import Foundation
import CryptoKit

import Common

/// 디스크 캐시
///
/// 데이터 파일과 메타데이터 파일 분리 저장
/// `countLimit` 제거는 `lastWrite` 기준 LRW
/// `writeBuffer` 사용 시 배치 flush 지원
public final class DiskCache: Sendable {
    /// write buffer 설정
    public struct WriteBufferConfiguration: Sendable {
        /// 자동 flush 간격
        public let flushInterval: TimeInterval
        /// 강제 flush 전 최대 pending 항목 수
        public let maxPendingCount: Int

        /// write buffer 설정을 생성
        ///
        /// - Parameters:
        ///   - flushInterval: 자동 flush 간격
        ///   - maxPendingCount: 강제 flush 전 최대 pending 항목 수
        public init(
            flushInterval: TimeInterval = 5,
            maxPendingCount: Int = 50
        ) {
            self.flushInterval = flushInterval
            self.maxPendingCount = maxPendingCount
        }
    }

    /// 디스크 캐시 설정
    public struct Configuration: Sendable {
        /// 캐시 디렉터리 이름
        public let directoryName: String
        /// 파일 보호 옵션
        public let fileProtection: FileProtectionType?
        /// write buffer 설정
        public let writeBuffer: WriteBufferConfiguration?

        /// 디스크 캐시 설정을 생성
        ///
        /// - Parameters:
        ///   - directoryName: 캐시 디렉터리 이름
        ///   - fileProtection: 파일 보호 옵션
        ///   - writeBuffer: write buffer 설정
        public init(
            directoryName: String = "Caches.DiskCache",
            fileProtection: FileProtectionType? = nil,
            writeBuffer: WriteBufferConfiguration? = nil
        ) {
            self.directoryName = directoryName
            self.fileProtection = fileProtection
            self.writeBuffer = writeBuffer
        }
    }

    /// 디스크 캐시 생성 에러
    public enum Error: Swift.Error {
        /// 기본 캐시 디렉터리를 찾지 못한 경우
        case baseDirectoryUnavailable
        /// 캐시 디렉터리 생성에 실패한 경우
        case directoryCreationFailed
    }

    private final class WriteBuffer: Sendable {
        private struct PendingEntry: Sendable {
            let data: Data
            let policy: CachePolicy
            let expiresAt: Date?
        }

        private struct State: Sendable {
            var pending: [String: PendingEntry] = [:]
            var scheduledFlushToken: UUID?
            /// flush 스냅샷 이후 removeValue가 호출된 키
            var deletedKeys: Set<String> = []
            /// removeAllPending 호출 시 증가 (진행 중인 flush 스냅샷을 무효화)
            var generation: UInt64 = 0
        }

        private let state = LockIsolated(State())
        private let writeAction: @Sendable (String, Data, CachePolicy) throws -> Void
        private let flushInterval: TimeInterval
        private let maxPendingCount: Int
        private let ioQueue = DispatchQueue(label: "core.caches.disk_write_batch.io", qos: .utility)
        private let timerQueue = DispatchQueue(label: "core.caches.disk_write_batch.timer", qos: .utility)

        init(
            writeAction: @escaping @Sendable (String, Data, CachePolicy) throws -> Void,
            configuration: WriteBufferConfiguration
        ) {
            self.writeAction = writeAction
            flushInterval = max(0.1, configuration.flushInterval)
            maxPendingCount = max(1, configuration.maxPendingCount)
        }

        func enqueue(key: String, data: Data, policy: CachePolicy) {
            let now = Date()
            let shouldFlush = state.withValue { state in
                // 새 쓰기가 들어오면 이전 삭제 의사를 취소
                state.deletedKeys.remove(key)
                state.pending[key] = PendingEntry(
                    data: data,
                    policy: policy,
                    expiresAt: policy.expiration.expiresAt(now: now)
                )
                return state.pending.count >= maxPendingCount
            }

            if shouldFlush {
                Task { await flush() }
            } else {
                scheduleFlush()
            }
        }

        func pendingValue(for key: String) -> Data? {
            let now = Date()
            return state.withValue { state in
                guard let entry = state.pending[key] else { return nil }
                if let expiresAt = entry.expiresAt, now >= expiresAt {
                    state.pending.removeValue(forKey: key)
                    return nil
                }
                return entry.data
            }
        }

