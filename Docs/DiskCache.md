# DiskCache

파일 시스템 기반 영속 캐시입니다. 키를 SHA256으로 해시해 파일명으로 쓰고, 데이터 파일과 메타데이터 파일을 쌍으로 저장합니다. 임시 파일에 먼저 기록한 뒤 rename으로 교체하므로, 쓰기 도중 앱이 종료되어도 이전 파일이 손상되지 않습니다.

WriteBuffer를 켜두면 `set` 호출을 즉시 디스크에 쓰지 않고 버퍼에 모아 배치로 기록합니다.

## Getting Started

```swift
import Caches

let cache = try DiskCache()

try cache.set(data, for: "my-key")

if let data = try cache.value(for: "my-key") {
    // 사용
}
```

---

## API Reference

### 초기화

```swift
public init(configuration: Configuration = Configuration()) throws
```

**Throws:**
- `DiskCache.Error.baseDirectoryUnavailable`: 시스템 캐시 디렉터리를 찾을 수 없는 경우
- `DiskCache.Error.directoryCreationFailed`: 캐시 디렉터리 생성에 실패한 경우

### 메서드

```swift
func set(_ data: Data, for key: String, policy: CachePolicy = .default) throws
func value(for key: String) throws -> Data?
func removeValue(for key: String) throws
func removeAll() throws
func removeExpired() throws
func contains(_ key: String) -> Bool
func flushPendingWrites() async
```

> `value`는 만료된 항목을 그 자리에서 삭제하고 `nil`을 반환합니다. 만료 여부는 저장 시 기록된 `expiresAt` 기준으로 판단합니다.

### `DiskCache.Configuration`

| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `directoryName` | `String` | `"Caches.DiskCache"` | 시스템 Caches 디렉터리 하위 경로 |
| `fileProtection` | `FileProtectionType?` | `nil` | 파일 보호 수준 |
| `writeBuffer` | `WriteBufferConfiguration?` | `nil` | WriteBuffer 설정 |

### `WriteBufferConfiguration`

| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `flushInterval` | `TimeInterval` | `5` | 자동 flush 간격 (초) |
| `maxPendingCount` | `Int` | `50` | 이 수를 넘으면 즉시 flush |

---

## Configuration Examples

```swift
// 파일 보호
let cache = try DiskCache(
    configuration: .init(
        directoryName: "MyApp.SecureCache",
        fileProtection: .completeUntilFirstUserAuthentication
    )
)
```

```swift
// WriteBuffer
let cache = try DiskCache(
    configuration: .init(
        directoryName: "MyApp.ImageCache",
        writeBuffer: .init(flushInterval: 3, maxPendingCount: 100)
    )
)
```

```swift
// 만료 정책
try cache.set(data, for: "token", policy: CachePolicy(expiration: .seconds(3600)))
```

---

## Notes

- WriteBuffer pending 항목은 앱 비정상 종료 시 디스크에 기록되지 않습니다. 앱 종료 시 `flushPendingWrites()`를 호출하세요.
- `costLimit`은 지원하지 않습니다. 개수 제한이 필요하면 `countLimit`을 쓰세요.
- 같은 `directoryName`으로 여러 인스턴스를 만들면 파일 충돌이 생길 수 있습니다.
