import Foundation

/// 캐시 만료 정책과 제거 정책 묶음
///
/// 같은 정책을 여러 저장소에 재사용할 때 사용
public struct CachePolicy: Sendable, Equatable {
    /// 캐시 만료 정책
    public let expiration: CacheExpiration
    /// 캐시 제거 정책
    public let eviction: CacheEviction

    /// 캐시 정책을 생성
    ///
    /// - Parameters:
    ///   - expiration: 캐시 만료 정책
    ///   - eviction: 캐시 제거 정책
    public init(
        expiration: CacheExpiration = .none,
        eviction: CacheEviction = .none
    ) {
        self.expiration = expiration
        self.eviction = eviction
    }

    /// 만료 없음 / 제거 없음
    public static let `default` = CachePolicy()
}

/// 캐시 만료 정책
public enum CacheExpiration: Sendable, Equatable {
    /// 만료를 적용하지 않음
    case none
    /// 현재 시각 기준 상대 만료를 적용
    case seconds(TimeInterval)
    /// 지정 시각에 만료
    case date(Date)

    /// 현재 기준 만료 시각 계산
    ///
    /// - Parameter now: 기준 시각
    /// - Returns: 만료 시각 또는 `nil`
    public func expiresAt(now: Date = Date()) -> Date? {
        switch self {
        case .none:
            return nil
        case let .seconds(interval):
            return now.addingTimeInterval(interval)
        case let .date(date):
            return date
        }
    }
}

/// 캐시 제거 정책
///
/// 저장 공간 한도 초과 시 제거 기준
public enum CacheEviction: Sendable, Equatable {
    /// 제거를 적용하지 않음
    case none
    /// 항목 수 기준 제거를 적용
    case countLimit(Int)
    /// 비용 기준 제거를 적용
    case costLimit(Int)
}