        func hasPending(_ key: String) -> Bool {
            pendingValue(for: key) != nil
        }

        func removePending(key: String) {
            state.withValue { state in
                if state.pending.removeValue(forKey: key) == nil {
                    // pending에 없으면 flush 스냅샷에 포함됐을 수 있으므로 tombstone 기록
                    state.deletedKeys.insert(key)
                }
            }
        }

        func removeAllPending() {
            state.withValue { state in
                state.pending = [:]
                state.scheduledFlushToken = nil
                // generation 증가로 진행 중인 flush 스냅샷 전체를 무효화
                state.generation &+= 1
                state.deletedKeys = []
            }
        }

        func removeExpiredPending() {
            let now = Date()
            state.withValue { state in
                state.pending = state.pending.filter { _, entry in
                    guard let expiresAt = entry.expiresAt else { return true }
                    return now < expiresAt
                }
            }
        }

        func flush() async {
            let (snapshot, generation) = state.withValue { state -> ([String: PendingEntry], UInt64) in
                state.scheduledFlushToken = nil
                guard !state.pending.isEmpty else { return ([:], state.generation) }
                let current = state.pending
                state.pending = [:]
                return (current, state.generation)
            }
            guard !snapshot.isEmpty else { return }

            let now = Date()
            let action = writeAction
            await withCheckedContinuation { continuation in
                ioQueue.async { [state] in
                    // generation 불일치 여부와 tombstone 집합을 한 번에 읽어 루프 내 락 제거
                    // tombstones는 이 시점 스냅샷이므로 IO 중 추가된 삭제는 놓칠 수 있으나,
                    // 이미지 캐시에서 허용 가능한 미미한 레이스 (다음 읽기 시 손상 감지 -> 자동 정리)
                    let (isValid, tombstones) = state.withValue { s in
                        (s.generation == generation, s.deletedKeys)
                    }
                    guard isValid else {
                        continuation.resume()
                        return
                    }
                    for (key, entry) in snapshot {
                        if tombstones.contains(key) { continue }
                        if let expiresAt = entry.expiresAt, now >= expiresAt { continue }
                        do {
                            try action(key, entry.data, entry.policy)
                        } catch {
                            AppLogger.caches.error(
                                "키 \(key) write buffer flush 실패: \(String(describing: error))"
                            )
                        }
                    }
                    // 이번 flush가 처리한 키의 tombstone 정리
                    state.withValue { s in
                        if s.generation == generation {
                            s.deletedKeys.subtract(snapshot.keys)
                        }
                    }
                    continuation.resume()
                }
            }
        }

        private func scheduleFlush() {
            let token = UUID()
            state.withValue { state in
                state.scheduledFlushToken = token
            }
            let interval = flushInterval
            timerQueue.asyncAfter(deadline: .now() + interval) { [weak self] in
                guard let self else { return }
                let shouldFlush = self.state.withValue { state in
                    guard state.scheduledFlushToken == token else { return false }
                    state.scheduledFlushToken = nil
                    return !state.pending.isEmpty
                }
                guard shouldFlush else { return }
                Task { await self.flush() }
            }
        }
    }

    private let cacheDirectory: URL
    private let fileProtection: FileProtectionType?
    private let writeBuffer = LockIsolated<WriteBuffer?>(nil)

    /// 디스크 캐시 초기화
    ///
    /// - Parameter configuration: 캐시 디렉터리 및 보호 옵션
    /// - Throws: 기본 캐시 디렉터리를 찾지 못하거나 생성에 실패한 경우
    public init(configuration: Configuration = Configuration()) throws {
        fileProtection = configuration.fileProtection
        let fileManager = FileManager.default
        guard let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { throw Error.baseDirectoryUnavailable }

        let directory = baseURL.appendingPathComponent(configuration.directoryName, isDirectory: true)
        cacheDirectory = directory

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Error.directoryCreationFailed
        }

