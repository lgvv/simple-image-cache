@testable import Caches
import Foundation
import Testing

@Suite
struct DiskCacheTests {
    @Test("디스크 캐시에 저장 후 다시 조회 가능")
    func storesAndLoadsValue() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let key = "disk.key"
        let data = Data("value".utf8)

        // When
        try sut.set(data, for: key)
        let result = try sut.value(for: key)

        // Then
        #expect(result == data)
    }

    @Test("만료된 항목은 조회 시 nil")
    func returnsNilForExpiredEntry() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let key = "disk.expired"
        let data = Data("value".utf8)
        let policy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))

        // When
        try sut.set(data, for: key, policy: policy)
        let result = try sut.value(for: key)

        // Then
        #expect(result == nil)
    }

    @Test("countLimit 정책은 오래된 항목 제거")
    func evictsOldestEntryForCountLimit() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let policy = CachePolicy(eviction: .countLimit(1))
        let dataA = Data("A".utf8)
        let dataB = Data("B".utf8)

        // When
        try sut.set(dataA, for: "A", policy: policy)
        try sut.set(dataB, for: "B", policy: policy)

        // Then
        #expect(try sut.value(for: "A") == nil)
        #expect(try sut.value(for: "B") == dataB)
    }

    @Test("removeExpired는 만료된 항목만 삭제")
    func removesOnlyExpiredEntries() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let expiredPolicy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))
        try sut.set(Data("A".utf8), for: "A", policy: expiredPolicy)
        try sut.set(Data("B".utf8), for: "B")

        // When
        try sut.removeExpired()

        // Then
        #expect(try sut.value(for: "A") == nil)
        #expect(try sut.value(for: "B") == Data("B".utf8))
    }

    @Test("DiskCache LRU는 조회가 아닌 마지막 쓰기 시각 기준 동작")
    func evictsLeastRecentlyWrittenEntry() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let policy = CachePolicy(eviction: .countLimit(2))
        try sut.set(Data("A".utf8), for: "A", policy: policy)
        try sut.set(Data("B".utf8), for: "B", policy: policy)

        // When
        _ = try sut.value(for: "A")
        try sut.set(Data("C".utf8), for: "C", policy: policy)

        // Then
        #expect(try sut.value(for: "A") == nil)
        #expect(try sut.value(for: "B") != nil)
        #expect(try sut.value(for: "C") != nil)
    }

    @Test("removeValue는 데이터와 메타데이터를 제거")
    func removesValueAndMetadata() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let key = "disk.remove"
        let data = Data("value".utf8)
        try sut.set(data, for: key)

        // When
        try sut.removeValue(for: key)

        // Then
        #expect(try sut.value(for: key) == nil)
        #expect(sut.contains(key) == false)
    }

    @Test("countLimit 0이면 저장 후 바로 제거")
    func removesEntryImmediatelyForZeroCountLimit() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let policy = CachePolicy(eviction: .countLimit(0))

        // When
        try sut.set(Data("A".utf8), for: "A", policy: policy)

        // Then
        #expect(try sut.value(for: "A") == nil)
    }

    @Test("존재하지 않는 키 조회는 nil")
    func returnsNilForMissingKey() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }

        // When
        let result = try sut.value(for: "nonexistent")

        // Then
        #expect(result == nil)
    }

    @Test("contains는 존재하는 키 확인")
    func reportsWhetherKeyExists() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let key = "test.key"
        try sut.set(Data("value".utf8), for: key)

        // When
        let exists = sut.contains(key)
        let notExists = sut.contains("nonexistent")

        // Then
        #expect(exists == true)
        #expect(notExists == false)
    }

    @Test("removeAll은 모든 캐시 항목 제거")
    func removesAllEntries() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        try sut.set(Data("A".utf8), for: "A")
        try sut.set(Data("B".utf8), for: "B")

        // When
        try sut.removeAll()

        // Then
        #expect(try sut.value(for: "A") == nil)
        #expect(try sut.value(for: "B") == nil)
    }

    @Test("큰 데이터 저장 및 조회")
    func storesAndLoadsLargeData() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let largeData = Data(repeating: 0xFF, count: 10 * 1024 * 1024) // 10MB

        // When
        try sut.set(largeData, for: "large")
        let result = try sut.value(for: "large")

        // Then
        #expect(result == largeData)
    }

    @Test("writeBuffer 활성 시 set 직후 value는 pending에서 조회 가능")
    func readsPendingWriteBeforeFlush() async throws {
        // Given
        let directory = "CacheTests.Buffered.\(UUID().uuidString)"
        let sut = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observer = try makeDiskCache(directory: directory)
        defer { try? sut.removeAll() }

        let key = "disk.buffer.pending"
        let data = Data("value".utf8)

        // When
        try await sut.set(data, for: key)

        // Then
        #expect(try await sut.value(for: key) == data)
        #expect(try await observer.value(for: key) == nil)
    }

    @Test("writeBuffer 활성 시 flushPendingWrites 후 디스크 반영")
    func flushesPendingWritesToDisk() async throws {
        // Given
        let directory = "CacheTests.Buffered.\(UUID().uuidString)"
        let sut = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observer = try makeDiskCache(directory: directory)
        defer { try? sut.removeAll() }

        let key = "disk.buffer.flush"
        let data = Data("value".utf8)
        try await sut.set(data, for: key)

        // When
        await sut.flushPendingWrites()

        // Then
        #expect(try await observer.value(for: key) == data)
    }

    @Test("writeBuffer flush 시 만료된 pending 항목 제외")
    func skipsExpiredPendingWritesDuringFlush() async throws {
        // Given
        let directory = "CacheTests.Buffered.\(UUID().uuidString)"
        let sut = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observer = try makeDiskCache(directory: directory)
        defer { try? sut.removeAll() }

        let key = "disk.buffer.expired"
        let policy = CachePolicy(expiration: .seconds(0.05))
        try await sut.set(Data("value".utf8), for: key, policy: policy)

        // When
        try await Task.sleep(nanoseconds: 120_000_000)
        await sut.flushPendingWrites()

        // Then
        #expect(try await observer.value(for: key) == nil)
        #expect(try await sut.value(for: key) == nil)
    }

    @Test("writeBuffer 비활성 기본 설정은 바로 디스크 반영")
    func persistsImmediatelyWhenWriteBufferDisabled() throws {
        // Given
        let directory = "CacheTests.Buffered.\(UUID().uuidString)"
        let sut = try makeDiskCache(directory: directory, writeBuffer: nil)
        let observer = try makeDiskCache(directory: directory, writeBuffer: nil)
        defer { try? sut.removeAll() }

        let key = "disk.immediate.default"
        let data = Data("value".utf8)

        // When
        try sut.set(data, for: key)

        // Then
        #expect(try observer.value(for: key) == data)
    }

    @Test("writeBuffer 활성 상태에서 removeValue는 pending까지 함께 제거")
    func removesPendingWriteWhenValueIsDeleted() async throws {
        // Given
        let directory = "CacheTests.Buffered.\(UUID().uuidString)"
        let sut = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observer = try makeDiskCache(directory: directory)
        defer { try? sut.removeAll() }

        let key = "disk.buffer.remove.pending"
        try await sut.set(Data("value".utf8), for: key)

        // When
        try await sut.removeValue(for: key)
        await sut.flushPendingWrites()

        // Then
        #expect(await sut.contains(key) == false)
        #expect(try await observer.value(for: key) == nil)
    }

    @Test("음수 countLimit은 eviction을 수행 안 함")
    func ignoresNegativeCountLimit() throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }
        let policy = CachePolicy(eviction: .countLimit(-5))

        // When
        try sut.set(Data("A".utf8), for: "A", policy: policy)
        try sut.set(Data("B".utf8), for: "B", policy: policy)

        // Then - 음수 limit이므로 eviction 없이 모든 항목 유지
        #expect(try sut.value(for: "A") == Data("A".utf8))
        #expect(try sut.value(for: "B") == Data("B".utf8))
    }

    @Test("동시에 서로 다른 키에 set을 호출해도 크래시 없이 모든 값 유효")
    func keepsDistinctConcurrentWritesValid() async throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }

        // When - 20개 서로 다른 키에 동시 쓰기
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    try sut.set(Data("value\(i)".utf8), for: "concurrent.\(i)")
                }
            }
        }

        // Then - 모든 키에 유효한 데이터 존재
        for i in 0 ..< 20 {
            let result = try sut.value(for: "concurrent.\(i)")
            #expect(result != nil)
            #expect(String(data: result!, encoding: .utf8) == "value\(i)")
        }
    }

    @Test("동시 set과 value가 뒤섞여도 크래시 없음")
    func remainsSafeDuringConcurrentReadsAndWrites() async throws {
        // Given
        let sut = try makeDiskCache()
        defer { try? sut.removeAll() }

        // When - 동시 쓰기/읽기/삭제
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 30 {
                group.addTask {
                    let key = "key.\(i % 5)"
                    try sut.set(Data("v\(i)".utf8), for: key)
                    _ = try sut.value(for: key)
                    if i % 4 == 0 { try sut.removeValue(for: key) }
                }
            }
        }

        // Then - 크래시 없이 완료
        try sut.removeAll()
        #expect(sut.contains("key.0") == false)
    }

    @Test("손상된 메타데이터 파일은 자동 복구(삭제)")
    func recoversFromCorruptedMetadata() throws {
        // Given
        let directory = "CacheTests.Corrupt.\(UUID().uuidString)"
        let sut = try makeDiskCache(directory: directory)
        defer { try? sut.removeAll() }

        // 정상 데이터 저장
        let key = "corrupt.meta"
        let data = Data("value".utf8)
        try sut.set(data, for: key)
        #expect(try sut.value(for: key) == data)

        // 메타데이터 파일을 손상시킴
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheDir = baseURL.appendingPathComponent(directory, isDirectory: true)
        let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
        let metaFile = contents.first { $0.pathExtension == "meta" }!
        try Data("corrupted".utf8).write(to: metaFile)

        // When - 손상된 메타데이터로 조회 시도
        let result = try sut.value(for: key)

        // Then - 손상 감지 후 삭제되어 nil 반환
        #expect(result == nil)
        #expect(sut.contains(key) == false)
    }
}
