import Foundation
@testable import ImageCache
import Networks
import Testing

/// `.none` 정책 테스트
///
/// URLCache, NSCache, 디코딩 캐시를 전부 우회해 매 요청마다 네트워크에서 새로 로드한다
/// URLCache에 응답이 심어져 있어도 참조 안 함
@Suite
struct ImageCacheClientNonePolicyTests {
    @Test("URLCache를 사용하지 않아 클라이언트 간 캐시를 재사용 안 함")
    func doesNotReuseCacheAcrossClientInstancesForNonePolicy() async {
        // Given: isolatedCache에 이미지를 미리 심어도 .none 정책은 참조 안 함
        let isolatedCache = makeIsolatedURLCache()
        let url = makeStoragePolicyImageURL(prefix: "none")
        seedURLCache(isolatedCache, for: url, data: makePNGData())

        let seedClient = makeStoragePolicyClient(storagePolicy: .none, urlCache: isolatedCache)

        // When
        let seededImage = await seedClient.loadImage(url)
        #expect(seededImage == nil)

        let reloadedClient = makeStoragePolicyClient(storagePolicy: .none, urlCache: isolatedCache)
        let reloadedImage = await reloadedClient.loadImage(url)

        // Then
        #expect(reloadedImage == nil)
    }
}
