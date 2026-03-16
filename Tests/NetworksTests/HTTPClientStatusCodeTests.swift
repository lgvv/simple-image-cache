import Foundation
@testable import Networks
import Testing

@Suite struct HTTPClientStatusCodeTests {
    private let request = HTTPRequest(method: .get, url: URL(string: "https://example.com")!)

    @Test("2xx 상태 코드는 허용", arguments: [200, 201, 204])
    func accepts2xxStatusCode(statusCode: Int) async throws {
        // Given
        let data = try JSONEncoder().encode(Sample(id: 1))
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: statusCode, headers: [:], body: data)
        }
        let sut = HTTPClient(transport: transport, middlewares: [StatusCodeValidationMiddleware()])

        // When / Then
        let _: Sample = try await sut.send(request: request)
    }

    @Test("2xx가 아닌 상태 코드는 unacceptableStatusCode 발생", arguments: [301, 404, 500, 503])
    func throwsUnacceptableStatusCodeForNon2xxStatus(statusCode: Int) async {
        // Given
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: statusCode, headers: [:], body: Data())
        }
        let sut = HTTPClient(transport: transport, middlewares: [StatusCodeValidationMiddleware()])

        // When / Then
        await #expect {
            let _: Sample = try await sut.send(request: request)
        } throws: { error in
            guard let failure = error as? HTTPFailure else { return false }
            guard case let HTTPClientError.unacceptableStatusCode(code) = failure.error else { return false }
            return code == statusCode && failure.request.url == request.url
        }
    }
}
