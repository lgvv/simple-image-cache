import Foundation

/// HTTP 요청 / 응답 가로채기 인터페이스
///
/// 요청 수정 / 응답 가공 / 공통 실패 처리 용도
/// 에러는 가능하면 `HTTPFailure`로 래핑
public protocol HTTPClientMiddleware: Sendable {
    /// 미들웨어 처리 진입점
    ///
    /// - Parameters:
    ///   - request: 현재 처리 중인 요청
    ///   - next: 다음 미들웨어 또는 최종 전송 클로저
    /// - Returns: 처리 결과 응답
    /// - Throws: 미들웨어 처리 에러
    func intercept(
        request: HTTPRequest,
        next: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse
}
