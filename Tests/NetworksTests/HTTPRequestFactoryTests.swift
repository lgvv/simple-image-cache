import Foundation
@testable import Networks
import Testing

@Suite struct HTTPRequestFactoryTests {
    @Test("헤더와 바디가 있는 요청은 모든 필드를 가진 URLRequest 생성")
    func buildsURLRequestWithAllFields() throws {
        // Given
        let url = URL(string: "https://example.com/path")!
        let body = Data("hello".utf8)
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: ["X-Test": "1"],
            body: body
        )

        // When
        let urlRequest = try HTTPRequestFactory.makeURLRequest(from: request)

        // Then
        #expect(urlRequest.url == url)
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "X-Test") == "1")
        #expect(urlRequest.httpBody == body)
    }

    @Test("바디와 헤더가 없는 GET 요청은 httpBody nil")
    func leavesHTTPBodyNilForGetRequestWithoutBody() throws {
        // Given
        let url = URL(string: "https://example.com")!
        let request = HTTPRequest(method: .get, url: url)

        // When
        let urlRequest = try HTTPRequestFactory.makeURLRequest(from: request)

        // Then
        #expect(urlRequest.httpBody == nil)
        #expect(urlRequest.httpMethod == "GET")
    }

    @Test("유효하지 않은 URL 문자열로 생성하면 nil 반환")
    func returnsNilForInvalidURLString() {
        // Given / When
        let request = HTTPRequest(method: .get, urlString: "not a valid url ://")

        // Then
        #expect(request == nil)
    }
}
