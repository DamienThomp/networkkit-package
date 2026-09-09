import Foundation
@testable import NetworkKit

final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var shouldHangUntilStopped = false

    private var didFinish = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if Self.shouldHangUntilStopped {
            return
        }

        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            didFinish = true
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            didFinish = true
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        guard Self.shouldHangUntilStopped, !didFinish else { return }
        didFinish = true
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

final class CapturingInterceptor: RequestInterceptor, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?

    func adapt(_ request: inout URLRequest) async throws {
        Self.lastRequest = request
    }
}

enum TestSupport {
    static let defaultBaseURL = URL(string: "https://api.example.com")!

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func makeManager(
        session: URLSession? = nil,
        authManager: AuthManagerProtocol? = nil,
        customInterceptors: [RequestInterceptor] = [],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        maxRetryCount: Int = 1
    ) -> NetworkManager {
        var interceptors: [RequestInterceptor] = customInterceptors

        if let authManager {
            interceptors.insert(AuthInterceptor(authManager: authManager), at: 0)
        }

        return NetworkManager(
            hostResolver: { host in
                switch host.rawValue {
                case "secondary":
                    URL(string: "https://secondary.example.com")!
                default:
                    defaultBaseURL
                }
            },
            session: session ?? makeSession(),
            pipeline: InterceptorPipeline(interceptors: interceptors),
            maxRetryCount: maxRetryCount,
            encoder: encoder,
            decoder: decoder
        )
    }

    static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}
