# MemoryCache

`NSCache`는 삭제 타이밍을 예측하기 어렵습니다. `MemoryCache`는 접근 순서와 만료 시각을 직접 추적해 삭제 타이밍을 완전히 제어할 수 있습니다. 모든 연산은 동기적이고 스레드 안전합니다.

## Getting Started

```swift
import Caches

let cache = MemoryCache()

cache.set(data, for: "key")

if let data = cache.value(for: "key") {
    // 사용
}
```

---

## API Reference

```swift
public init()
```

### 메서드

```swift
func set(_ data: Data, for key: String, policy: CachePolicy = .default)
```

데이터를 저장합니다. 같은 키가 있으면 덮어쓰고, 삭제 기준이 설정된 경우 저장 직후 오래된 항목을 정리합니다.

```swift
func setReturningPrevious(_ data: Data, for key: String, policy: CachePolicy = .default) -> Data?
```

데이터를 저장하면서 이전 값을 반환합니다. 단일 락 안에서 처리합니다. `HybridCache`의 롤백 용도로 주로 씁니다.

```swift
func value(for key: String, policy: CachePolicy = .default) -> Data?
func removeValue(for key: String)
func removeAll()
func removeExpired()
func contains(_ key: String) -> Bool
```

---

## Configuration Examples

```swift
// 만료
cache.set(data, for: "key", policy: CachePolicy(expiration: .seconds(3600)))
cache.set(data, for: "banner", policy: CachePolicy(expiration: .date(eventEndDate)))
```

```swift
// 개수 제한
let policy = CachePolicy(eviction: .countLimit(100))
cache.set(data, for: key, policy: policy)
```

```swift
// 크기 제한 (50MB)
let policy = CachePolicy(eviction: .costLimit(50 * 1024 * 1024))
cache.set(imageData, for: "large-image", policy: policy)
```

---

## `NSCache`와의 차이점

| 항목 | `MemoryCache` | `NSCache` |
|---|---|---|
| 삭제 기준 | LRU (lastAccess 카운터) | 구현 비공개 |
| 만료 지원 | O | X |
| 삭제 예측 가능성 | O | X |
| 메모리 경고 자동 클리어 | X(미구현) | O |

---

## Notes

- 항목 정리는 `set` 호출 시에만 일어납니다. 시간이 흘러도 자동으로 지워지지 않습니다.
- 정책은 항목 단위입니다. 인스턴스 수준의 전역 정책은 없습니다.
