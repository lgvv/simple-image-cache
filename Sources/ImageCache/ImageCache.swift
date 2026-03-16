import UIKit

import Caches
import Common
import Networks

/// 이미지 로딩 / 캐싱 코어
///
/// 조회 순서: 디코딩 캐시 -> raw 캐시 -> 네트워크
/// 동일 URL 동시 요청은 한 번만 전송
/// 실패 시 cooldown 적용
final class ImageCache: Sendable {
    /// `ImageCache` 구성 옵션
    struct Configuration: Sendable {
        /// 이미지 요청에 사용할 HTTP 클라이언트
        let httpClient: HTTPClient
        /// 이미지 디코더
        let decoder: ImageDecoder
        /// 실패 cooldown 시작 간격
        let failureCooldownBase: TimeInterval
        /// 실패 cooldown 최대 간격
        let failureCooldownMax: TimeInterval
        /// 실패 cooldown 적용 여부
        let failureCooldownEnabled: Bool
        /// 디코딩 이미지 메모리 캐시 사용 여부
        let decodedImageCacheEnabled: Bool
        /// 디코딩 이미지 메모리 캐시 최대 항목 수 (0이면 제한 없음)
        let decodedCacheCountLimit: Int
        /// 디코딩 이미지 메모리 캐시 최대 비용 (바이트, 0이면 제한 없음)
        let decodedCacheCostLimit: Int
        /// GPU 텍스처 사전 업로드 여부
        ///
        /// 첫 렌더링 지연 감소 목적
        /// 추가 CPU / 메모리 사용
        let prewarmGPUTexture: Bool

        /// 구성 옵션을 생성
        ///
        /// - Parameters:
        ///   - httpClient: 이미지 요청에 사용할 HTTP 클라이언트
        ///   - decoder: 이미지 디코더
        ///   - failureCooldownBase: 실패 cooldown 시작 간격
        ///   - failureCooldownMax: 실패 cooldown 최대 간격
        ///   - failureCooldownEnabled: 실패 cooldown 적용 여부
        ///   - decodedImageCacheEnabled: 디코딩 이미지 메모리 캐시 사용 여부
        ///   - decodedCacheCountLimit: 디코딩 이미지 메모리 캐시 최대 항목 수 (0이면 제한 없음)
        ///   - decodedCacheCostLimit: 디코딩 이미지 메모리 캐시 최대 비용 (바이트, 0이면 제한 없음)
        ///   - prewarmGPUTexture: GPU 텍스처 사전 업로드 여부
        init(
            httpClient: HTTPClient = .live,
            decoder: ImageDecoder = UIImageDecoder(),
            failureCooldownBase: TimeInterval = 2,
            failureCooldownMax: TimeInterval = 30,
            failureCooldownEnabled: Bool = true,
            decodedImageCacheEnabled: Bool = true,
            decodedCacheCountLimit: Int = 100,
            decodedCacheCostLimit: Int = 50 * 1024 * 1024,
            prewarmGPUTexture: Bool = false
        ) {
            self.httpClient = httpClient
            self.decoder = decoder
            self.failureCooldownBase = failureCooldownBase
            self.failureCooldownMax = failureCooldownMax
            self.failureCooldownEnabled = failureCooldownEnabled
            self.decodedImageCacheEnabled = decodedImageCacheEnabled
            self.decodedCacheCountLimit = decodedCacheCountLimit
            self.decodedCacheCostLimit = decodedCacheCostLimit
            self.prewarmGPUTexture = prewarmGPUTexture
        }
    }

