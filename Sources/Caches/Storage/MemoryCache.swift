import Foundation

import Common

/// 메모리 캐시
///
/// 만료 정책 / `countLimit` / `costLimit` 지원
/// 제거 기준은 최근 접근 순서 LRU
public final class MemoryCache: Sendable {
    struct Entry: Sendable {
        let data: Data
        let expiresAt: Date?
        var lastAccess: UInt64
        let cost: Int

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    private struct State {
        var storage: [String: Entry] = [:]
        var totalCost: Int = 0
        var accessCounter: UInt64 = 0
    }

    private let state = LockIsolated(State())

    /// 메모리 캐시를 생성
    public init() {}

    /// 데이터 저장
    ///
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 캐시 키
    ///   - policy: 만료/제거 정책
    public func set(
        _ data: Data,
        for key: String,
        policy: CachePolicy = .default
    ) {
        state.withValue { state in
            removeExpiredLocked(state: &state)
            if let existing = state.storage[key] {
                state.totalCost -= existing.cost
            }
            let entry = Entry(
                data: data,
                expiresAt: policy.expiration.expiresAt(),
                lastAccess: nextAccessCounter(state: &state),
                cost: data.count
            )
            state.storage[key] = entry
            state.totalCost += entry.cost
            evictIfNeeded(policy: policy, state: &state)
        }
    }

    /// 데이터를 저장하고 교체된 이전 값을 반환
    ///
    /// `set` + 이전 값 조회를 단일 락으로 처리
    /// HybridCache 롤백처럼 이전 값이 필요한 경우에 사용
    ///
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 캐시 키
    ///   - policy: 만료/제거 정책
    /// - Returns: 교체된 이전 데이터. 없었거나 만료됐으면 nil
    public func setReturningPrevious(
        _ data: Data,
        for key: String,
        policy: CachePolicy = .default
    ) -> Data? {
        state.withValue { state in
            removeExpiredLocked(state: &state)
            var previousData: Data?
            if let existing = state.storage[key] {
                state.totalCost -= existing.cost
                previousData = existing.isExpired ? nil : existing.data
            }
            let entry = Entry(
                data: data,
                expiresAt: policy.expiration.expiresAt(),
                lastAccess: nextAccessCounter(state: &state),
                cost: data.count
            )
            state.storage[key] = entry
            state.totalCost += entry.cost
            evictIfNeeded(policy: policy, state: &state)
            return previousData
        }
    }

    /// 데이터 조회
    ///
    /// - Parameters:
    ///   - key: 조회할 키
    ///   - policy: 만료/제거 정책
    /// - Returns: 저장된 데이터. 만료되었거나 없으면 nil
    public func value(
        for key: String,
        policy _: CachePolicy = .default
    ) -> Data? {
        state.withValue { state in
            guard var entry = state.storage[key] else { return nil }
            if entry.isExpired {
                if let removed = state.storage.removeValue(forKey: key) {
                    state.totalCost -= removed.cost
                    if state.totalCost < 0 { state.totalCost = 0 }
                }
                return nil
            }
            entry.lastAccess = nextAccessCounter(state: &state)
            state.storage[key] = entry
            return entry.data
        }
    }

    /// 키 삭제
    ///
    /// - Parameter key: 삭제할 키
    public func removeValue(for key: String) {
        state.withValue { state in
            if let existing = state.storage.removeValue(forKey: key) {
                state.totalCost -= existing.cost
            }
        }
    }

    /// 전체 삭제
    public func removeAll() {
        state.withValue { state in
            state.storage.removeAll()
            state.totalCost = 0
        }
    }

    /// 만료 항목 삭제
    public func removeExpired() {
        state.withValue { state in
            removeExpiredLocked(state: &state)
        }
    }

    /// 키 존재 여부
    ///
    /// - Parameter key: 확인할 키
    /// - Returns: 유효한 항목이 있으면 true
    public func contains(_ key: String) -> Bool {
        state.withValue { state in
            guard let entry = state.storage[key] else { return false }
            return !entry.isExpired
        }
    }
}

// MARK: - Private Helpers

private extension MemoryCache {
    private func removeExpiredLocked(state: inout State) {
        let expiredKeys = state.storage.compactMap { key, entry in entry.isExpired ? key : nil }
        for key in expiredKeys {
            if let removed = state.storage.removeValue(forKey: key) {
                state.totalCost -= removed.cost
            }
        }
        if state.totalCost < 0 { state.totalCost = 0 }
    }

    private func nextAccessCounter(state: inout State) -> UInt64 {
        state.accessCounter &+= 1
        return state.accessCounter
    }

    private func evictIfNeeded(policy: CachePolicy, state: inout State) {
        // 필요 시에만 정렬 수행
        switch policy.eviction {
        case .none:
            return
        case let .countLimit(limit):
            guard limit >= 0, state.storage.count > limit else { return }
            let lruSorted = state.storage.sorted { $0.value.lastAccess < $1.value.lastAccess }
            for element in lruSorted.prefix(state.storage.count - limit) {
                if let removed = state.storage.removeValue(forKey: element.key) {
                    state.totalCost -= removed.cost
                }
            }
        case let .costLimit(limit):
            guard limit >= 0, state.totalCost > limit else { return }
            let lruSorted = state.storage.sorted { $0.value.lastAccess < $1.value.lastAccess }
            for element in lruSorted {
                if state.totalCost <= limit { break }
                if let removed = state.storage.removeValue(forKey: element.key) {
                    state.totalCost -= removed.cost
                }
            }
        }
    }
}
