# HybridCache

메모리와 디스크를 결합한 2계층 캐시입니다. 읽을 때 메모리를 먼저 확인하고, 없으면 디스크에서 찾아 메모리로 올립니다. 디스크 쓰기가 실패하면 메모리를 이전 상태로 롤백해 두 저장소의 일관성을 유지합니다.

## Getting Started

```swift
import Caches

let disk = try DiskCache(configuration: .init(directoryName: "MyApp.HybridCache"))
let cache = HybridCache(disk: disk)

try await cache.set(data, for: "key")

if let data = try await cache.value(for: "key") {
    // 사용
}
```

---

## API Reference

### 초기화

```swift
public init(
    memory: MemoryCache = MemoryCache(),
    disk: DiskCache,
    policy: CachePolicy = .default
)
```

### 메서드

```swift
func set(_ data: Data, for key: String, policy: CachePolicy = .default) async throws
```

메모리와 디스크에 저장합니다. 디스크 쓰기가 실패하면 메모리를 롤백하고 에러를 throw합니다.

```swift
func value(for key: String, policy: CachePolicy = .default) async throws -> Data?
```

메모리 먼저, 없으면 디스크를 확인합니다. 디스크 히트 시 메모리로 승격 후 반환합니다.

```swift
func removeMemory() async
```

메모리 캐시만 비웁니다. iOS 메모리 경고 대응에 씁니다.

```swift
func flush() async
```

WriteBuffer에 쌓인 항목을 즉시 디스크에 기록합니다.

```swift
func removeValue(for key: String) async throws
func removeAll() async throws
func removeExpired() async throws
func contains(_ key: String) async -> Bool
```

---

## Configuration Examples

```swift
// 캐시 정책
let cache = HybridCache(
    disk: disk,
    policy: CachePolicy(expiration: .seconds(3600), eviction: .countLimit(200))
)
```

```swift
// WriteBuffer와 함께 사용
let disk = try DiskCache(
    configuration: .init(
        directoryName: "MyApp.HybridCache",
        writeBuffer: .init(flushInterval: 5, maxPendingCount: 50)
    )
)
let cache = HybridCache(disk: disk)

// 앱 종료 전 명시적 flush
await cache.flush()
```

---

## Notes

- `removeValue`는 메모리와 디스크를 독립적으로 삭제합니다. 한쪽 실패 시에도 다른 쪽은 삭제됩니다.
- WriteBuffer pending 항목은 앱 비정상 종료 시 디스크에 기록되지 않습니다. 중요한 데이터는 `flush()`를 명시적으로 호출하세요.
