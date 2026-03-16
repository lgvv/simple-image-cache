@testable import Caches
import Foundation
import Testing

@Suite
struct CachePolicyTests {
    @Test("CachePolicy 기본값은 만료와 제거가 모두 없음")
    func usesNoExpirationOrEvictionByDefault() {
        // Given
        let sut = CachePolicy.default

        // When
        let expiration = sut.expiration
        let eviction = sut.eviction

        // Then
        #expect(matchesNoneExpiration(expiration))
        #expect(matchesNoneEviction(eviction))
    }

    @Test("이미 만료된 정책은 expiresAt이 현재보다 과거")
    func returnsPastDateForExpiredPolicy() {
        // Given
        let sut = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))

        // When
        let expiresAt = sut.expiration.expiresAt()

        // Then
        #expect(expiresAt.map { $0 <= Date() } ?? false)
    }

    @Test(".seconds(60) 만료는 미래 시각의 expiresAt 생성")
    func returnsFutureDateForSecondsExpiration() {
        // Given
        let sut = CachePolicy(expiration: .seconds(60))

        // When
        let expiresAt = sut.expiration.expiresAt()

        // Then
        #expect(expiresAt.map { $0 > Date() } ?? false)
    }

    @Test(".none 만료는 expiresAt이 nil")
    func returnsNilForNoneExpiration() {
        // Given
        let sut = CacheExpiration.none

        // When
        let expiresAt = sut.expiresAt()

        // Then
        #expect(expiresAt == nil)
    }

    @Test(".date 만료는 지정한 날짜를 그대로 반환")
    func returnsExactDateForDateExpiration() {
        // Given
        let target = Date().addingTimeInterval(120)
        let sut = CacheExpiration.date(target)

        // When
        let expiresAt = sut.expiresAt()

        // Then
        #expect(expiresAt == target)
    }

    @Test("만료와 countLimit은 독립적으로 함께 설정")
    func combinesExpirationAndCountLimitIndependently() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(
            expiration: .seconds(60),
            eviction: .countLimit(2)
        )

        // When - 3개 저장 -> countLimit(2) eviction 발생
        sut.set(Data("A".utf8), for: "A", policy: policy)
        sut.set(Data("B".utf8), for: "B", policy: policy)
        sut.set(Data("C".utf8), for: "C", policy: policy)

        // Then - LRU에 의해 A 제거, B/C 유지 (만료 전이므로 데이터 존재)
        #expect(sut.value(for: "A", policy: policy) == nil)
        #expect(sut.value(for: "B", policy: policy) != nil)
        #expect(sut.value(for: "C", policy: policy) != nil)
    }

    @Test("만료와 costLimit은 독립적으로 함께 동작")
    func combinesExpirationAndCostLimitIndependently() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(
            expiration: .seconds(60),
            eviction: .costLimit(3)
        )

        // When - cost 1 + 1 + 2 = 4 > 3 -> eviction 발생
        sut.set(Data("A".utf8), for: "A", policy: policy) // cost 1
        sut.set(Data("B".utf8), for: "B", policy: policy) // cost 1
        sut.set(Data("CC".utf8), for: "CC", policy: policy) // cost 2

        // Then - LRU에 의해 A 제거 (totalCost 3 이하로)
        #expect(sut.value(for: "A", policy: policy) == nil)
        #expect(sut.value(for: "B", policy: policy) != nil)
        #expect(sut.value(for: "CC", policy: policy) != nil)
    }

    @Test("이미 만료된 정책에서는 eviction보다 만료가 우선")
    func prioritizesExpirationOverEvictionWhenAlreadyExpired() {
        // Given
        let sut = MemoryCache()
        let expiredPolicy = CachePolicy(
            expiration: .date(Date().addingTimeInterval(-1)),
            eviction: .countLimit(10)
        )

        // When - 만료된 정책으로 저장
        sut.set(Data("A".utf8), for: "A", policy: expiredPolicy)

        // Then - eviction 여유 있지만 만료로 인해 nil
        #expect(sut.value(for: "A", policy: expiredPolicy) == nil)
    }

    @Test("같은 CachePolicy는 Equatable 비교에서 동일")
    func equatesIdenticalPolicies() {
        // Given
        let a = CachePolicy(expiration: .seconds(60), eviction: .countLimit(10))
        let b = CachePolicy(expiration: .seconds(60), eviction: .countLimit(10))

        // Then
        #expect(a == b)
    }

    @Test("다른 CachePolicy는 Equatable 비교에서 상이")
    func differentiatesDistinctPolicies() {
        // Given
        let a = CachePolicy(expiration: .seconds(60), eviction: .countLimit(10))
        let b = CachePolicy(expiration: .seconds(30), eviction: .countLimit(10))

        // Then
        #expect(a != b)
    }

    private func matchesNoneExpiration(_ expiration: CacheExpiration) -> Bool {
        if case .none = expiration { return true }
        return false
    }

    private func matchesNoneEviction(_ eviction: CacheEviction) -> Bool {
        if case .none = eviction { return true }
        return false
    }
}
