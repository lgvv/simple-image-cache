import Foundation

/// 미들웨어 기반 HTTP 클라이언트
///
/// 등록 순서대로 미들웨어 적용 후 전송 계층 호출
public struct HTTPClient: Sendable {
    private let transport: any HTTPTransport
    private let middlewares: [any HTTPClientMiddleware]

    /// 클라이언트 초기화
    ///
    /// - Parameters:
    ///   - transport: 실제 전송 계층
    ///   - middlewares: 요청/응답 가로채기 목록
    public init(
        transport: any HTTPTransport,
        middlewares: [any HTTPClientMiddleware]
    ) {
        self.transport = transport
        self.middlewares = middlewares
    }

    /// 전송 계층 교체
    ///
    /// - Parameter transport: 새 요청 전송 계층
    /// - Returns: 동일 미들웨어를 사용하는 새 HTTPClient
    public func replacingTransport(_ transport: any HTTPTransport) -> HTTPClient {
        HTTPClient(transport: transport, middlewares: middlewares)
    }

    /// 요청 전송 후 응답 디코딩
    ///
    /// - Parameter request: 전송 대상 요청
    /// - Returns: 디코딩된 응답 모델
    /// - Throws: 전송 / 상태 코드 / 디코딩 에러
    public func send<ResponseType: Decodable>(
        request: HTTPRequest,
        decoder: some ResponseDecoder = JSONResponseDecoder()
    ) async throws -> ResponseType {
        let response: HTTPResponse
        do {
            response = try await sendThroughPipeline(request: request)
        } catch let failure as HTTPFailure {
            throw failure
        } catch {
            throw HTTPFailure(request: request, response: nil, error: error)
        }

        guard let data = response.body else {
            throw HTTPFailure(
                request: request,
                response: response,
                error: HTTPClientError.missingResponseData
            )
        }

        do {
            return try decoder.decode(ResponseType.self, from: data)
        } catch {
            throw HTTPFailure(
                request: request,
                response: response,
                error: HTTPClientError.decodingFailed(
                    underlyingError: error,
                    data: data
                )
            )
        }
    }

    private func sendThroughPipeline(request: HTTPRequest) async throws -> HTTPResponse {
        let terminal: @Sendable (HTTPRequest) async throws -> HTTPResponse = { _request in
            try await transport.send(request: _request)
        }

        var pipeline = terminal
        for middleware in middlewares.reversed() {
            let next = pipeline
            pipeline = { _request in
                try await middleware.intercept(request: _request, next: next)
            }
        }

        do {
            return try await pipeline(request)
        } catch let failure as HTTPFailure {
            throw failure
        } catch {
            throw HTTPFailure(request: request, response: nil, error: error)
        }
    }
}

public extension HTTPClient {
    /// 기본 라이브 설정
    ///
    /// `URLSession.shared`와 상태 코드 검증 미들웨어 사용
    static let live: HTTPClient = .init(
        transport: URLSessionTransport(urlSession: .shared),
        middlewares: [
            StatusCodeValidationMiddleware(),
        ]
    )
}
