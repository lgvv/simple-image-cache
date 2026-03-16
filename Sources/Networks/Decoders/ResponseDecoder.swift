import Foundation

/// 응답 바디 디코더 프로토콜
///
/// HTTPClient에서 응답 바디를 원하는 모델로 변환할 때 사용
public protocol ResponseDecoder: Sendable {
    /// 지정 타입 디코딩
    ///
    /// - Parameters:
    ///   - type: 디코딩할 타입
    ///   - data: 원본 응답 데이터
    /// - Returns: 디코딩된 모델
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}