    /// raw 이미지 데이터 저장소
    private let dataStore: any ImageDataStore
    /// 이미지 요청에 사용할 HTTP 클라이언트
    private let httpClient: HTTPClient
    /// 기본 이미지 디코더
    private let decoder: ImageDecoder
    /// 실패 cooldown 시작 간격
    private let failureCooldownBase: TimeInterval
    /// 실패 cooldown 최대 간격
    private let failureCooldownMax: TimeInterval
    /// 실패 cooldown 적용 여부
    private let failureCooldownEnabled: Bool
    /// 디코딩 이미지 메모리 캐시 사용 여부
    private let decodedImageCacheEnabled: Bool
    /// 디코딩 이미지 메모리 캐시 최대 항목 수
    private let decodedCacheCountLimit: Int
    /// 디코딩 이미지 메모리 캐시 최대 비용 (바이트)
    private let decodedCacheCostLimit: Int
    /// GPU 텍스처 사전 업로드 여부
    private let prewarmGPUTexture: Bool
    /// 동일 URL 요청 공유기
    private let inFlight = ImageCacheInFlightRequests()
    /// 디코딩 이미지 메모리 캐시
    private let decodedCache = UncheckedSendable(NSCache<NSString, UIImage>())
    /// 앱 생명주기 관찰 task 목록
    private let lifecycleTasks = LockIsolated<[Task<Void, Never>]>([])

    private struct State {
        /// URL별 cooldown 만료 시각
        var cooldowns: [String: Date] = [:]
        /// URL별 연속 실패 횟수
        var failureCounts: [String: Int] = [:]
    }
    
    /// cooldown 상태 저장소
    private let state = LockIsolated(State())
    
    /// 이미지 캐시 코어를 생성
    ///
    /// - Parameters:
    ///   - dataStore: raw 이미지 데이터 저장소
    ///   - configuration: 이미지 캐시 구성 옵션
    init(
        dataStore: any ImageDataStore,
        configuration: Configuration = Configuration()
    ) {
        self.dataStore = dataStore
        httpClient = configuration.httpClient
        decoder = configuration.decoder
        failureCooldownBase = configuration.failureCooldownBase
        failureCooldownMax = configuration.failureCooldownMax
        failureCooldownEnabled = configuration.failureCooldownEnabled
        decodedImageCacheEnabled = configuration.decodedImageCacheEnabled
        decodedCacheCountLimit = configuration.decodedCacheCountLimit
        decodedCacheCostLimit = configuration.decodedCacheCostLimit
        prewarmGPUTexture = configuration.prewarmGPUTexture
        decodedCache.value.countLimit = configuration.decodedCacheCountLimit
        decodedCache.value.totalCostLimit = configuration.decodedCacheCostLimit
        lifecycleTasks.withValue { tasks in
            tasks = [
                Task(priority: .background) { [weak self] in
                    for await _ in NotificationCenter.default.notifications(
                        named: UIApplication.didReceiveMemoryWarningNotification
                    ) {
                        await self?.handleMemoryWarning()
                    }
                },
                Task(priority: .background) { [weak self] in
                    for await _ in NotificationCenter.default.notifications(
                        named: UIApplication.didEnterBackgroundNotification
                    ) {
                        await self?.dataStore.flush()
                    }
                },
                Task(priority: .background) { [weak self] in
                    for await _ in NotificationCenter.default.notifications(
                        named: UIApplication.willTerminateNotification
                    ) {
                        await self?.dataStore.flush()
                    }
                }
            ]
        }
    }
   
    deinit {
        lifecycleTasks.withValue { $0.forEach { $0.cancel() } }
    }
    
    /// 이미지 로드
    ///
    /// 디코딩 캐시 -> raw 캐시 -> 네트워크 순서
    ///
    /// - Parameters:
    ///   - url: 이미지를 로드할 URL
    ///   - options: 크기 변환 옵션 / `nil`이면 원본 크기
    func loadImage(from url: URL, options: ImageProcessingOptions? = nil) async throws -> UIImage {
        let requestURL = url.normalizedForRequest
        let rawKey = requestURL.absoluteString
        let decodedKey = decodedCacheKey(url: requestURL, options: options)
        if decodedImageCacheEnabled, let decoded = decodedCache.value.object(forKey: decodedKey) {
            return decoded
        }

        let cachedData: Data?
        do {
            cachedData = try await dataStore.value(for: rawKey)
        } catch {
            throw ImageCacheError.cacheError(error)
        }

        if let cachedData {
            do {
                let image = try await decode(cachedData, options: options)
                if decodedImageCacheEnabled {
                    cacheDecodedImage(image, for: decodedKey)
                }
                return image
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw error
                }
                // 손상 캐시 삭제
                try? await dataStore.removeValue(for: rawKey)
            }
        }

