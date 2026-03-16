# Networks

미들웨어 파이프라인 기반의 HTTP 클라이언트입니다. `ImageCache` 내부에서 쓰지만, 독립적으로도 사용할 수 있습니다. 미들웨어는 등록 순서대로 실행됩니다.

## Getting Started

```swift
import Networks

let client = HTTPClient(
    transport: URLSessionTransport(urlSession: .shared),
    middlewares: [StatusCodeValidationMiddleware()]
)

let request = HTTPRequest(method: .get, url: url)

// Data 응답
let data: Data = try await client.send(request: request, decoder: DataResponseDecoder())

// JSON 디코딩
let user: User = try await client.send(request: request)
```

기본 설정을 쓰려면 `.live`를 사용합니다.

```swift
let client = HTTPClient.live  // URLSession.shared + StatusCodeValidationMiddleware
```

---

## API Reference

### `HTTPClient`

```swift
public init(transport: any HTTPTransport, middlewares: [any HTTPClientMiddleware])
```

```swift
func send<ResponseType: Decodable>(
    request: HTTPRequest,
    decoder: some ResponseDecoder = JSONResponseDecoder()
) async throws -> ResponseType
```

모든 에러는 `HTTPFailure`로 래핑됩니다.

```swift
func replacingTransport(_ transport: any HTTPTransport) -> HTTPClient
```

미들웨어는 유지하고 전송 계층만 교체한 새 인스턴스를 반환합니다.

### `HTTPRequest`

| 프로퍼티 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `method` | `HTTPMethod` | - | HTTP 메서드 |
| `url` | `URL` | - | 요청 URL |
| `headers` | `[String: String]` | `[:]` | 요청 헤더 |
| `body` | `Data?` | `nil` | 요청 바디 |

### `HTTPFailure`

| 프로퍼티 | 타입 | 설명 |
|---|---|---|
| `request` | `HTTPRequest` | 실패한 요청 |
| `response` | `HTTPResponse?` | 응답 (전송 실패 시 `nil`) |
| `error` | `any Error` | 실제 에러 |

### `HTTPClientMiddleware`

```swift
func intercept(
    request: HTTPRequest,
    next: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
) async throws -> HTTPResponse
```

`next`를 호출하면 다음 미들웨어로 넘깁니다. 호출하지 않으면 그 자리에서 응답을 직접 반환할 수 있습니다.

### `ResponseDecoder`

| 구현체 | 설명 |
|---|---|
| `JSONResponseDecoder` | `JSONDecoder`로 `Decodable` 타입 디코딩 (기본값) |
| `DataResponseDecoder` | `Data`를 그대로 반환 |

---

## Configuration Examples

```swift
// 로깅 미들웨어
struct LoggingMiddleware: HTTPClientMiddleware {
    func intercept(
        request: HTTPRequest,
        next: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        let start = Date()
        do {
            let response = try await next(request)
            let elapsed = Date().timeIntervalSince(start)
            print("[\(response.statusCode)] \(request.url) (\(String(format: "%.0fms", elapsed * 1000)))")
            return response
        } catch {
            print("[ERR] \(request.url): \(error)")
            throw error
        }
    }
}
```

```swift
// 커스텀 JSONDecoder
let decoder = JSONResponseDecoder(jsonDecoder: {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}())

let user: User = try await client.send(request: request, decoder: decoder)
```

---

## Notes

- `Data` 응답이 필요하면 `DataResponseDecoder`를 명시적으로 전달하세요. 기본값인 `JSONResponseDecoder`는 `Data`를 JSON으로 파싱하려다 실패합니다.
- 커스텀 미들웨어는 `Sendable`을 준수해야 합니다.
