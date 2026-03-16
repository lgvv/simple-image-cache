import Foundation
@testable import ImageCache
import Networks
import Testing

/// `.all` / `.memoryOnly` 정책 테스트
///
/// 두 정책 모두 커스텀 디스크/메모리 스토어를 사용하며 URLCache와 무관하다
@Suite
struct ImageCacheClientLocalStoragePolicyTests {
    @Test(".all 정책은 클라이언트 인스턴스가 달라도 캐시를 재사용")
    func reusesCacheAcrossClientInstancesForAllPolicy() async {
        // Given
        let url = makeStoragePolicyImageURL(prefix: "all")
        let seedClient = makeStoragePolicyClient(
            storagePolicy: .all,
            transport: StaticImageTransport(data: makePNGData())
        )

        // When
        let seededImage = await seedClient.loadImage(url)
        #expect(seededImage != nil)

        let reloadedClient = makeStoragePolicyClient(
            storagePolicy: .all,
            transport: AlwaysFailTransport()
        )
        let cachedImage = await reloadedClient.loadImage(url)

        // Then
        #expect(cachedImage != nil)
    }

    @Test(".memoryOnly 정책은 클라이언트 인스턴스 간 캐시를 공유 안 함")
    func doesNotShareCacheAcrossClientInstancesForMemoryOnlyPolicy() async {
        // Given
        let url = makeStoragePolicyImageURL(prefix: "memory-only")
        let seedClient = makeStoragePolicyClient(
            storagePolicy: .memoryOnly,
            transport: StaticImageTransport(data: makePNGData())
        )

        // When
        let seededImage = await seedClient.loadImage(url)
        #expect(seededImage != nil)

        let reloadedClient = makeStoragePolicyClient(
            storagePolicy: .memoryOnly,
            transport: AlwaysFailTransport()
        )
        let reloadedImage = await reloadedClient.loadImage(url)

        // Then
        #expect(reloadedImage == nil)
    }
}
