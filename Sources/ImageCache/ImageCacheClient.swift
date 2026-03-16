import UIKit

import Caches
import Common
import Networks

/// 이미지를 로드하고 사전 로드하는 클라이언트
public struct ImageCacheClient: Sendable {
    var loadImage: @Sendable (URL?, ImageProcessingOptions?) async -> UIImage?
    var prefetch: @Sendable ([URL], ImageProcessingOptions?) async -> PrefetchResult
    var cancelPrefetch: @Sendable ([URL]) -> Void

    /// 이미지 캐시 클라이언트를 생성
    ///
    /// - Parameters:
    ///   - loadImage: 이미지 로드 클로저
    ///   - prefetch: 사전 로드 클로저
    ///   - cancelPrefetch: 사전 로드 취소 클로저
    public init(
        loadImage: @Sendable @escaping (URL?, ImageProcessingOptions?) async -> UIImage?,
        prefetch: @Sendable @escaping ([URL], ImageProcessingOptions?) async -> PrefetchResult = { _, _ in
            PrefetchResult(successCount: 0, failureCount: 0, errors: [])
        },
        cancelPrefetch: @Sendable @escaping ([URL]) -> Void = { _ in }
    ) {
        self.loadImage = loadImage
        self.prefetch = prefetch
        self.cancelPrefetch = cancelPrefetch
    }

    /// 이미지 로드
    ///
    /// `options` 미지정 시 원본 크기 디코딩
    public func loadImage(
        _ url: URL?,
        options: ImageProcessingOptions? = nil
    ) async -> UIImage? {
        await self.loadImage(url, options)
    }

    /// 이미지 사전 로드
    ///
    /// `options` 지정 시 디코딩 캐시 선반영
    public func prefetch(
        urls: [URL],
        options: ImageProcessingOptions? = nil
    ) async -> PrefetchResult {
        await self.prefetch(urls, options)
    }

    /// 진행 중인 사전 로드 취소
    ///
    /// `UICollectionViewDataSourcePrefetching`의 `cancelPrefetchingForItemsAt`에서 호출한다.
    /// 이미 완료된 URL은 무시된다.
    public func cancelPrefetch(urls: [URL]) {
        self.cancelPrefetch(urls)
    }
}

public extension ImageCacheClient {
    /// 기본 설정을 사용하는 라이브 클라이언트
    static let live: ImageCacheClient = make(configuration: .init())

    /// 설정을 적용한 라이브 클라이언트를 생성
    ///
    /// - Parameter configuration: 클라이언트 설정
    /// - Returns: 설정이 반영된 클라이언트
    static func live(configuration: ImageCacheClientConfiguration) -> ImageCacheClient {
        make(configuration: configuration)
    }

    /// 미리보기용 기본 클라이언트
    static let preview = ImageCacheClient(
        loadImage: { _, _ in UIImage(systemName: "photo") }
    )

    /// 아무 동작도 하지 않는 클라이언트
    static let noop = ImageCacheClient(
        loadImage: { _, _ in nil }
    )
}

private extension ImageCacheClient {
    static func make(configuration: ImageCacheClientConfiguration) -> ImageCacheClient {
        let resolvedHTTPClient = resolveImageCacheHTTPClient(for: configuration)
        let imageCache = makeImageCache(configuration: configuration, httpClient: resolvedHTTPClient)

        // 동일 (URL + options) 키에 대한 최종 이미지 로드를 공유해
        // 동시 요청 시 중복 디코딩과 중복 로깅을 방지한다.
        let inFlightImages = LockIsolated<[String: Task<UIImage?, Never>]>([:])

        // URL별 사전 로드 Task를 추적해 cancelPrefetch에서 개별 취소를 가능하게 한다.
        let inFlightPrefetches = LockIsolated<[String: Task<PrefetchUpdateOutcome, Never>]>([:])

        return ImageCacheClient(
            loadImage: { url, options in
                guard let url else { return nil }
                let requestURL = url.normalizedForRequest
                let keyString = makeCacheKey(url: requestURL, options: options) as String
                let (loadTask, isCreator) = inFlightImages.withValue { dict -> (Task<UIImage?, Never>, Bool) in
                    if let existing = dict[keyString] { return (existing, false) }

                    let task = Task<UIImage?, Never> {
                        do {
                            return try await imageCache.loadImage(from: requestURL, options: options)
                        } catch {
                            AppLogger.imageCache.error("ImageCacheClient 이미지 로드 실패: \(String(describing: error))")
                            return nil
                        }
                    }

                    dict[keyString] = task
                    return (task, true)
                }

                let image = await loadTask.value
                if isCreator {
                    inFlightImages.withValue { $0[keyString] = nil }
                }
                return image
            },
            prefetch: { urls, options in
                let normalizedURLs = urls.map(\.normalizedForRequest)

                // URL별 Task를 firing하며 추적한다.
                // 같은 URL이 이미 사전 로드 중이면 기존 Task를 재사용한다.
                let taskPairs: [(key: String, task: Task<PrefetchUpdateOutcome, Never>)] = normalizedURLs.map { url in
                    let key = url.absoluteString
                    if let existing = inFlightPrefetches.withValue({ $0[key] }) {
                        return (key, existing)
                    }
                    let task = Task<PrefetchUpdateOutcome, Never> {
                        let outcome = await imageCache.prefetchURL(url, options: options)
                        inFlightPrefetches.withValue { $0.removeValue(forKey: key) }
                        return outcome
                    }
                    inFlightPrefetches.withValue { $0[key] = task }
                    return (key, task)
                }

                var success = 0, failure = 0, cancelled = 0
                var errors: [ImageCacheError] = []
                for (_, task) in taskPairs {
                    switch await task.value {
                    case .success:            success += 1
                    case .cancelled:          cancelled += 1
                    case .failure(let error): failure += 1; errors.append(error)
                    }
                }
                return PrefetchResult(
                    successCount: success,
                    failureCount: failure,
                    cancelledCount: cancelled,
                    errors: errors
                )
            },
            cancelPrefetch: { urls in
                let keys = urls.map { $0.normalizedForRequest.absoluteString }
                inFlightPrefetches.withValue { dict in
                    for key in keys {
                        dict[key]?.cancel()
                        dict.removeValue(forKey: key)
                    }
                }
            }
        )
    }