        try Task.checkCancellation()
        let fetched = try await fetchData(url: requestURL)
        try Task.checkCancellation()
        let image = try await decode(fetched.data, options: options)
        if fetched.isCreator {
            do {
                try await dataStore.set(fetched.data, for: rawKey)
            } catch {
                throw ImageCacheError.cacheError(error)
            }
        }
        if decodedImageCacheEnabled {
            cacheDecodedImage(image, for: decodedKey)
        }
        return image
    }
    
    /// 이미지 사전 로드
    ///
    /// 원본 데이터 저장
    /// `options` 지정 시 디코딩 캐시 선반영
    ///
    /// - Parameters:
    ///   - urls: 사전 로드할 URL 목록
    ///   - options: 크기 변환 옵션 / `nil`이면 원본 데이터만 저장
    func prefetch(
        urls: [URL],
        options: ImageProcessingOptions? = nil
    ) async -> PrefetchResult {
        let normalizedURLs = urls.map(\.normalizedForRequest)
        var success = 0, failure = 0, cancelled = 0
        var errors: [ImageCacheError] = []

        await withTaskGroup(of: PrefetchUpdateOutcome.self) { group in
            for url in normalizedURLs {
                group.addTask { await self.prefetchURL(url, options: options) }
            }
            for await outcome in group {
                switch outcome {
                case .success:             success += 1
                case .cancelled:           cancelled += 1
                case .failure(let error):  failure += 1; errors.append(error)
                }
            }
        }

        return PrefetchResult(
            successCount: success,
            failureCount: failure,
            cancelledCount: cancelled,
            errors: errors
        )
    }

    /// 개별 URL 사전 로드 실행
    func prefetchURL(_ url: URL, options: ImageProcessingOptions?) async -> PrefetchUpdateOutcome {
        // url은 prefetch()에서 이미 정규화된 상태로 전달됨
        let rawKey = url.absoluteString

        do {
            try Task.checkCancellation()
            if (try? await dataStore.value(for: rawKey)) != nil {
                return .success
            }

            let fetched = try await fetchData(url: url)
            try Task.checkCancellation()

            if fetched.isCreator {
                do {
                    try await dataStore.set(fetched.data, for: rawKey)
                } catch {
                    return .failure(.cacheError(error))
                }
            }

            try Task.checkCancellation()

            if let options, decodedImageCacheEnabled {
                do {
                    let image = try await decode(fetched.data, options: options)
                    try Task.checkCancellation()
                    let decodedKey = decodedCacheKey(url: url, options: options)
                    cacheDecodedImage(image, for: decodedKey)
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    // 디코딩 캐시 선반영 실패 무시
                }
            }

            return .success
        } catch is CancellationError {
            return .cancelled
        } catch let error as ImageCacheError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    /// 네트워크 데이터 로드
    ///
    /// in-flight 공유 / cooldown 적용
    private func fetchData(url: URL) async throws -> (data: Data, isCreator: Bool) {
        let key = url.absoluteString
        if failureCooldownEnabled {
            purgeExpiredCooldowns()
            if let until = cooldownDate(forKey: key), until > Date() {
                throw ImageCacheError.cooldown(until: until)
            }
        }
        let (task, token, isCreator) = await inFlight.task(for: key) {
            let request = HTTPRequest(method: .get, url: url)
            do {
                return try await self.httpClient.send(request: request, decoder: DataResponseDecoder())
            } catch {
                throw ImageCacheError.networkError(error)
            }
        }
        if Task.isCancelled {
            await inFlight.release(key: key, token: token)
            throw CancellationError()
        }
        let result: Result<Data, Error>
        do {
            result = .success(try await task.value)
        } catch {
            result = .failure(error)
        }
        await inFlight.release(key: key, token: token)
        do {
            let data = try result.get()
            clearFailures(forKey: key)
            return (data, isCreator)
        } catch let imageError as ImageCacheError {
            if isCreator && failureCooldownEnabled { recordFailure(forKey: key) }
            throw imageError
        } catch {
            if isCreator && failureCooldownEnabled { recordFailure(forKey: key) }
            throw ImageCacheError.networkError(error)
        }
    }
    
    /// 이미지 디코딩
    ///
    /// `options` 지정 시 다운샘플링 디코더 사용
    /// `prewarmGPUTexture` 지정 시 GPU 텍스처 사전 업로드
    private func decode(_ data: Data, options: ImageProcessingOptions?) async throws -> UIImage {
        // 부모 취소 전파용 Task
        try await Task(priority: .utility) { [decoder, prewarmGPUTexture] in
            let decoded: UIImage
            if let options {
                let downsampler = DownsamplingImageDecoder(
                    targetSize: options.targetSize,
                    scale: options.scale,
                    contentMode: options.contentMode
                )
                decoded = try downsampler.decode(data)
            } else {
                decoded = try decoder.decode(data)
            }

            guard prewarmGPUTexture else { return decoded }

            // GPU 텍스처 사전 업로드
            let format = UIGraphicsImageRendererFormat()
            format.scale = decoded.scale
            return UIGraphicsImageRenderer(size: decoded.size, format: format)
                .image { _ in decoded.draw(at: .zero) }
        }.value
    }

    /// 디코딩 캐시 키 생성
    private func decodedCacheKey(url: URL, options: ImageProcessingOptions?) -> NSString {
        guard let options else { return url.absoluteString as NSString }
        return "\(url.absoluteString)|\(options.cacheKeySuffix)" as NSString
    }

    /// 디코딩 이미지를 메모리 캐시에 저장
    private func cacheDecodedImage(_ image: UIImage, for key: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        decodedCache.value.setObject(image, forKey: key, cost: cost)
    }

    /// cooldown 만료 시각 조회
    private func cooldownDate(forKey key: String) -> Date? {
        state.withValue {
            guard let date = $0.cooldowns[key] else { return nil }
            guard date > Date() else {
                $0.cooldowns.removeValue(forKey: key)
                $0.failureCounts.removeValue(forKey: key)
                return nil
            }
            return date
        }
    }

    /// 실패 정보 초기화
    private func clearFailures(forKey key: String) {
        state.withValue {
            $0.failureCounts.removeValue(forKey: key)
            $0.cooldowns.removeValue(forKey: key)
        }
    }

    /// 실패 기록 / cooldown 설정
    private func recordFailure(forKey key: String) {
        state.withValue {
            let count = ($0.failureCounts[key] ?? 0) + 1
            $0.failureCounts[key] = count
            let base = failureCooldownBase * pow(2.0, Double(max(0, count - 1)))
            let cooldown = base.isFinite ? min(failureCooldownMax, base) : failureCooldownMax
            $0.cooldowns[key] = Date().addingTimeInterval(cooldown)
        }
    }

    /// 만료된 cooldown 정리
    private func purgeExpiredCooldowns() {
        let now = Date()
        state.withValue { state in
            let expiredKeys = state.cooldowns.filter { $0.value <= now }.map(\.key)
            for key in expiredKeys {
                state.cooldowns.removeValue(forKey: key)
                state.failureCounts.removeValue(forKey: key)
            }
        }
    }

    /// 메모리 경고 처리
    func handleMemoryWarning() async {
        await dataStore.flush()
        decodedCache.value.removeAllObjects()
        await dataStore.removeMemory()
        purgeExpiredCooldowns()
    }
}
