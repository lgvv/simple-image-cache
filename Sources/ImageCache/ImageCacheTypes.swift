import CoreGraphics
import Foundation

import Caches
import Networks

/// 이미지 저장 위치 정책
///
/// 로컬 캐시 / HTTP 캐시 사용 범위 결정
public enum CacheStoragePolicy: Sendable, Hashable {
    /// 메모리 / 디스크 캐시 사용
    case all
    /// 메모리 캐시만 사용
    case memoryOnly
    /// `URLCache` 메모리 / 디스크 사용
    case httpCache
    /// `URLCache` 메모리만 사용
    case httpCacheMemoryOnly
    /// 로컬 캐시 사용 안 함
    case none
}

/// 이미지 리사이징 방식
public enum ImageContentMode: Sendable {
    /// 비율 유지 / 내부 맞춤
    case scaleAspectFit
    /// 비율 유지 / 영역 채움
    case scaleAspectFill
    /// 비율 무시 / 전체 채움
    case scaleToFill
}

/// 요청 단위 이미지 처리 옵션
///
/// 같은 URL이라도 옵션이 다르면 별도 디코딩 캐시 사용
public struct ImageProcessingOptions: Sendable, Hashable {
    /// 목표 출력 크기
    public let targetSize: CGSize
    /// 목표 출력 scale
    public let scale: CGFloat
    /// 출력 정렬 방식
    public let contentMode: ImageContentMode

    /// 이미지 처리 옵션을 생성
    ///
    /// - Parameters:
    ///   - targetSize: 목표 출력 크기
    ///   - scale: 목표 출력 scale
    ///   - contentMode: 출력 정렬 방식
    public init(
        targetSize: CGSize,
        scale: CGFloat = 1.0,
        contentMode: ImageContentMode = .scaleAspectFit
    ) {
        self.targetSize = targetSize
        self.scale = scale
        self.contentMode = contentMode
    }
}

extension ImageProcessingOptions {
    var cacheKeySuffix: String {
        let modeTag: String
        switch contentMode {
        case .scaleAspectFit:
            modeTag = "fit"
        case .scaleAspectFill:
            modeTag = "fill"
        case .scaleToFill:
            modeTag = "stretch"
        }
        return "\(Int(targetSize.width))x\(Int(targetSize.height))@\(scale)_\(modeTag)"
    }
}

/// 이미지 캐시 전용 에러
public enum ImageCacheError: Swift.Error, Sendable {
    /// 응답 데이터가 비어 있는 경우
    case emptyData
    /// 이미지 디코딩에 실패한 경우
    case invalidImageData
    /// 재시도 제한 시간이 남아 있는 경우
    case cooldown(until: Date)
    /// 저장소 작업이 실패한 경우
    case cacheError(Swift.Error)
    /// 네트워크 작업이 실패한 경우
    case networkError(Swift.Error)
}

/// 사전 로드 결과
public struct PrefetchResult: Sendable {
    /// 성공한 요청 수
    public let successCount: Int
    /// 실패한 요청 수
    public let failureCount: Int
    /// 취소된 요청 수
    public let cancelledCount: Int
    /// 수집된 에러 목록
    public let errors: [ImageCacheError]

    /// 사전 로드 결과를 생성
    ///
    /// - Parameters:
    ///   - successCount: 성공한 요청 수
    ///   - failureCount: 실패한 요청 수
    ///   - cancelledCount: 취소된 요청 수
    ///   - errors: 수집된 에러 목록
    public init(
        successCount: Int,
        failureCount: Int,
        cancelledCount: Int = 0,
        errors: [ImageCacheError]
    ) {
        self.successCount = successCount
        self.failureCount = failureCount
        self.cancelledCount = cancelledCount
        self.errors = errors
    }
}

/// 사전 로드 개별 URL 결과
package enum PrefetchUpdateOutcome: Sendable {
    /// 사전 로드 성공
    case success
    /// 사전 로드 실패
    case failure(ImageCacheError)
    /// 사전 로드 취소
    case cancelled
}

/// `ImageCacheClient` 생성 옵션
///
/// 저장 정책 / 디코더 / HTTP 캐시 동작 제어
public struct ImageCacheClientConfiguration: Sendable {
    /// 저장소 사용 정책
    public let storagePolicy: CacheStoragePolicy
    /// 로컬 저장소 캐시 정책
    public let cachePolicy: CachePolicy
    /// 이미지 요청에 사용할 HTTP 클라이언트
    public let httpClient: HTTPClient
    /// 이미지 디코더
    public let decoder: any ImageDecoder
    /// 실패 cooldown 시작 간격
    public let failureCooldownBase: TimeInterval
    /// 실패 cooldown 최대 간격
    public let failureCooldownMax: TimeInterval
    /// 실패 cooldown 적용 여부
    public let failureCooldownEnabled: Bool
    /// HTTP 캐시에 사용할 URLCache
    public let urlCache: URLCache
    /// 디코딩 이미지 메모리 캐시 최대 항목 수 (0이면 제한 없음)
    public let decodedCacheCountLimit: Int
    /// 디코딩 이미지 메모리 캐시 최대 비용 (바이트, 0이면 제한 없음)
    public let decodedCacheCostLimit: Int
    /// GPU 텍스처 사전 업로드 여부
    public let prewarmGPUTexture: Bool

    /// 이미지 캐시 클라이언트 설정을 생성
    ///
    /// - Parameters:
    ///   - storagePolicy: 저장소 사용 정책
    ///   - cachePolicy: 로컬 저장소 캐시 정책
    ///   - httpClient: 이미지 요청에 사용할 HTTP 클라이언트
    ///   - decoder: 이미지 디코더
    ///   - failureCooldownBase: 실패 cooldown 시작 간격
    ///   - failureCooldownMax: 실패 cooldown 최대 간격
    ///   - failureCooldownEnabled: 실패 cooldown 적용 여부
    ///   - urlCache: HTTP 캐시에 사용할 URLCache
    ///   - decodedCacheCountLimit: 디코딩 이미지 메모리 캐시 최대 항목 수 (0이면 제한 없음)
    ///   - decodedCacheCostLimit: 디코딩 이미지 메모리 캐시 최대 비용 (바이트, 0이면 제한 없음)
    ///   - prewarmGPUTexture: GPU 텍스처 사전 업로드 여부
    public init(
        storagePolicy: CacheStoragePolicy = .all,
        cachePolicy: CachePolicy = .default,
        httpClient: HTTPClient = HTTPClient(
            transport: URLSessionTransport(urlSession: .shared),
            middlewares: [StatusCodeValidationMiddleware()]
        ),
        decoder: any ImageDecoder = UIImageDecoder(),
        failureCooldownBase: TimeInterval = 2,
        failureCooldownMax: TimeInterval = 30,
        failureCooldownEnabled: Bool = true,
        urlCache: URLCache = .shared,
        decodedCacheCountLimit: Int = 100,
        decodedCacheCostLimit: Int = 50 * 1024 * 1024,
        prewarmGPUTexture: Bool = false
    ) {
        self.storagePolicy = storagePolicy
        self.cachePolicy = cachePolicy
        self.httpClient = httpClient
        self.decoder = decoder
        self.failureCooldownBase = failureCooldownBase
        self.failureCooldownMax = failureCooldownMax
        self.failureCooldownEnabled = failureCooldownEnabled
        self.urlCache = urlCache
        self.decodedCacheCountLimit = decodedCacheCountLimit
        self.decodedCacheCostLimit = decodedCacheCostLimit
        self.prewarmGPUTexture = prewarmGPUTexture
    }
}
