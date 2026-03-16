import Foundation

/// URLSession 기반 전송 구현체
public struct URLSessionTransport: HTTPTransport {
    private let urlSession: URLSession

    /// URLSession으로 전송 계층을 생성
    ///
    /// - Parameters:
    ///   - urlSession: 요청을 수행할 URLSession
    public init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    /// URLSession으로 요청을 전송
    ///
    /// - Parameters:
    ///   - request: 전송할 요청
    /// - Returns: 서버로부터 받은 응답
    /// - Throws: URLSession 오류 또는 HTTP 응답 변환 실패
    public func send(request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest: URLRequest = try HTTPRequestFactory.makeURLRequest(from: request)

        try Task.checkCancellation()
        let (data, response) = try await urlSession.data(for: urlRequest)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.nonHTTPURLResponse(response)
        }

        let httpHeaderResponse: [String: String] = httpResponse.allHeaderFields
            .reduce(into: [:]) { result, pair in
                guard let key = pair.key as? String else { return }
                result[key] = String(describing: pair.value)
            }

        return HTTPResponse(
            requestURL: request.url,
            statusCode: httpResponse.statusCode,
            headers: httpHeaderResponse,
            body: data
        )
    }
}
