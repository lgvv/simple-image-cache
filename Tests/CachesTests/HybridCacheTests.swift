@testable import Caches
import Foundation
import Testing

@Suite
struct HybridCacheTests {
    @Test("하이브리드 캐시는 메모리 캐시 우선으로 반환")
    func returnsMemoryValueFirst() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.key"
        let data = Data("value".utf8)

        // When
        try await sut.set(data, for: key)
        let result = try await sut.value(for: key)

        // Then
        #expect(result == data)
    }

    @Test("디스크에만 있는 값은 조회 후 메모리에 적재")
    func loadsDiskValueIntoMemory() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.disk"
        let data = Data("value".utf8)
        try await disk.set(data, for: key)

        // When
        let result = try await sut.value(for: key)

        // Then
        #expect(result == data)
        #expect(memory.contains(key) == true)
    }

    @Test("removeAll은 메모리와 디스크 모두 삭제")
    func removesAllEntriesFromMemoryAndDisk() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.remove"
        let data = Data("value".utf8)
        try await sut.set(data, for: key)

        // When
        try await sut.removeAll()

        // Then
        #expect(memory.contains(key) == false)
        #expect(try await disk.value(for: key) == nil)
    }

    @Test("removeValue는 메모리와 디스크 모두 삭제")
    func removesSingleEntryFromMemoryAndDisk() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.remove.one"
        let data = Data("value".utf8)
        try await sut.set(data, for: key)

        // When
        try await sut.removeValue(for: key)

        // Then
        #expect(memory.contains(key) == false)
        #expect(try await disk.value(for: key) == nil)
    }

    @Test("contains는 디스크에만 있어도 true")
    func returnsTrueWhenEntryExistsOnlyOnDisk() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.contains"
        let data = Data("value".utf8)
        try await disk.set(data, for: key)

        // When
        let result = await sut.contains(key)

        // Then
        #expect(result == true)
    }

    @Test("removeExpired는 메모리와 디스크 모두 정리")
    func removesExpiredEntriesFromMemoryAndDisk() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let expiredPolicy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))
        let sut = HybridCache(memory: memory, disk: disk, policy: expiredPolicy)
        let key = "hybrid.expired"
        try await sut.set(Data("A".utf8), for: key)

        // When
        try await sut.removeExpired()

        // Then
        #expect(await sut.contains(key) == false)
    }

    @Test("디스크 쓰기는 flush 전까지 실제 디스크 파일 반영 지연")
    func delaysDiskWritesUntilFlush() async throws {
        // Given
        let directory = "CacheTests.Hybrid.Buffered.\(UUID().uuidString)"
        let writerDisk = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observerDisk = try makeDiskCache(directory: directory)
        defer { try? writerDisk.removeAll() }

        let memory = MemoryCache()
        let sut = HybridCache(memory: memory, disk: writerDisk)
        let key = "hybrid.pending"
        let data = Data("value".utf8)

        // When
        try await sut.set(data, for: key)

        // Then
        #expect(try await observerDisk.value(for: key) == nil)
        #expect(try await sut.value(for: key) == data)
    }

    @Test("flush 호출 시 pending 데이터가 디스크에 반영")
    func flushPersistsPendingDataToDisk() async throws {
        // Given
        let directory = "CacheTests.Hybrid.Flush.\(UUID().uuidString)"
        let writerDisk = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observerDisk = try makeDiskCache(directory: directory)
        defer { try? writerDisk.removeAll() }

        let sut = HybridCache(disk: writerDisk)
        let key = "hybrid.flush"
        let data = Data("value".utf8)
        try await sut.set(data, for: key)

        // When
        await sut.flush()

        // Then
        #expect(try await observerDisk.value(for: key) == data)
    }

    @Test("removeMemory는 메모리만 비우고 디스크 값은 유지")
    func clearsMemoryWhileKeepingDiskValue() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try makeDiskCache()
        defer { try? disk.removeAll() }
        let sut = HybridCache(memory: memory, disk: disk)
        let key = "hybrid.removeMemory"
        let data = Data("value".utf8)
        try await sut.set(data, for: key)

        // When
        await sut.removeMemory()

        // Then
        #expect(memory.contains(key) == false)
        #expect(try await disk.value(for: key) == data)
    }

    @Test("flush 시점에 만료된 pending 항목은 디스크에 쓰기 안 함")
    func skipsExpiredPendingEntriesDuringFlush() async throws {
        // Given
        let directory = "CacheTests.Hybrid.Expire.\(UUID().uuidString)"
        let writerDisk = try makeDiskCache(
            directory: directory,
            writeBuffer: .init(flushInterval: 60, maxPendingCount: 999)
        )
        let observerDisk = try makeDiskCache(directory: directory)
        defer { try? writerDisk.removeAll() }

        let sut = HybridCache(disk: writerDisk)
        let key = "hybrid.expire.before.flush"
        let policy = CachePolicy(expiration: .seconds(0.05))
        try await sut.set(Data("value".utf8), for: key, policy: policy)

        // When
        try await Task.sleep(nanoseconds: 120_000_000)
        await sut.flush()

        // Then
        #expect(try await observerDisk.value(for: key) == nil)
        #expect(try await sut.value(for: key, policy: policy) == nil)
    }
}
