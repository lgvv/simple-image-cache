import Foundation

/// 바디를 `Data` 그대로 반환하는 디코더
public struct DataResponseDecoder: ResponseDecoder {
    /// 기본 생성자
    public init() {}

    /// 응답 데이터를 그대로 반환
    ///
    /// 참고:
    /// `type`이 `Data`가 아니면 실패
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard type == Data.self, let value = data as? T else {
            let error = NSError(domain: "DataResponseDecoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Expected Data type but got \(type)"])
            throw HTTPClientError.decodingFailed(underlyingError: error, data: data)
        }
        return value
    }
}
