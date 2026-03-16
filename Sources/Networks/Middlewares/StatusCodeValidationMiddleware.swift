import Foundation

/// 응답 상태 코드가 2xx인지 검증
public struct StatusCodeValidationMiddleware: HTTPClientMiddleware {
    /// 상태 코드 검증 미들웨어를 생성
    public init() {}

    /// 응답 상태 코드를 검증
    ///
    /// - Parameters:
    ///   - request: 현재 요청
    ///   - next: 다음 미들웨어 또는 전송 계층
    /// - Returns: 검증을 통과한 응답
    /// - Throws: 상태 코드가 2xx가 아니면 `HTTPFailure`
    public func intercept(
        request: HTTPRequest,
        next: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        let response = try await next(request)
        guard (200 ..< 300) ~= response.statusCode else {
            throw HTTPFailure(
                request: request,
                response: response,
                error: HTTPClientError.unacceptableStatusCode(response.statusCode)
            )
        }
        return response
    }
}
