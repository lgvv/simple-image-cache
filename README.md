# ImageCache

> **학습 목적으로 만든 프로젝트입니다.** [Nuke](https://github.com/kean/Nuke), [Kingfisher](https://github.com/onevcat/Kingfisher), [SDWebImage](https://github.com/SDWebImage/SDWebImage) 등 실전 라이브러리를 참고해 이미지 캐시의 핵심 구조를 직접 구현하며 이해하는 데 목적이 있습니다. 프로덕션 사용은 권장하지 않습니다.

Swift 6 기반 iOS 이미지 캐시 라이브러리입니다.

---

## 어떻게 구성되어 있나요?

패키지는 세 개의 독립적인 모듈로 나뉘어 있습니다.

- **Caches**: `MemoryCache`, `DiskCache`, `HybridCache`를 제공합니다. `ImageCache`에 의존하지 않아 범용 캐시로 단독으로 쓸 수 있습니다.
- **Networks**: 미들웨어 파이프라인 기반의 HTTP 클라이언트입니다.
- **ImageCache**: 위 두 모듈을 조합해 이미지 로딩에 특화된 레이어를 제공합니다.

이미지 요청은 디코딩 캐시(NSCache), 원본 데이터 저장소(메모리 + 디스크), 네트워크 순서로 탐색합니다. 디코딩 캐시는 `UIImage`를 직접 보관하기 때문에, 같은 URL이라도 `ImageProcessingOptions`가 다르면 별도 항목으로 관리합니다. 원본 `Data`는 하위 저장소에 딱 한 번만 저장되고, 디코딩 결과는 따로 분리해서 관리하는 구조입니다.

같은 URL에 요청이 동시에 몰려도 첫 번째 `Task`를 공유하기 때문에 네트워크는 한 번만 요청합니다. 셀 열 개가 동시에 같은 이미지를 요청해도 마찬가지입니다. 요청이 실패하면 지수 백오프로 쿨다운을 늘려가며 (기본 2초에서 최대 30초까지) 불필요한 재시도를 줄입니다.

`ImageCacheClient`는 클로저를 감싼 값 타입이라, 테스트나 Preview에서 클로저만 교체해 주입할 수 있습니다.

---

## 요구사항

- Swift 6.0+
- iOS 15.0+
- Xcode 16.2+

---

## 설치

`Package.swift`에 패키지를 추가합니다.

```swift
.package(url: "https://github.com/lgvv/simple-image-cache.git", from: "1.0.0")
```

그런 다음 타겟에도 추가합니다.

```swift
.product(name: "ImageCache", package: "SimpleImageCache")
```

---

## 빠른 시작

```swift
import ImageCache

let client = ImageCacheClient.live

// 이미지 로드
let image = await client.loadImage(imageURL)

// 다운샘플링
let options = ImageProcessingOptions(
    targetSize: CGSize(width: 200, height: 200),
    scale: UIScreen.main.scale,
    contentMode: .scaleAspectFill
)
let thumbnail = await client.loadImage(imageURL, options: options)

// 사전 로드
let result = await client.prefetch(urls: imageURLs)
print("성공 \(result.successCount) / 실패 \(result.failureCount)")
```

---

## 문서

각 구현 영역의 상세 내용은 아래 문서를 참고합니다.

| 모듈 | 설명 |
|---|---|
| [ImageCache](Docs/ImageCache.md) | 이미지 로딩 레이어 (API, 저장소 정책, DI 패턴 포함) |
| [HybridCache](Docs/HybridCache.md) | 메모리 + 디스크 2계층 캐시 |
| [DiskCache](Docs/DiskCache.md) | 영속 디스크 캐시 (WriteBuffer, 파일 보호, 개수 제한 정리 포함) |
| [MemoryCache](Docs/MemoryCache.md) | 인메모리 LRU 캐시 |
| [Networks](Docs/Networks.md) | 미들웨어 기반 HTTP 클라이언트 |

---

## 테스트

`ImageCache` 모듈이 UIKit에 의존하기 때문에 macOS(`swift test`)는 지원하지 않습니다. iOS 시뮬레이터로 실행합니다.

```bash
xcodebuild test \
  -scheme ImageCache-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

특정 타겟만 실행하고 싶다면 `-only-testing` 옵션을 사용합니다.

```bash
xcodebuild test \
  -scheme ImageCache-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:CachesTests \
  CODE_SIGNING_ALLOWED=NO
```
