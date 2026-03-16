import Foundation

/// HTTP 전송 계층
public protocol HTTPTransport: Sendable {
    /// 요청 전송
    ///
    /// - Parameter request: 전송 대상 요청
    /// - Returns: 서버로부터 받은 응답
    /// - Throws: 전송 에러
    func send(request: HTTPRequest) async throws -> HTTPResponse
}
