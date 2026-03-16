import Caches
import Foundation
@testable import ImageCache
import Networks
import Testing

@Suite("CacheStoragePolicy")
struct StoragePolicyTests {
    // MARK: - .all

    @Test(".all: 로드 후 DiskCache에 데이터 저장")
    func persistsToDiskForAllPolicy() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let disk = try DiskCache(
            configuration: .init(directoryName: "StoragePolicyTests-all-\(UUID().uuidString)")
        )
        defer { try? disk.removeAll() }
        let hybrid = HybridCache(disk: disk)
        let sut = ImageCache(
            dataStore: hybrid,
            configuration: ImageCache.Configuration(httpClient: httpClient)
        )

        // When
        let url = URL(string: "https://example.com/all.png")!
        _ = try await sut.loadImage(from: url)

        // Then
        let stored = try disk.value(for: url.absoluteString)
        #expect(stored != nil)
        #expect(await transport.callCount() == 1)
    }

    // MARK: - .memoryOnly

    @Test(".memoryOnly: 로드 후 DiskCache에 데이터 없음")
    func keepsDataOffDiskForMemoryOnlyPolicy() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let disk = try DiskCache(
            configuration: .init(directoryName: "StoragePolicyTests-mem-\(UUID().uuidString)")
        )
        defer { try? disk.removeAll() }
        let memoryDataStore = MemoryImageDataStore()
        let sut = ImageCache(
            dataStore: memoryDataStore,
            configuration: ImageCache.Configuration(httpClient: httpClient)
        )

        // When
        let url = URL(string: "https://example.com/mem.png")!
        _ = try await sut.loadImage(from: url)
        _ = try await sut.loadImage(from: url)

        // Then
        let stored = try disk.value(for: url.absoluteString)
        #expect(stored == nil)
        #expect(await transport.callCount() == 1)
    }
}
