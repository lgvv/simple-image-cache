/// HTTP 메서드
public enum HTTPMethod: String, Sendable, Codable {
    /// GET 요청
    case get = "GET"
    /// POST 요청
    case post = "POST"
    /// PUT 요청
    case put = "PUT"
    /// PATCH 요청
    case patch = "PATCH"
    /// DELETE 요청
    case delete = "DELETE"
}
