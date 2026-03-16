import Foundation
@testable import Networks
import Testing

@Suite struct HTTPClientErrorWrappingTests {
    @Test("transport 에러는 HTTPFailure로 래핑")
    func wrapsTransportErrorInHTTPFailure() async {
        struct TransportError: Error {}

        // Given
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let transport = MockTransport { _ in
            throw TransportError()
        }
        let sut = HTTPClient(transport: transport, middlewares: [])

        // When / Then
        await #expect {
            let _: Sample = try await sut.send(request: request)
        } throws: { error in
            guard let failure = error as? HTTPFailure else { return false }
            return failure.request.url == request.url && failure.response == nil
        }
    }
}
