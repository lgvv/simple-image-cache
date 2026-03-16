import Foundation

/// 요청/응답 포함 실패 정보
public struct HTTPFailure: Error {
    /// 요청 정보
    public let request: HTTPRequest
    /// 응답 정보
    public let response: HTTPResponse?
    /// 원인 에러
    public let error: any Error

    /// 실패 정보 생성
    public init(
        request: HTTPRequest,
        response: HTTPResponse?,
        error: any Error
    ) {
        self.request = request
        self.response = response
        self.error = error
    }
}
