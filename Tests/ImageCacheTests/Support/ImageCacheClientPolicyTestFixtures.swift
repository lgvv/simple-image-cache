import Foundation
@testable import ImageCache
import Network
import Networks

// MARK: - Client Factory

/// `storagePolicy`가 `.httpCache`, `.httpCacheMemoryOnly`, `.none`이면 `transport`는
/// `ImageCacheClient` 내부에서 `URLSessionTransport`로 교체된다
/// 해당 정책 테스트에서는 `transport`를 생략하고 기본값을 사용
func makeStoragePolicyClient(
    storagePolicy: CacheStoragePolicy,
    transport: any HTTPTransport = URLSessionTransport(urlSession: .shared),
    middlewares: [any HTTPClientMiddleware] = [],
    urlCache: URLCache = .shared
) -> ImageCacheClient {
    ImageCacheClient.live(
        configuration: .init(
            storagePolicy: storagePolicy,
            httpClient: HTTPClient(transport: transport, middlewares: middlewares),
            urlCache: urlCache
        )
    )
}

// MARK: - URLCache Helpers

func makeIsolatedURLCache() -> URLCache {
    URLCache(
        memoryCapacity: 8 * 1024 * 1024,
        diskCapacity: 16 * 1024 * 1024,
        diskPath: nil
    )
}

func seedURLCache(_ cache: URLCache, for url: URL, data: Data) {
    let request = URLRequest(url: url)
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
            "Content-Type": "image/png",
            "Cache-Control": "public, max-age=600",
        ]
    )!
    let cached = CachedURLResponse(response: response, data: data)
    cache.storeCachedResponse(cached, for: request)
}

// MARK: - Image Helpers

func makeStoragePolicyImageURL(prefix: String) -> URL {
    URL(string: "https://\(prefix)-\(UUID().uuidString).image-cache-policy.invalid/image.png")!
}

// MARK: - Transport Stubs

struct StaticImageTransport: HTTPTransport {
    let data: Data

    func send(request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(
            requestURL: request.url,
            statusCode: 200,
            headers: [:],
            body: data
        )
    }
}

struct AlwaysFailTransport: HTTPTransport {
    func send(request _: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.cannotFindHost)
    }
}

// MARK: - LocalETagHTTPServer

/// ETag 기반 HTTP 재검증을 테스트하기 위한 로컬 TCP 서버
///
/// - 첫 요청: 200 OK + `ETag` + `Cache-Control: no-cache`
/// - If-None-Match 일치: 304 Not Modified
final class LocalETagHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let ifNoneMatch: String?
    }

    static let etag = "\"v1\""

    private actor Recorder {
        private var requests: [Request] = []

        func append(_ request: Request) {
            requests.append(request)
        }

        func snapshot() -> [Request] {
            requests
        }
    }

    private let listener: NWListener
    private let responseData: Data
    private let queue = DispatchQueue(label: "image-cache-tests.local-etag-server")
    private let recorder = Recorder()

    private init(listener: NWListener, responseData: Data) {
        self.listener = listener
        self.responseData = responseData
    }

    var imageURL: URL {
        URL(string: "http://127.0.0.1:\(port)/image.png")!
    }

    private var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    static func start(responseData: Data) async throws -> LocalETagHTTPServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = LocalETagHTTPServer(listener: listener, responseData: responseData)
        try await server.start()
        return server
    }

    func requests() async -> [Request] {
        await recorder.snapshot()
    }

    func stop() {
        listener.cancel()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumed.resumeOnce {
                        continuation.resume()
                    }
                case let .failed(error):
                    resumed.resumeOnce {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    resumed.resumeOnce {
                        continuation.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                assertionFailure("LocalETagHTTPServer receive failed: \(error)")
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if accumulated.containsHTTPHeaderTerminator {
                Task {
                    await self.respond(to: connection, requestData: accumulated)
                }
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) async {
        let ifNoneMatch = requestData.httpHeaderValue(named: "If-None-Match")
        await recorder.append(.init(ifNoneMatch: ifNoneMatch))

        let response: Data
        if ifNoneMatch == Self.etag {
            response = httpResponse(
                statusLine: "HTTP/1.1 304 Not Modified",
                headers: [
                    "ETag": Self.etag,
                    "Cache-Control": "no-cache",
                    "Connection": "close",
                ]
            )
        } else {
            response = httpResponse(
                statusLine: "HTTP/1.1 200 OK",
                headers: [
                    "Content-Type": "image/png",
                    "Content-Length": "\(responseData.count)",
                    "ETag": Self.etag,
                    "Cache-Control": "no-cache",
                    "Connection": "close",
                ],
                body: responseData
            )
        }

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpResponse(
        statusLine: String,
        headers: [String: String],
        body: Data = Data()
    ) -> Data {
        let headerLines = headers
            .map { "\($0.key): \($0.value)\r\n" }
            .sorted()
            .joined()
        let responseString = "\(statusLine)\r\n\(headerLines)\r\n"
        return Data(responseString.utf8) + body
    }
}

// MARK: - LockedFlag

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resumeOnce(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        action()
    }
}

// MARK: - Data Extensions

extension Data {
    var containsHTTPHeaderTerminator: Bool {
        range(of: Data("\r\n\r\n".utf8)) != nil
    }

    func httpHeaderValue(named name: String) -> String? {
        guard let string = String(data: self, encoding: .utf8) else { return nil }
        let lines = string.components(separatedBy: "\r\n")
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let headerName = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            guard headerName.caseInsensitiveCompare(name) == .orderedSame else { continue }
            let valueStart = line.index(after: separatorIndex)
            return String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
