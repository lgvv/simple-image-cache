import Foundation

import Caches

/// `ImageCache`가 raw 이미지 데이터를 읽고 쓰는 저장소 추상화
package protocol ImageDataStore: Sendable {
    /// 저장된 raw 이미지를 조회
    func value(for key: String) async throws -> Data?
    /// raw 이미지를 저장
    func set(_ data: Data, for key: String) async throws
    /// 저장된 raw 이미지를 삭제
    func removeValue(for key: String) async throws
    /// pending 쓰기를 반영
    func flush() async
    /// 메모리 기반 상태를 정리
    func removeMemory() async
}

/// 메모리 캐시만 사용하는 데이터 저장소
final class MemoryImageDataStore: ImageDataStore {
    private let memory: MemoryCache
    private let policy: CachePolicy

    /// 메모리 데이터 저장소를 생성
    package init(policy: CachePolicy = .default) {
        memory = MemoryCache()
        self.policy = policy
    }

    /// 저장된 raw 이미지를 조회
    package func value(for key: String) async throws -> Data? {
        memory.value(for: key, policy: policy)
    }

    /// raw 이미지를 저장
    package func set(_ data: Data, for key: String) async throws {
        memory.set(data, for: key, policy: policy)
    }

    /// 저장된 raw 이미지를 삭제
    package func removeValue(for key: String) async throws {
        memory.removeValue(for: key)
    }

    /// pending 쓰기를 반영
    package func flush() async {}

    /// 메모리 캐시를 비움
    package func removeMemory() async {
        memory.removeAll()
    }
}

/// 모든 연산이 no-op인 데이터 저장소
package struct NullImageDataStore: ImageDataStore {
    /// 비어 있는 데이터 저장소를 생성
    package init() {}

    /// 저장된 데이터가 없음을 반환
    package func value(for key: String) async throws -> Data? { nil }
    /// 아무 작업도 하지 않음
    package func set(_ data: Data, for key: String) async throws {}
    /// 아무 작업도 하지 않음
    package func removeValue(for key: String) async throws {}
    /// 아무 작업도 하지 않음
    package func flush() async {}
    /// 아무 작업도 하지 않음
    package func removeMemory() async {}
}

extension HybridCache: ImageDataStore {
    /// 저장된 raw 이미지를 조회
    package func value(for key: String) async throws -> Data? {
        try await value(for: key, policy: .default)
    }

    /// raw 이미지를 저장
    package func set(_ data: Data, for key: String) async throws {
        try await set(data, for: key, policy: .default)
    }
}
