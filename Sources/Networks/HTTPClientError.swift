import Foundation

/// HTTP 클라이언트 에러
public enum HTTPClientError: Error {
    /// 비 HTTP 응답
    case nonHTTPURLResponse(URLResponse)
    /// 응답 바디 없음
    case missingResponseData
    /// 응답 바디 디코딩 실패
    case decodingFailed(underlyingError: Error, data: Data)
    /// 허용 범위 외 상태 코드
    case unacceptableStatusCode(_ statusCode: Int)
}