        if let writeBuffer = configuration.writeBuffer {
            enableWriteBufferIfNeeded(configuration: writeBuffer)
        }
    }

    private func enableWriteBufferIfNeeded(configuration: WriteBufferConfiguration) {
        writeBuffer.withValue { buffer in
            guard buffer == nil else { return }
            let action: @Sendable (String, Data, CachePolicy) throws -> Void = { [weak self] key, data, policy in
                try self?.setImmediate(data, for: key, policy: policy)
            }
            buffer = WriteBuffer(writeAction: action, configuration: configuration)
        }
    }

    /// 데이터 저장
    ///
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 캐시 키
    ///   - policy: 만료/제거 정책
    /// - Throws: 파일 쓰기 또는 메타데이터 저장 실패
    public func set(
        _ data: Data,
        for key: String,
        policy: CachePolicy = .default
    ) throws {
        if let buffer = writeBuffer.withValue({ $0 }) {
            buffer.enqueue(key: key, data: data, policy: policy)
            return
        }
        try setImmediate(data, for: key, policy: policy)
    }

    /// 데이터 조회
    ///
    /// - Parameters:
    ///   - key: 조회할 키
    ///   - policy: 만료/제거 정책
    /// - Returns: 저장된 데이터. 만료되었거나 없으면 nil
    /// - Throws: 파일 읽기 또는 메타데이터 디코딩 실패
    ///
    /// 조회 시 `CachePolicy`는 사용하지 않음
    /// 만료 판단은 저장 시 기록한 `expiresAt` 기준
    /// 읽기 시 `lastWrite` 미갱신
    public func value(
        for key: String,
        _: CachePolicy = .default
    ) throws -> Data? {
        if let pending = writeBuffer.withValue({ $0?.pendingValue(for: key) }) {
            return pending
        }
        let fileManager = FileManager.default
        let (fileURL, metadataURL) = cacheURLs(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        if let metadata = try loadMetadata(at: metadataURL, dataURL: fileURL) {
            if metadata.isExpired {
                try removeEntry(dataURL: fileURL, metadataURL: metadataURL)
                return nil
            }
        } else {
            // 메타데이터 누락 시 데이터 파일 재확인
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        }
        // 읽기 시 lastWrite 미갱신
        return try Data(contentsOf: fileURL)
    }

    /// 키 삭제
    ///
    /// - Parameter key: 삭제할 키
    /// - Throws: 파일 삭제 실패
    public func removeValue(for key: String) throws {
        writeBuffer.withValue { $0?.removePending(key: key) }
        let (fileURL, metadataURL) = cacheURLs(for: key)
        try removeEntry(dataURL: fileURL, metadataURL: metadataURL)
    }

    /// 전체 삭제
    ///
    /// - Throws: 디렉터리 열기 또는 파일 삭제 실패
    public func removeAll() throws {
        writeBuffer.withValue { $0?.removeAllPending() }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// 만료 항목 삭제
    ///
    /// - Throws: 메타데이터 읽기 또는 삭제 실패
    public func removeExpired() throws {
        writeBuffer.withValue { $0?.removeExpiredPending() }
        for entry in try allMetadataEntries() where entry.metadata.isExpired {
            try removeEntry(dataURL: entry.dataURL, metadataURL: entry.metadataURL)
        }
    }

    /// 키 존재 여부
    ///
    /// - Parameter key: 확인할 키
    /// - Returns: 존재하고 만료되지 않은 경우 true
    public func contains(_ key: String) -> Bool {
        if writeBuffer.withValue({ $0?.hasPending(key) ?? false }) { return true }
        let fileManager = FileManager.default
        let (fileURL, metadataURL) = cacheURLs(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        if let metadata = try? loadMetadata(at: metadataURL, dataURL: fileURL), metadata.isExpired { return false }
        return true
    }

    /// pending 쓰기를 즉시 flush
    public func flushPendingWrites() async {
        guard let writeBuffer = writeBuffer.withValue({ $0 }) else { return }
        await writeBuffer.flush()
    }
}

private extension DiskCache {
    func setImmediate(
        _ data: Data,
        for key: String,
        policy: CachePolicy = .default
    ) throws {
        let (fileURL, metadataURL) = cacheURLs(for: key)
        let tempDataURL = fileURL.appendingPathExtension("tmp")
        let tempMetadataURL = metadataURL.appendingPathExtension("tmp")
        let fileManager = FileManager.default

        // 임시 파일 정리
        try? fileManager.removeItem(at: tempDataURL)
        try? fileManager.removeItem(at: tempMetadataURL)

        do {
            // 데이터 파일 기록
            let options = writeOptions()
            try data.write(to: tempDataURL, options: options)

            // 메타데이터 파일 기록
            let metadata = CacheMetadata(
                expiresAt: policy.expiration.expiresAt(),
                lastWrite: Date()
            )
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: tempMetadataURL, options: options)

            // 최종 파일 교체
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: metadataURL)

            try fileManager.moveItem(at: tempDataURL, to: fileURL)
            try fileManager.moveItem(at: tempMetadataURL, to: metadataURL)

            try evictIfNeeded(policy: policy)
        } catch {
            // 실패 시 임시 파일 정리
            try? fileManager.removeItem(at: tempDataURL)
            try? fileManager.removeItem(at: tempMetadataURL)
            throw error
        }
    }

    /// 데이터 / 메타데이터 URL 생성
    func cacheURLs(for key: String) -> (dataURL: URL, metadataURL: URL) {
        let name = hashedFileName(for: key)
        return (
            cacheDirectory.appendingPathComponent(name),
            cacheDirectory.appendingPathComponent("\(name).meta")
        )
    }

    func hashedFileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func writeOptions() -> Data.WritingOptions {
        switch fileProtection {
        case .some(.complete):                             return [.atomic, .completeFileProtection]
        case .some(.completeUnlessOpen):                   return [.atomic, .completeFileProtectionUnlessOpen]
        case .some(.completeUntilFirstUserAuthentication): return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        default:                                           return .atomic
        }
    }

    /// 메타데이터 로드
    func loadMetadata(at metadataURL: URL, dataURL: URL) throws -> CacheMetadata? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
        let data = try Data(contentsOf: metadataURL)
        do {
            return try JSONDecoder().decode(CacheMetadata.self, from: data)
        } catch {
            // 손상 메타데이터 정리
            AppLogger.caches.warning(
                "손상된 메타데이터 \(metadataURL.lastPathComponent) 감지. 캐시 엔트리 삭제: \(String(describing: error))"
            )
            try? fileManager.removeItem(at: metadataURL)
            try? fileManager.removeItem(at: dataURL)
            return nil
        }
    }

    /// 전체 메타데이터 엔트리 조회
    ///
    /// 손상 엔트리 발견 시 자동 정리
    func allMetadataEntries() throws -> [MetadataEntry] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )

        return contents.compactMap { url in
            guard url.pathExtension == "meta" else { return nil }
            do {
                let data = try Data(contentsOf: url)
                let metadata = try JSONDecoder().decode(CacheMetadata.self, from: data)
                let dataURL = url.deletingPathExtension()
                return MetadataEntry(dataURL: dataURL, metadataURL: url, metadata: metadata)
            } catch {
                // 손상 엔트리 정리
                let dataURL = url.deletingPathExtension()
                AppLogger.caches.warning(
                    "손상된 메타데이터 \(url.lastPathComponent) 감지. 엔트리 삭제: \(String(describing: error))"
                )
                try? fileManager.removeItem(at: url)
                try? fileManager.removeItem(at: dataURL)
                return nil
            }
        }
    }

    func evictIfNeeded(policy: CachePolicy) throws {
        if case .costLimit = policy.eviction {
            AppLogger.caches.warning("DiskCache는 costLimit eviction을 지원하지 않음. countLimit 사용")
            return
        }
        guard case let .countLimit(limit) = policy.eviction, limit >= 0 else { return }
        var entries = try allMetadataEntries()
        guard entries.count > limit else { return }

        entries.sort { $0.metadata.lastWrite < $1.metadata.lastWrite }
        let removeCount = entries.count - limit
        for entry in entries.prefix(removeCount) {
            try removeEntry(dataURL: entry.dataURL, metadataURL: entry.metadataURL)
        }
    }

    func removeEntry(dataURL: URL, metadataURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dataURL.path) {
            try fileManager.removeItem(at: dataURL)
        }
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
    }
}

private struct MetadataEntry {
    let dataURL: URL
    let metadataURL: URL
    let metadata: CacheMetadata
}
