import Foundation

/// 테스트 기본값 모음
public enum Dummy {
    /// 기본 Int 값
    public static let int: Int = 0
    /// 기본 String 값
    public static let string: String = "dummy"
    /// 기본 Bool 값
    public static let bool: Bool = false
    /// 기본 Double 값
    public static let double: Double = 0
    /// 기본 Float 값
    public static let float: Float = 0
    /// 기본 UUID 값
    public static let uuid: UUID = .init(uuidString: "00000000-0000-0000-0000-000000000000")!
    /// 기본 Date 값
    public static let date: Date = .init(timeIntervalSince1970: 0)
    /// 기본 URL 값
    public static let url: URL = .init(string: "https://example.com")!
    /// 기본 Data 값
    public static let data: Data = .init()
}
