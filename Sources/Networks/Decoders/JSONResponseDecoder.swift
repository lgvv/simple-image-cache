import Foundation

/// JSON 응답을 디코딩하는 기본 디코더
public struct JSONResponseDecoder: ResponseDecoder {
    private let decoder: JSONDecoder

    /// JSONDecoder를 주입해 생성
    ///
    /// - Parameter decoder: 사용할 JSONDecoder
    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    /// JSON 데이터 디코딩
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
