import Foundation

extension URL {
    /// 합성 캐시 키 제거
    ///
    /// 디코딩 캐시 suffix가 붙은 URL도 원본 요청 URL로 복원
    var normalizedForRequest: URL {
        let absolute = absoluteString
        guard let separatorIndex = absolute.firstIndex(of: "|") else { return self }
        return URL(string: String(absolute[..<separatorIndex])) ?? self
    }
}

/// 동일 URL 요청 공유
///
/// 첫 요청 task 재사용 방식
actor ImageCacheInFlightRequests {
    private struct Entry {
        let id: UUID
        let task: Task<Data, Error>
        var waiters: Int
    }

    private var entries: [String: Entry] = [:]

    /// 진행 중 요청 task를 조회하거나 생성
    func task(
        for key: String,
        create: @escaping @Sendable () async throws -> Data
    ) -> (task: Task<Data, Error>, token: UUID, isCreator: Bool) {
        if var existing = entries[key] {
            existing.waiters += 1
            entries[key] = existing
            return (existing.task, existing.id, false)
        }

        let id = UUID()
        let task = Task(priority: Task.currentPriority) {
            do {
                let data = try await create()
                finish(key: key, id: id)
                return data
            } catch {
                finish(key: key, id: id)
                throw error
            }
        }
        entries[key] = Entry(id: id, task: task, waiters: 1)
        return (task, id, true)
    }

    /// 대기자 수를 줄이고 필요 시 task를 정리
    func release(key: String, token: UUID) {
        guard var entry = entries[key], entry.id == token else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entries.removeValue(forKey: key)
        } else {
            entries[key] = entry
        }
    }

    private func finish(key: String, id: UUID) {
        guard let entry = entries[key], entry.id == id else { return }
        entries.removeValue(forKey: key)
    }
}
