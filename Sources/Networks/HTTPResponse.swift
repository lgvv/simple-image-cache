import Foundation

/// HTTP 응답 값
public struct HTTPResponse: Sendable, Decodable {
    /// 요청 URL
    public let requestURL: URL
    /// 상태 코드
    public let statusCode: Int
    /// 헤더
    public let headers: [String: String]
    /// 바디 데이터
    public let body: Data?

    /// 초기화
    ///
    /// - Parameters:
    ///   - requestURL: 요청 URL
    ///   - statusCode: 상태 코드
    ///   - headers: 응답 헤더
    ///   - body: 응답 바디
    public init(
        requestURL: URL,
        statusCode: Int,
        headers: [String: String],
        body: Data?
    ) {
        self.requestURL = requestURL
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// `HTTPResponse` 편의 메서드
///
/// 문자열 / JSON / `Decodable` 변환 지원
public extension HTTPResponse {
    /// 바디 문자열 변환
    ///
    /// - Parameter encoding: 문자열 인코딩
    /// - Returns: 문자열 변환 결과 또는 `nil`
    func bodyString(encoding: String.Encoding = .utf8) -> String? {
        guard let body else { return nil }
        return String(data: body, encoding: encoding)
    }

    /// JSON 객체 변환
    ///
    /// - Returns: JSON 객체 또는 바디가 없으면 `nil`
    /// - Throws: JSON 파싱 실패
    func jsonObject() throws -> Any? {
        guard let body else { return nil }
        return try JSONSerialization.jsonObject(with: body, options: [])
    }

    /// 보기 좋은 JSON 문자열 변환
    ///
    /// - Parameter encoding: 문자열 인코딩
    /// - Returns: 변환 실패 시 `nil`
    func prettyPrintedJSON(encoding: String.Encoding = .utf8) -> String? {
        guard let body else { return nil }
        guard
            let object = try? JSONSerialization.jsonObject(with: body, options: []),
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        else { return nil }

        return String(data: data, encoding: encoding)
    }

    /// `Decodable` 타입 디코딩
    ///
    /// - Parameters:
    ///   - type: 디코딩할 타입
    ///   - decoder: `JSONDecoder`
    /// - Returns: 디코딩된 모델
    /// - Throws: 바디 없음 또는 디코딩 실패
    func decode<T: Decodable>(
        _: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let body else {
            throw HTTPClientError.missingResponseData
        }
        return try decoder.decode(T.self, from: body)
    }
}
