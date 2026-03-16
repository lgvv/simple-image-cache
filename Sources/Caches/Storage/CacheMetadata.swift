import Foundation

/// 디스크 캐시 메타데이터
struct CacheMetadata: Codable {
    var expiresAt: Date?
    var lastWrite: Date

    /// 만료 여부
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}
