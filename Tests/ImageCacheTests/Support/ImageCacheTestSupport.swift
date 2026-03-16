import Caches
import Common
import Foundation
@testable import ImageCache
import Networks
import UIKit

func makePNGData(width: CGFloat = 1, height: CGFloat = 1) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return image.pngData() ?? Data()
}

func makeHybridCache() throws -> HybridCache {
    let disk = try DiskCache(configuration: .init(directoryName: "ImageCacheTests-\(UUID().uuidString)"))
    return HybridCache(disk: disk)
}

actor TransportSpy: HTTPTransport {
    private let responseData: Data
    private let delay: UInt64
    private let delays: [URL: UInt64]
    private let failURLs: Set<URL>
    private var callCountStorage: Int = 0
    private var maxConcurrentStorage: Int = 0
    private var currentCount: Int = 0

    init(
        responseData: Data,
        delay: UInt64 = 0,
        delays: [URL: UInt64] = [:],
        failURLs: Set<URL> = []
    ) {
        self.responseData = responseData
        self.delay = delay
        self.delays = delays
        self.failURLs = failURLs
    }

    func send(request: HTTPRequest) async throws -> HTTPResponse {
        callCountStorage += 1
        currentCount += 1
        if currentCount > maxConcurrentStorage {
            maxConcurrentStorage = currentCount
        }

        defer {
            currentCount -= 1
        }

        let effectiveDelay = delays[request.url] ?? delay
        if effectiveDelay > 0 {
            try await Task.sleep(nanoseconds: effectiveDelay)
        }

        try Task.checkCancellation()

        if failURLs.contains(request.url) {
            throw URLError(.badServerResponse)
        }

        return HTTPResponse(
            requestURL: request.url,
            statusCode: 200,
            headers: [:],
            body: responseData
        )
    }

    func callCount() -> Int {
        callCountStorage
    }

    func maxConcurrent() -> Int {
        maxConcurrentStorage
    }
}

actor MiddlewareCallCounter {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}

struct FailingTransport: HTTPTransport {
    func send(request _: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.cannotFindHost)
    }
}

struct ImmediateImageResponseMiddleware: HTTPClientMiddleware {
    let data: Data
    let counter: MiddlewareCallCounter

    func intercept(
        request: HTTPRequest,
        next _: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        await counter.increment()
        return HTTPResponse(
            requestURL: request.url,
            statusCode: 200,
            headers: [:],
            body: data
        )
    }
}

final class CountingDecoder: ImageDecoder, @unchecked Sendable {
    private let decodeCountStorage = LockIsolated(0)

    func decode(_ data: Data) throws -> UIImage {
        decodeCountStorage.withValue {
            $0 += 1
        }
        guard let image = UIImage(data: data) else {
            throw ImageCacheError.invalidImageData
        }
        return image
    }

    func decodeCount() -> Int {
        decodeCountStorage.value
    }
}

struct AlwaysFailingDecoder: ImageDecoder {
    func decode(_: Data) throws -> UIImage {
        throw ImageCacheError.invalidImageData
    }
}

struct FailingImageDataStore: ImageDataStore {
    private let failOnGet: Bool

    init(failOnGet: Bool = false) {
        self.failOnGet = failOnGet
    }

    func value(for _: String) async throws -> Data? {
        if failOnGet {
            throw NSError(domain: "test", code: 1)
        }
        return nil
    }

    func set(_: Data, for _: String) async throws {
        throw NSError(domain: "test", code: 2)
    }

    func removeValue(for _: String) async throws {}
    func flush() async {}
    func removeMemory() async {}
}
