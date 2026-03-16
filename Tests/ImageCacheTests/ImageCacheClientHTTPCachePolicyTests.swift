import Foundation
@testable import ImageCache
import Networks
import Testing

/// `.httpCache` / `.httpCacheMemoryOnly` 정책 테스트
///
/// 두 정책 모두 URLSession 내장 URLCache를 사용해 HTTP 캐시 헤더를 준수한다
/// 차이점: `.httpCache`는 외부 URLCache를 공유하고, `.httpCacheMemoryOnly`는
/// 자체 메모리 전용 URLCache를 생성해 인스턴스 간 캐시를 공유 안 함
@Suite
struct ImageCacheClientHTTPCachePolicyTests {
    // MARK: - .httpCache

    @Test(".httpCache 정책은 URLCache를 통해 클라이언트 간 캐시를 재사용")
    func reusesURLCacheAcrossClientInstancesForHTTPCachePolicy() async {
        // Given
        let isolatedCache = makeIsolatedURLCache()
        let url = makeStoragePolicyImageURL(prefix: "http-cache")
        seedURLCache(isolatedCache, for: url, data: makePNGData())

        let seedClient = makeStoragePolicyClient(storagePolicy: .httpCache, urlCache: isolatedCache)

        // When
        let seededImage = await seedClient.loadImage(url)
        #expect(seededImage != nil)

        let reloadedClient = makeStoragePolicyClient(storagePolicy: .httpCache, urlCache: isolatedCache)
        let cachedImage = await reloadedClient.loadImage(url)

        // Then
        #expect(cachedImage != nil)
    }

    @Test(".httpCache 정책은 ETag 재검증 시 URLCache가 304를 내부에서 처리해 이미지를 정상 반환")
    func handlesETagRevalidationWithStatusCodeMiddlewareForHTTPCachePolicy() async throws {
        // Given
        let isolatedCache = makeIsolatedURLCache()
        let server = try await LocalETagHTTPServer.start(responseData: makePNGData())
        defer { server.stop() }

        let seedClient = makeStoragePolicyClient(
            storagePolicy: .httpCache,
            middlewares: [StatusCodeValidationMiddleware()],
            urlCache: isolatedCache
        )

        let reloadedClient = makeStoragePolicyClient(
            storagePolicy: .httpCache,
            middlewares: [StatusCodeValidationMiddleware()],
            urlCache: isolatedCache
        )

        // When
        let seededImage = await seedClient.loadImage(server.imageURL)
        let cachedImage = await reloadedClient.loadImage(server.imageURL)
        let requests = await server.requests()

        // Then: 공유 URLCache가 ETag를 저장 -> 두 번째 요청에서 If-None-Match 재검증
        #expect(seededImage != nil)
        #expect(cachedImage != nil)
        #expect(requests.count == 2)
        #expect(requests.last?.ifNoneMatch == LocalETagHTTPServer.etag)
    }

    // MARK: - .httpCacheMemoryOnly

    @Test(".httpCacheMemoryOnly 정책은 configuration.urlCache를 무시하고 자체 URLCache를 사용")
    func ignoresConfigurationURLCacheForHTTPCacheMemoryOnlyPolicy() async {
        // Given: isolatedCache에 이미지를 미리 심어둔 뒤 urlCache로 전달
        let isolatedCache = makeIsolatedURLCache()
        let url = makeStoragePolicyImageURL(prefix: "http-cache-memory-only-ignored")
        seedURLCache(isolatedCache, for: url, data: makePNGData())

        // .httpCacheMemoryOnly 정책은 configuration.urlCache를 무시하고
        // 자체 메모리 전용 URLCache(50 MB, 디스크 0)를 새로 생성
        let client = makeStoragePolicyClient(storagePolicy: .httpCacheMemoryOnly, urlCache: isolatedCache)

        // When: 자체 URLCache(비어 있음)를 사용하고 .invalid TLD라 네트워크도 실패
        let image = await client.loadImage(url)

        // Then: isolatedCache의 데이터는 참조되지 않으므로 nil
        #expect(image == nil)
    }

    @Test(".httpCacheMemoryOnly 정책은 인스턴스 간 URLCache를 공유 안 함")
    func doesNotShareURLCacheAcrossClientInstancesForHTTPCacheMemoryOnlyPolicy() async throws {
        // Given: 각 클라이언트가 자체 URLCache를 사용하는지 확인하기 위해 실제 서버를 사용
        let server = try await LocalETagHTTPServer.start(responseData: makePNGData())
        defer { server.stop() }

        // 두 클라이언트는 각각 독립된 메모리 전용 URLCache를 가진다
        let client1 = makeStoragePolicyClient(
            storagePolicy: .httpCacheMemoryOnly,
            middlewares: [StatusCodeValidationMiddleware()]
        )
        let client2 = makeStoragePolicyClient(
            storagePolicy: .httpCacheMemoryOnly,
            middlewares: [StatusCodeValidationMiddleware()]
        )

        // When
        let image1 = await client1.loadImage(server.imageURL)
        let image2 = await client2.loadImage(server.imageURL)
        let requests = await server.requests()

        // Then: client2는 client1의 URLCache를 공유하지 않으므로
        // 캐시 항목이 없는 상태에서 새 GET 요청을 전송한다 -> If-None-Match 없음
        // (.httpCache와 달리 두 번째 요청에 ETag 재검증은 없음)
        #expect(image1 != nil)
        #expect(image2 != nil)
        #expect(requests.count == 2)
        #expect(requests.last?.ifNoneMatch == nil)
    }
}
