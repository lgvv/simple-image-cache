import Foundation

/// HTTP 요청 값
public struct HTTPRequest: Sendable {
    /// HTTP 메서드
    public let method: HTTPMethod
    /// 요청 URL
    public let url: URL
    /// 요청 헤더
    public let headers: [String: String]
    /// 요청 바디
    public let body: Data?

    /// URL 기반 초기화
    ///
    /// - Parameters:
    ///   - method: HTTP 메서드
    ///   - url: 요청 대상 URL
    ///   - headers: 요청 헤더
    ///   - body: 원본 요청 바디 데이터
    public init(
        method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    /// 문자열 URL 기반 초기화
    ///
    /// - Parameters:
    ///   - method: HTTP 메서드
    ///   - urlString: 요청 대상 URL 문자열
    ///   - headers: 요청 헤더
    ///   - body: 원본 요청 바디 데이터
    /// - Returns: 유효하지 않은 URL이면 `nil`
    public init?(
        method: HTTPMethod,
        urlString: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(method: method, url: url, headers: headers, body: body)
    }
}
