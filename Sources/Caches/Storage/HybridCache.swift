import Foundation

/// 메모리 / 디스크 하이브리드 캐시
///
/// 조회 순서: 메모리 -> 디스크
/// 디스크 조회 성공 시 메모리 승격
public final class HybridCache: Sendable {
    private let memory: MemoryCache
    private let disk: DiskCache
    private let policy: CachePolicy

    /// 하이브리드 캐시를 생성
    ///
    /// - Parameters:
    ///   - memory: 메모리 캐시
    ///   - disk: 디스크 캐시
    ///   - policy: 기본 캐시 정책
    public init(
        memory: MemoryCache = MemoryCache(),
        disk: DiskCache,
        policy: CachePolicy = .default
    ) {
        self.memory = memory
        self.disk = disk
        self.policy = policy
    }

    /// 데이터 저장
    ///
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 캐시 키
    ///   - policy: 만료 / 제거 정책 / 기본값은 인스턴스 정책
    public func set(_ data: Data, for key: String, policy: CachePolicy = .default) async throws {
        let effective = effectivePolicy(for: policy)
        // 쓰기와 이전 값 조회를 단일 락으로 처리(중복 락 없음)
        let previous = memory.setReturningPrevious(data, for: key, policy: effective)
        do {
            try disk.set(data, for: key, policy: effective)
        } catch {
            // 디스크 실패 시 메모리 롤백(기존 값이 있었다면 복원)
            if let previous {
                memory.set(previous, for: key, policy: effective)
            } else {
                memory.removeValue(for: key)
            }
            throw error
        }
    }

    /// 데이터 조회
    ///
    /// - Parameters:
    ///   - key: 조회할 키
    ///   - policy: 만료 / 제거 정책 / 기본값은 인스턴스 정책
    /// - Returns: 저장된 데이터. 만료되었거나 없으면 nil
    public func value(for key: String, policy: CachePolicy = .default) async throws -> Data? {
        let effective = effectivePolicy(for: policy)
        if let data = memory.value(for: key, policy: effective) {
            return data
        }
        if let data = try disk.value(for: key) {
            // 디스크 조회 성공 시 메모리 승격
            memory.set(data, for: key, policy: effective)
            return data
        }
        return nil
    }

    /// 키 삭제
    ///
    /// 메모리 / 디스크 독립 삭제
    public func removeValue(for key: String) async throws {
        memory.removeValue(for: key)
        try disk.removeValue(for: key)
    }

    /// 전체 삭제
    public func removeAll() async throws {
        memory.removeAll()
        try disk.removeAll()
    }

    /// 메모리 캐시만 비움
    public func removeMemory() async {
        memory.removeAll()
    }

    /// 만료 항목 삭제
    public func removeExpired() async throws {
        memory.removeExpired()
        try disk.removeExpired()
    }

    /// 키 존재 여부
    ///
    /// - Parameter key: 확인할 키
    /// - Returns: 존재하면 true
    public func contains(_ key: String) async -> Bool {
        memory.contains(key) || disk.contains(key)
    }

    /// 배치 쓰기 flush
    public func flush() async {
        await disk.flushPendingWrites()
    }
}

// MARK: - Private Helpers

private extension HybridCache {
    func effectivePolicy(for policy: CachePolicy) -> CachePolicy {
        policy == .default ? self.policy : policy
    }
}
