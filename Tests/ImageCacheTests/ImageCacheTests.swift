import Caches
import Common
import Foundation
@testable import ImageCache
import Networks
import Testing

import UIKit

@Suite
struct ImageCacheTests {
    @Test("캐시 미스 시 네트워크 호출 후 캐시에 저장")
    func fetchesFromNetworkAndCachesOnCacheMiss() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let decoder = CountingDecoder()
        let sut = ImageCache(
            dataStore: cache,
            configuration: ImageCache.Configuration(
                httpClient: httpClient,
                decoder: decoder
            )
        )
        let url = URL(string: "https://example.com/1.png")!

        // When
        _ = try await sut.loadImage(from: url)
        _ = try await sut.loadImage(from: url)

        // Then
        #expect(await transport.callCount() == 1)
        #expect(decoder.decodeCount() == 1)
    }

    @Test("동일 URL 동시 요청 시 네트워크는 1회만 호출")
    func deduplicatesConcurrentRequestsForSameURL() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData(), delay: 100_000_000)
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/2.png")!

        // When
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    _ = try? await sut.loadImage(from: url)
                }
            }
        }

        // Then
        #expect(await transport.callCount() == 1)
    }

    @Test("완료된 in-flight task는 재사용하지 않음")
    func doesNotReuseCompletedInFlightTask() async throws {
        let inFlight = ImageCacheInFlightRequests()
        let key = "https://example.com/inflight-completed.png"

        let first = await inFlight.task(for: key) {
            Data([0x01])
        }
        #expect(first.isCreator)
        #expect(try await first.task.value == Data([0x01]))

        let second = await inFlight.task(for: key) {
            Data([0x02])
        }

        #expect(second.isCreator)
        #expect(first.token != second.token)
        #expect(try await second.task.value == Data([0x02]))

        await inFlight.release(key: key, token: first.token)
        await inFlight.release(key: key, token: second.token)
    }

    @Test("이전 task의 release는 새 in-flight task를 취소하지 않음")
    func staleReleaseDoesNotCancelNewInFlightTask() async throws {
        let inFlight = ImageCacheInFlightRequests()
        let key = "https://example.com/inflight-release.png"

        let first = await inFlight.task(for: key) {
            Data([0x01])
        }
        _ = try await first.task.value

        let second = await inFlight.task(for: key) {
            try await Task.sleep(nanoseconds: 100_000_000)
            return Data([0x02])
        }

        await inFlight.release(key: key, token: first.token)

        #expect(second.isCreator)
        #expect(try await second.task.value == Data([0x02]))

        await inFlight.release(key: key, token: second.token)
    }

    @Test("failure cooldown 적용")
    func appliesFailureCooldownAfterRequestFailure() async throws {
        // Given
        let url = URL(string: "https://example.com/fail.png")!
        let transport = TransportSpy(responseData: makePNGData(), failURLs: [url])
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(
            dataStore: cache,
            configuration: .init(
                httpClient: httpClient,
                failureCooldownBase: 0.2,
                failureCooldownMax: 0.2
            )
        )

        // When
        _ = try? await sut.loadImage(from: url)

        // Then
        await #expect {
            _ = try await sut.loadImage(from: url)
        } throws: { error in
            guard let imageError = error as? ImageCacheError,
                  case let .cooldown(until) = imageError
            else { return false }
            return until > Date()
        }
    }

    @Test("prefetch는 실패해도 나머지 URL 계속 처리")
    func continuesRemainingURLsAfterFailure() async throws {
        // Given
        let failURL = URL(string: "https://example.com/fail3.png")!
        let transport = TransportSpy(responseData: makePNGData(), failURLs: [failURL])
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let successURLs = (0 ..< 4).map { URL(string: "https://example.com/ok3-\($0).png")! }
        let urls = [failURL] + successURLs

        // When
        let result = await sut.prefetch(urls: urls)

        // Then
        #expect(result.failureCount == 1)
        #expect(result.successCount == successURLs.count)
        #expect(result.errors.count == 1)
        #expect(await transport.callCount() == urls.count)
    }

    @Test(".none 정책용 구성에서는 디코딩 메모리 캐시를 사용 안 함")
    func fetchesFromNetworkEveryTimeWhenDecodedCacheIsDisabled() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let sut = ImageCache(
            dataStore: NullImageDataStore(),
            configuration: .init(
                httpClient: httpClient,
                decodedImageCacheEnabled: false
            )
        )
        let url = URL(string: "https://example.com/no-decoded-cache.png")!

        // When
        _ = try await sut.loadImage(from: url)
        _ = try await sut.loadImage(from: url)

        // Then
        #expect(await transport.callCount() == 2)
    }

    @Test("ImageCacheClient는 imageCache 로드 실패 시 네트워크를 재시도 안 함")
    func doesNotRetryNetworkWhenImageCacheClientLoadFails() async {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let client = ImageCacheClient.live(
            configuration: .init(
                storagePolicy: .all,
                httpClient: HTTPClient(transport: transport, middlewares: []),
                decoder: AlwaysFailingDecoder()
            )
        )
        let url = URL(string: "https://example.com/client-no-retry.png")!

        // When
        let image = await client.loadImage(url)

        // Then
        #expect(image == nil)
        #expect(await transport.callCount() == 1)
    }

    @Test("ImageCacheClient는 ImageCache의 디코딩 캐시를 재사용")
    func imageCacheClientReusesImageCacheDecodedCache() async {
        let transport = TransportSpy(responseData: makePNGData())
        let decoder = CountingDecoder()
        let client = ImageCacheClient.live(
            configuration: .init(
                storagePolicy: .memoryOnly,
                httpClient: HTTPClient(transport: transport, middlewares: []),
                decoder: decoder
            )
        )
        let url = URL(string: "https://example.com/client-decoded-cache.png")!

        let image1 = await client.loadImage(url)
        let image2 = await client.loadImage(url)

        #expect(image1 != nil)
        #expect(image2 != nil)
        #expect(await transport.callCount() == 1)
        #expect(decoder.decodeCount() == 1)
    }

    @Test("ImageCacheClient .none 정책은 디코딩 캐시를 사용 안 함")
    func imageCacheClientNonePolicyDoesNotUseDecodedCache() async {
        let middlewareCalls = MiddlewareCallCounter()
        let data = makePNGData()
        let decoder = CountingDecoder()
        let client = ImageCacheClient.live(
            configuration: .init(
                storagePolicy: .none,
                httpClient: HTTPClient(
                    transport: FailingTransport(),
                    middlewares: [ImmediateImageResponseMiddleware(data: data, counter: middlewareCalls)]
                ),
                decoder: decoder
            )
        )
        let url = URL(string: "https://example.invalid/client-no-decoded-cache.png")!

        let image1 = await client.loadImage(url)
        let image2 = await client.loadImage(url)

        #expect(image1 != nil)
        #expect(image2 != nil)
        #expect(await middlewareCalls.value == 2)
        #expect(decoder.decodeCount() == 2)
    }

    @Test("ImageCacheClient .none 정책에서도 주입 httpClient 미들웨어를 사용")
    func usesInjectedHTTPClientMiddlewareForNonePolicy() async {
        // Given
        let middlewareCalls = MiddlewareCallCounter()
        let data = makePNGData()
        let injectedHTTPClient = HTTPClient(
            transport: FailingTransport(),
            middlewares: [ImmediateImageResponseMiddleware(data: data, counter: middlewareCalls)]
        )
        let client = ImageCacheClient.live(
            configuration: .init(storagePolicy: .none, httpClient: injectedHTTPClient)
        )
        let url = URL(string: "https://example.invalid/middleware.png")!

        // When
        let image = await client.loadImage(url)

        // Then
        #expect(image != nil)
        #expect(await middlewareCalls.value == 1)
    }

    @Test("데이터 저장소에 손상된 데이터가 있으면 캐시 삭제 후 네트워크에서 다시 로드")
    func removesCorruptCacheDataAndReloadsFromNetwork() async throws {
        // Given
        let expectedData = makePNGData()
        let transport = TransportSpy(responseData: expectedData)
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/corrupt.png")!
        try await cache.set(Data([0xFF, 0xFE]), for: url.absoluteString)

        // When
        _ = try await sut.loadImage(from: url)
        let repairedData = try await cache.value(for: url.absoluteString)

        // Then
        #expect(repairedData == expectedData)
        #expect(await transport.callCount() == 1)
    }

    @Test("options를 전달하면 DownsamplingImageDecoder로 디코딩하고 디코딩 캐시에 저장")
    func usesDownsamplingAndCachesDecodedImageWhenOptionsAreProvided() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData(width: 20, height: 20))
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/options.png")!
        let options = ImageProcessingOptions(targetSize: CGSize(width: 10, height: 10), scale: 1)

        // When
        let image = try await sut.loadImage(from: url, options: options)
        let image2 = try await sut.loadImage(from: url, options: options)

        // Then
        #expect(image.size == CGSize(width: 10, height: 10)) // DownsamplingImageDecoder가 targetSize 적용됐는지
        #expect(image === image2)                             // 두 번째 요청은 디코딩 캐시에서 동일 객체 반환
        #expect(await transport.callCount() == 1)
    }

    @Test("options가 다르면 별도 디코딩 캐시 항목을 사용하고 원본 데이터는 재사용")
    func separatesDecodedCacheEntriesButSharesRawDataForDifferentOptions() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/multi-options.png")!
        let smallOptions = ImageProcessingOptions(targetSize: CGSize(width: 10, height: 10), scale: 1)
        let largeOptions = ImageProcessingOptions(targetSize: CGSize(width: 100, height: 100), scale: 1)

        // When
        _ = try await sut.loadImage(from: url, options: smallOptions)
        _ = try await sut.loadImage(from: url, options: largeOptions)

        // Then
        #expect(await transport.callCount() == 1)
    }

    @Test("prefetch에 options를 전달하면 디코딩 캐시도 미리 채워 loadImage가 바로 반환")
    func fillsDecodedCacheDuringPrefetchWithOptions() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/prefetch-options.png")!
        let options = ImageProcessingOptions(targetSize: CGSize(width: 10, height: 10), scale: 1)

        // When
        _ = await sut.prefetch(urls: [url], options: options)
        _ = try await sut.loadImage(from: url, options: options)

        // Then
        #expect(await transport.callCount() == 1)
    }

    @Test("cancelPrefetch는 진행 중인 특정 URL의 사전 로드를 취소")
    func cancelPrefetchCancelsInFlightURL() async throws {
        // Given: 200ms delay로 취소 전에 완료되지 않음을 보장
        let transport = TransportSpy(responseData: makePNGData(), delay: 200_000_000)
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let sut = ImageCacheClient.live(
            configuration: .init(storagePolicy: .memoryOnly, httpClient: httpClient)
        )
        let cancelURL = URL(string: "https://example.com/prefetch-cancel.png")!
        let keepURL   = URL(string: "https://example.com/prefetch-keep.png")!

        // When
        let prefetchTask = Task { await sut.prefetch(urls: [cancelURL, keepURL]) }
        while await transport.callCount() == 0 { await Task.yield() }
        sut.cancelPrefetch(urls: [cancelURL])
        let result = await prefetchTask.value

        // Then
        #expect(result.cancelledCount == 1)
        #expect(result.successCount   == 1)
    }

    @Test("캐시 저장 실패 시 ImageCacheError.cacheError로 전파")
    func propagatesCacheSetFailureAsCacheError() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let dataStore = FailingImageDataStore()
        let sut = ImageCache(dataStore: dataStore, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/cache-fail.png")!

        // When / Then
        await #expect {
            _ = try await sut.loadImage(from: url)
        } throws: { error in
            guard let imageError = error as? ImageCacheError,
                  case .cacheError = imageError
            else { return false }
            return true
        }
    }

    @Test("캐시 조회 실패 시 ImageCacheError.cacheError로 전파")
    func propagatesCacheGetFailureAsCacheError() async throws {
        // Given
        let transport = TransportSpy(responseData: makePNGData())
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let dataStore = FailingImageDataStore(failOnGet: true)
        let sut = ImageCache(dataStore: dataStore, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/cache-get-fail.png")!

        // When / Then
        await #expect {
            _ = try await sut.loadImage(from: url)
        } throws: { error in
            guard let imageError = error as? ImageCacheError,
                  case .cacheError = imageError
            else { return false }
            return true
        }
    }

    // MARK: - Regression Tests

    @Test("회귀: 동시 waiter 중 하나가 취소돼도 나머지 waiter는 이미지 수신")
    func regressionWaiterCancellationDoesNotBlockOtherWaiters() async throws {
        // 취소된 waiter가 공유 Task를 조기 취소하지 않는지 확인
        let transport = TransportSpy(responseData: makePNGData(), delay: 200_000_000)
        let httpClient = HTTPClient(transport: transport, middlewares: [])
        let cache = try makeHybridCache()
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let url = URL(string: "https://example.com/waiter-cancel.png")!

        let creatorTask = Task { try? await sut.loadImage(from: url) }
        while await transport.callCount() == 0 {
            await Task.yield()
        }

        let cancelledTask = Task { try? await sut.loadImage(from: url) }
        let waiterTask = Task { try? await sut.loadImage(from: url) }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        cancelledTask.cancel()

        let creatorImage = await creatorTask.value
        _ = await cancelledTask.value
        let waiterImage = await waiterTask.value

        #expect(creatorImage != nil)
        #expect(cancelledTask.isCancelled)
        #expect(waiterImage != nil)
        #expect(await transport.callCount() == 1)
    }

    @Test("메모리 경고 시 메모리 캐시만 비움")
    func clearsOnlyMemoryCacheOnMemoryWarning() async throws {
        // Given
        let memory = MemoryCache()
        let disk = try DiskCache(configuration: .init(directoryName: "ImageCacheTests-\(UUID().uuidString)"))
        defer { try? disk.removeAll() }
        let cache = HybridCache(memory: memory, disk: disk)
        let httpClient = HTTPClient(transport: TransportSpy(responseData: makePNGData()), middlewares: [])
        let sut = ImageCache(dataStore: cache, configuration: .init(httpClient: httpClient))
        let key = "memory.warning.key"
        let data = makePNGData()
        try await cache.set(data, for: key)

        // When
        #expect(memory.contains(key) == true)
        await sut.handleMemoryWarning()

        // Then
        #expect(memory.contains(key) == false)
        #expect(try await disk.value(for: key) != nil)
    }
}
