@testable import Caches
import Common
import Foundation
import Testing

@Suite
struct MemoryCacheTests {
    @Test("메모리 캐시에 저장 후 다시 조회 가능")
    func storesAndLoadsValue() {
        // Given
        let sut = MemoryCache()
        let key = "memory.key"
        let data = Data("value".utf8)

        // When
        sut.set(data, for: key)
        let result = sut.value(for: key)

        // Then
        #expect(result == data)
    }

    @Test("만료된 항목은 조회 시 nil")
    func returnsNilForExpiredEntry() {
        // Given
        let sut = MemoryCache()
        let key = "memory.expired"
        let data = Data("value".utf8)
        let policy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))

        // When
        sut.set(data, for: key, policy: policy)
        let result = sut.value(for: key, policy: policy)

        // Then
        #expect(result == nil)
    }

    @Test("countLimit 정책은 오래된 항목 제거")
    func evictsOldestEntryForCountLimit() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .countLimit(1))
        let dataA = Data("A".utf8)
        let dataB = Data("B".utf8)

        // When
        sut.set(dataA, for: "A", policy: policy)
        sut.set(dataB, for: "B", policy: policy)

        // Then
        #expect(sut.value(for: "A", policy: policy) == nil)
        #expect(sut.value(for: "B", policy: policy) == dataB)
    }

    @Test("removeAll은 모든 항목 삭제")
    func removesAllEntries() {
        // Given
        let sut = MemoryCache()
        sut.set(Data("A".utf8), for: "A")
        sut.set(Data("B".utf8), for: "B")

        // When
        sut.removeAll()

        // Then
        #expect(sut.contains("A") == false)
        #expect(sut.contains("B") == false)
    }

    @Test("costLimit 정책은 총 비용을 기준으로 오래된 항목 제거")
    func evictsOldestEntryForCostLimit() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .costLimit(2))
        let dataA = Data("A".utf8) // cost 1
        let dataBC = Data("BC".utf8) // cost 2

        // When
        sut.set(dataA, for: "A", policy: policy)
        sut.set(dataBC, for: "BC", policy: policy)

        // Then
        #expect(sut.value(for: "A", policy: policy) == nil)
        #expect(sut.value(for: "BC", policy: policy) == dataBC)
    }

    @Test("removeExpired는 만료된 항목만 제거")
    func removesOnlyExpiredEntries() {
        // Given
        let sut = MemoryCache()
        let expiredPolicy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))
        let validPolicy = CachePolicy(expiration: .seconds(60))

        sut.set(Data("old".utf8), for: "old", policy: expiredPolicy)
        sut.set(Data("new".utf8), for: "new", policy: validPolicy)

        // When
        sut.removeExpired()

        // Then
        #expect(sut.contains("old") == false)
        #expect(sut.contains("new") == true)
    }

    @Test("countLimit 0이면 저장 후 바로 제거")
    func removesEntryImmediatelyForZeroCountLimit() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .countLimit(0))
        let data = Data("A".utf8)

        // When
        sut.set(data, for: "A", policy: policy)

        // Then
        #expect(sut.value(for: "A", policy: policy) == nil)
    }

    @Test("costLimit 0이면 저장 후 바로 제거")
    func removesEntryImmediatelyForZeroCostLimit() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .costLimit(0))
        let data = Data("A".utf8)

        // When
        sut.set(data, for: "A", policy: policy)

        // Then
        #expect(sut.value(for: "A", policy: policy) == nil)
    }

    @Test("contains는 만료된 항목에 대해 false")
    func returnsFalseForExpiredEntryInContains() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(expiration: .date(Date().addingTimeInterval(-1)))
        sut.set(Data("A".utf8), for: "A", policy: policy)

        // Then
        #expect(sut.contains("A") == false)
    }

    @Test("최근 접근한 항목은 LRU에서 보호")
    func keepsRecentlyAccessedEntryForCountLimitLRU() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .countLimit(2))
        sut.set(Data("A".utf8), for: "A", policy: policy)
        sut.set(Data("B".utf8), for: "B", policy: policy)

        // When
        _ = sut.value(for: "A", policy: policy) // A를 최근 접근으로 갱신
        sut.set(Data("C".utf8), for: "C", policy: policy)

        // Then
        #expect(sut.value(for: "A", policy: policy) != nil)
        #expect(sut.value(for: "B", policy: policy) == nil)
        #expect(sut.value(for: "C", policy: policy) != nil)
    }

    @Test("costLimit에서도 최근 접근한 항목 우선 유지")
    func keepsRecentlyAccessedEntryForCostLimitLRU() {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .costLimit(3))
        sut.set(Data("A".utf8), for: "A", policy: policy) // cost 1
        sut.set(Data("B".utf8), for: "B", policy: policy) // cost 1

        // When
        _ = sut.value(for: "A", policy: policy)
        sut.set(Data("CC".utf8), for: "CC", policy: policy) // cost 2, total 4 -> eviction to 3

        // Then
        #expect(sut.value(for: "A", policy: policy) != nil)
        #expect(sut.value(for: "B", policy: policy) == nil)
        #expect(sut.value(for: "CC", policy: policy) != nil)
    }

    @Test("동시에 set/value/remove를 호출해도 크래시 없음")
    func remainsSafeDuringConcurrentAccess() async {
        // Given
        let sut = MemoryCache()
        let iterations = 100

        // When - set, value, remove, contains를 동시에 수행
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< iterations {
                group.addTask {
                    let key = "key.\(i % 10)"
                    let data = Data("value\(i)".utf8)
                    sut.set(data, for: key)
                    _ = sut.value(for: key)
                    _ = sut.contains(key)
                    if i % 3 == 0 { sut.removeValue(for: key) }
                }
            }
        }

        // Then - 크래시 없이 완료
        sut.removeAll()
        #expect(sut.contains("key.0") == false)
    }

    @Test("동시 set+eviction에서 데이터 정합성 유지")
    func keepsDataConsistentDuringConcurrentSetAndEviction() async {
        // Given
        let sut = MemoryCache()
        let policy = CachePolicy(eviction: .countLimit(10))
        let totalWrites = LockIsolated(0)

        // When - 50개 동시 쓰기, countLimit 10
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    sut.set(Data("v\(i)".utf8), for: "k\(i)", policy: policy)
                    totalWrites.withValue { $0 += 1 }
                }
            }
        }

        // Then - 모든 쓰기 완료, countLimit 이하의 항목만 유지
        #expect(totalWrites.value == 50)
        var remaining = 0
        for i in 0 ..< 50 {
            if sut.contains("k\(i)") { remaining += 1 }
        }
        #expect(remaining <= 10)
    }
}
