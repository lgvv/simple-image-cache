# ImageCache

이미지 URL을 받아 `UIImage`를 반환합니다. 디코딩 캐시, 원본 데이터 저장소, 네트워크를 순서대로 탐색하고, 동시 중복 요청 차단과 실패 쿨다운을 내장합니다.

같은 이미지라도 `ImageProcessingOptions`가 다르면 디코딩 결과가 달라지므로, 원본 `Data`와 디코딩 결과를 별도 계층에서 관리합니다.

## Getting Started

```swift
import ImageCache

let client = ImageCacheClient.live

let image = await client.loadImage(url)

let options = ImageProcessingOptions(
    targetSize: CGSize(width: 200, height: 200),
    scale: UIScreen.main.scale,
    contentMode: .scaleAspectFill
)
let thumbnail = await client.loadImage(url, options: options)
```

---

## API Reference

### `ImageCacheClient`

클로저를 감싼 값 타입입니다. 테스트나 Preview에서 클로저만 교체해 동작을 바꿀 수 있습니다.

| 인스턴스 | 설명 |
|---|---|
| `.live` | 기본 설정(`.all` 정책) 클라이언트 |
| `.live(configuration:)` | 커스텀 설정 클라이언트 |
| `.preview` | `UIImage(systemName: "photo")` 반환 |
| `.noop` | 항상 `nil` 반환 |

```swift
func loadImage(_ url: URL?, options: ImageProcessingOptions? = nil) async -> UIImage?
func prefetch(urls: [URL], options: ImageProcessingOptions? = nil) async -> PrefetchResult
func cancelPrefetch(urls: [URL])
```

### `ImageCacheClientConfiguration`

| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `storagePolicy` | `CacheStoragePolicy` | `.all` | 저장소 범위 |
| `cachePolicy` | `CachePolicy` | `.default` | 만료 및 삭제 기준 |
| `httpClient` | `HTTPClient` | `.live` | 네트워크 클라이언트 |
| `decoder` | `any ImageDecoder` | `UIImageDecoder()` | 이미지 디코더 |
| `failureCooldownBase` | `TimeInterval` | `2` | 실패 쿨다운 초기값 (초) |
| `failureCooldownMax` | `TimeInterval` | `30` | 실패 쿨다운 최대값 (초) |
| `urlCache` | `URLCache` | `.shared` | `.httpCache` 정책용 URLCache |
| `prewarmGPUTexture` | `Bool` | `false` | GPU 텍스처 사전 업로드 |

### `CacheStoragePolicy`

| 케이스 | 저장 위치 | 앱 재시작 후 유지 |
|---|---|---|
| `.all` | 메모리 + 디스크 (HybridCache) | O |
| `.memoryOnly` | 메모리 (MemoryCache) | X |
| `.httpCache` | URLCache 메모리 + 디스크 | OS 정책에 따름 |
| `.httpCacheMemoryOnly` | URLCache 메모리 전용 (50MB) | X |
| `.none` | 캐시 없음 | - |

### `ImageProcessingOptions`

| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `targetSize` | `CGSize` | - | 목표 출력 크기 (포인트) |
| `scale` | `CGFloat` | `1.0` | 렌더링 스케일 |
| `contentMode` | `ImageContentMode` | `.scaleAspectFit` | 리사이징 방식 |

### `ImageCacheError`

| 케이스 | 설명 |
|---|---|
| `.emptyData` | 응답 바디가 비어 있음 |
| `.invalidImageData` | 이미지로 디코딩할 수 없는 데이터 |
| `.cooldown(until: Date)` | 쿨다운 중 요청 차단 |
| `.cacheError(Swift.Error)` | 저장소 읽기/쓰기 실패 |
| `.networkError(Swift.Error)` | 네트워크 요청 실패 |

---

## Configuration Examples

```swift
// 저장소 정책 변경
let client = ImageCacheClient.live(configuration: .init(storagePolicy: .memoryOnly))
let client = ImageCacheClient.live(configuration: .init(storagePolicy: .httpCache))
let client = ImageCacheClient.live(configuration: .init(storagePolicy: .none))
```

```swift
// 캐시 정책
let client = ImageCacheClient.live(
    configuration: .init(
        cachePolicy: CachePolicy(expiration: .seconds(86400), eviction: .countLimit(500))
    )
)
```

```swift
// 테스트 / Preview
let client = ImageCacheClient(loadImage: { url, _ in UIImage(named: "fixture") })
```

---

## Notes

- 같은 `(URL + options)` 조합의 동시 요청은 첫 번째 `Task`를 공유합니다. 네트워크는 한 번만 나갑니다.
- 요청 실패 시 지수 백오프 쿨다운이 적용됩니다 (기본 2초, 최대 30초).
- 메모리 경고 시 디코딩 캐시와 메모리 저장소를 비웁니다. 디스크는 유지됩니다.
- `.all` 정책에서 `DiskCache` 초기화 실패 시 메모리 전용으로 자동 폴백합니다.
