import Foundation
@testable import Networks
import Testing

@Suite struct HTTPClientMiddlewareTests {
    @Test("미들웨어는 등록된 순서대로 요청 가로챔")
    func interceptsInRegistrationOrder() async throws {
        // Given
        let recorder = OrderRecorder()
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let middlewares: [any HTTPClientMiddleware] = [
            RecordingMiddleware(id: "first", recorder: recorder),
            RecordingMiddleware(id: "second", recorder: recorder),
        ]
        let payload = Sample(id: 1)
        let data = try JSONEncoder().encode(payload)
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: data)
        }

        // When
        let sut = HTTPClient(transport: transport, middlewares: middlewares)
        let _: Sample = try await sut.send(request: request)

        // Then
        #expect(await recorder.values == ["first", "second"])
    }

    @Test("미들웨어가 없으면 transport 직접 호출 후 응답 디코딩")
    func callsTransportDirectlyWhenNoMiddlewareExists() async throws {
        // Given
        let payload = Sample(id: 42)
        let data = try JSONEncoder().encode(payload)
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: data)
        }

        // When
        let sut = HTTPClient(transport: transport, middlewares: [])
        let decoded: Sample = try await sut.send(request: request)

        // Then
        #expect(decoded == payload)
    }

    @Test("단일 미들웨어는 정확히 한 번만 동작")
    func interceptsExactlyOnceForSingleMiddleware() async throws {
        // Given
        let recorder = OrderRecorder()
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let payload = Sample(id: 1)
        let data = try JSONEncoder().encode(payload)
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: data)
        }

        // When
        let sut = HTTPClient(transport: transport, middlewares: [RecordingMiddleware(id: "only", recorder: recorder)])
        let _: Sample = try await sut.send(request: request)

        // Then
        #expect(await recorder.values == ["only"])
    }

    @Test("transport를 교체해도 기존 미들웨어 유지")
    func preservesMiddlewareWhenReplacingTransport() async throws {
        // Given
        let recorder = OrderRecorder()
        let originalTransportCalls = Counter()
        let replacedTransportCalls = Counter()
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let payload = Sample(id: 7)
        let data = try JSONEncoder().encode(payload)
        let originalTransport = MockTransport { transportRequest in
            await originalTransportCalls.increment()
            return HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: data)
        }
        let replacedTransport = MockTransport { transportRequest in
            await replacedTransportCalls.increment()
            return HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: data)
        }

        // When
        let base = HTTPClient(
            transport: originalTransport,
            middlewares: [RecordingMiddleware(id: "mw", recorder: recorder)]
        )
        let sut = base.replacingTransport(replacedTransport)
        let decoded: Sample = try await sut.send(request: request)

        // Then
        #expect(decoded == payload)
        #expect(await recorder.values == ["mw"])
        #expect(await originalTransportCalls.value == 0)
        #expect(await replacedTransportCalls.value == 1)
    }
}

private actor OrderRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor Counter {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}

private struct RecordingMiddleware: HTTPClientMiddleware {
    let id: String
    let recorder: OrderRecorder

    func intercept(
        request: HTTPRequest,
        next: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        await recorder.append(id)
        return try await next(request)
    }
}