    private static func makeCacheKey(url: URL, options: ImageProcessingOptions?) -> NSString {
        options.map { "\(url.absoluteString)|\($0.cacheKeySuffix)" as NSString } ?? url.absoluteString as NSString
    }

    private static func makeImageCache(
        configuration: ImageCacheClientConfiguration,
        httpClient: HTTPClient
    ) -> ImageCache {
        let imageCacheConfig = ImageCache.Configuration(
            httpClient: httpClient,
            decoder: configuration.decoder,
            failureCooldownBase: configuration.failureCooldownBase,
            failureCooldownMax: configuration.failureCooldownMax,
            failureCooldownEnabled: configuration.failureCooldownEnabled,
            decodedImageCacheEnabled: configuration.storagePolicy != .none,
            decodedCacheCountLimit: configuration.decodedCacheCountLimit,
            decodedCacheCostLimit: configuration.decodedCacheCostLimit,
            prewarmGPUTexture: configuration.prewarmGPUTexture
        )

        switch configuration.storagePolicy {
        case .all:
            do {
                let disk = try DiskCache(
                    configuration: DiskCache.Configuration(
                        directoryName: "ImageCacheClient.ImageCache"
                    )
                )
                return ImageCache(
                    dataStore: HybridCache(disk: disk, policy: configuration.cachePolicy),
                    configuration: imageCacheConfig
                )
            } catch {
                AppLogger.imageCache.error("ImageCacheClient DiskCache 초기화 실패. 메모리 전용 저장소로 대체: \(String(describing: error))")
                return ImageCache(
                    dataStore: MemoryImageDataStore(policy: configuration.cachePolicy),
                    configuration: imageCacheConfig
                )
            }

        case .memoryOnly:
            return ImageCache(
                dataStore: MemoryImageDataStore(policy: configuration.cachePolicy),
                configuration: imageCacheConfig
            )

        case .httpCache, .httpCacheMemoryOnly, .none:
            return ImageCache(dataStore: NullImageDataStore(), configuration: imageCacheConfig)
        }
    }

    private static func resolveImageCacheHTTPClient(
        for configuration: ImageCacheClientConfiguration
    ) -> HTTPClient {
        switch configuration.storagePolicy {
        case .all, .memoryOnly:
            return configuration.httpClient

        case .httpCache:
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.urlCache = configuration.urlCache
            let session = URLSession(configuration: sessionConfig)
            return configuration.httpClient.replacingTransport(
                URLSessionTransport(urlSession: session)
            )

        case .httpCacheMemoryOnly:
            let sessionConfig = URLSessionConfiguration.default
            let memoryOnlyURLCache = URLCache(
                memoryCapacity: 50 * 1024 * 1024,
                diskCapacity: 0,
                directory: nil
            )
            sessionConfig.urlCache = memoryOnlyURLCache
            let session = URLSession(configuration: sessionConfig)
            return configuration.httpClient.replacingTransport(
                URLSessionTransport(urlSession: session)
            )

        case .none:
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            sessionConfig.urlCache = nil
            let session = URLSession(configuration: sessionConfig)
            return configuration.httpClient.replacingTransport(
                URLSessionTransport(urlSession: session)
            )
        }
    }
}
