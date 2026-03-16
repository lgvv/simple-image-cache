import Foundation
@testable import Networks
import Testing

/// 테스트용 샘플 모델
struct Sample: Codable, Equatable {
    let id: Int
}

/// 클로저 기반 모의 전송 계층
struct MockTransport: HTTPTransport {
    let handler: @Sendable (HTTPRequest) async throws -> HTTPResponse

    func send(request: HTTPRequest) async throws -> HTTPResponse {
        try await handler(request)
    }
}
