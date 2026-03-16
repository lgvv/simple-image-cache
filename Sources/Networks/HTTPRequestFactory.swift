import Foundation

/// `HTTPRequest` -> `URLRequest` 변환기
public enum HTTPRequestFactory {
    /// `URLRequest` 생성
    ///
    /// - Parameter request: 변환 대상 요청
    /// - Returns: `URLRequest`
    /// - Throws: 변환 에러
    public static func makeURLRequest(from request: HTTPRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue

        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        if let httpBody = request.body {
            urlRequest.httpBody = httpBody
        }

        return urlRequest
    }
}
