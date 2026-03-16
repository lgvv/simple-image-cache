import Foundation
@testable import Networks
import Testing

@Suite struct HTTPClientDecodingTests {
    @Test("JSON 응답 바디를 모델로 디코딩")
    func decodesModelFromJSONResponse() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let payload = Sample(id: 7)
        let data = try JSONEncoder().encode(payload)
        let transport = MockTransport { transportRequest in
            HTTPResponse(
                requestURL: transportRequest.url,
                statusCode: 200,
                headers: [:],
                body: data
            )
        }

        // When
        let sut = HTTPClient(transport: transport, middlewares: [])
        let decoded: Sample = try await sut.send(request: request)

        // Then
        #expect(decoded == payload)
    }

    @Test("응답 바디가 없으면 missingResponseData를 담은 HTTPFailure 발생")
    func throwsMissingResponseDataForNilResponseBody() async {
        // Given
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let transport = MockTransport { transportRequest in
            HTTPResponse(requestURL: transportRequest.url, statusCode: 200, headers: [:], body: nil)
        }
        let sut = HTTPClient(transport: transport, middlewares: [])

        // When / Then
        await #expect {
            let _: Sample = try await sut.send(request: request)
        } throws: { error in
            guard let failure = error as? HTTPFailure else { return false }
            guard case HTTPClientError.missingResponseData = failure.error else { return false }
            return failure.request.url == request.url && failure.response?.statusCode == 200
        }
    }

    @Test("잘못된 JSON 응답은 decodingFailed를 담은 HTTPFailure 발생")
    func throwsDecodingFailedForMalformedJSON() async {
        // Given
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)
        let transport = MockTransport { transportRequest in
            HTTPResponse(
                requestURL: transportRequest.url,
                statusCode: 200,
                headers: [:],
                body: Data("not-json".utf8)
            )
        }
        let sut = HTTPClient(transport: transport, middlewares: [])

        // When / Then
        await #expect {
            let _: Sample = try await sut.send(request: request)
        } throws: { error in
            guard let failure = error as? HTTPFailure else { return false }
            guard case HTTPClientError.decodingFailed = failure.error else { return false }
            return failure.request.url == request.url && failure.response?.statusCode == 200
        }
    }
}
