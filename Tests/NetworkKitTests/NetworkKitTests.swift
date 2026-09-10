import Foundation
import Testing
@testable import NetworkKit

// MARK: - Test models

private struct UserResponse: Codable, Sendable, Equatable {
    let userName: String
}

private struct UserRequestBody: Encodable, Sendable {
    let userName: String
}

private struct DefaultGetEndpoint: EndpointProtocol {
    typealias Response = UserResponse

    var path: String
    var httpMethod: HTTPMethod = .get
    var host: APIHost = .default
    var queryItems: [URLQueryItem]? = nil
}

private struct EmptyBodyEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    var path: String = "resource"
    var httpMethod: HTTPMethod = .delete
}

private struct JSONBodyEndpoint: EndpointProtocol {
    typealias Response = UserResponse

    var path: String = "users"
    var httpMethod: HTTPMethod = .post
    var body: (any Encodable & Sendable)? {
        UserRequestBody(userName: "ignored")
    }
}

private struct RawBodyEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    var path: String = "upload"
    var httpMethod: HTTPMethod = .post
    var rawBody: Data? {
        Data([0x01, 0x02, 0x03])
    }
    var body: (any Encodable & Sendable)? {
        UserRequestBody(userName: "ignored")
    }
    var contentType: ContentType? { .protobuf }
}

private struct ProtobufGetEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    var path: String = "gtfs-realtime"
    var httpMethod: HTTPMethod = .get
    var contentType: ContentType? = .protobuf
}

private struct SecondaryHostEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    var host: APIHost = "secondary"
    var path: String = "feed"
    var httpMethod: HTTPMethod = .get
}

private struct SnakeCaseEndpoint: EndpointProtocol {
    typealias Response = UserResponse

    var path: String = "profile"
    var httpMethod: HTTPMethod = .post
    var body: (any Encodable & Sendable)? {
        UserRequestBody(userName: "Ada")
    }
}

private actor MockAuthManager: AuthManagerProtocol {
    private(set) var refreshCount = 0
    private var shouldFailRefresh = false
    var credential: AuthCredential? = .bearer("test-token")

    func setShouldFailRefresh(_ value: Bool) {
        shouldFailRefresh = value
    }

    func refreshCredentials() async throws {
        refreshCount += 1
        try await Task.sleep(for: .milliseconds(25))
        if shouldFailRefresh {
            throw URLError(.userAuthenticationRequired)
        }
    }
}

private struct StaticCredentialAuthManager: AuthManagerProtocol {
    let storedCredential: AuthCredential?

    var credential: AuthCredential? {
        get async { storedCredential }
    }

    func refreshCredentials() async throws {}

    func shouldRefresh(for response: HTTPURLResponse) -> Bool {
        false
    }
}

private actor CustomRefreshAuthManager: AuthManagerProtocol {
    private(set) var refreshCount = 0

    var credential: AuthCredential? {
        get async { .bearer("test-token") }
    }

    func refreshCredentials() async throws {
        refreshCount += 1
    }

    nonisolated func shouldRefresh(for response: HTTPURLResponse) -> Bool {
        response.statusCode == 403
    }
}

// MARK: - Helpers

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private func setHandler(
    _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) {
    MockURLProtocol.requestHandler = handler
}

private func resetMockState() {
    MockURLProtocol.requestHandler = nil
    MockURLProtocol.shouldHangUntilStopped = false
    CapturingInterceptor.lastRequest = nil
    CapturingNetworkLogger.messages = []
}

// MARK: - Tests

@Suite(.serialized)
struct NetworkKitTestSuite {

@Test func requestDecodesSuccessBody() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        let data = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), data)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manager = TestSupport.makeManager(decoder: decoder)

    let user = try await manager.request(for: DefaultGetEndpoint(path: "users/1"))
    #expect(user.userName == "Ada")
}

@Test func requestDataReturnsRawBytes() async throws {
    resetMockState()
    defer { resetMockState() }

    let payload = Data([0x0A, 0x0B, 0x0C])
    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 200), payload)
    }

    let manager = TestSupport.makeManager()
    let data = try await manager.requestData(for: ProtobufGetEndpoint())
    #expect(data == payload)
}

@Test func emptyBodyReturnsEmptyResponse() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let manager = TestSupport.makeManager()
    _ = try await manager.request(for: EmptyBodyEndpoint())
}

@Test func emptyBodyWithDecodableResponseThrowsEmptyResponse() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 200), Data())
    }

    let manager = TestSupport.makeManager()

    do {
        _ = try await manager.request(for: DefaultGetEndpoint(path: "users/1"))
        Issue.record("Expected emptyResponse to be thrown")
    } catch let error as NetworkError {
        guard case .emptyResponse = error else {
            Issue.record("Expected emptyResponse, got \(error)")
            return
        }
    }
}

@Test func nonSuccessStatusMapsToServerError() async throws {
    resetMockState()
    defer { resetMockState() }

    let errorBody = Data("{\"error\":\"not found\"}".utf8)
    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 404), errorBody)
    }

    let manager = TestSupport.makeManager(maxRetryCount: 0)

    do {
        _ = try await manager.requestData(for: DefaultGetEndpoint(path: "missing"))
        Issue.record("Expected serverError to be thrown")
    } catch let error as NetworkError {
        guard case .serverError(let statusCode, let data, _) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(statusCode == 404)
        #expect(data == errorBody)
    }
}

@Test func malformedJSONMapsToDecodingError() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 200), Data("not-json".utf8))
    }

    let manager = TestSupport.makeManager()

    do {
        _ = try await manager.request(for: DefaultGetEndpoint(path: "users/1"))
        Issue.record("Expected decodingError to be thrown")
    } catch let error as NetworkError {
        guard case .decodingError = error else {
            Issue.record("Expected decodingError, got \(error)")
            return
        }
    }

    #expect(CapturingNetworkLogger.messages.count == 1)
    let log = try #require(CapturingNetworkLogger.messages.first)
    #expect(log.contains("Decoding failed"))
    #expect(log.contains("DefaultGetEndpoint"))
    #expect(log.contains("UserResponse"))
    #expect(log.contains("users/1"))
    #expect(log.contains("Status: 200"))
    #expect(log.contains("not-json"))
}

@Test func injectedEncoderAndDecoderStrategiesAreHonored() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        let response = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), response)
    }

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let manager = TestSupport.makeManager(
        customInterceptors: [CapturingInterceptor()],
        encoder: encoder,
        decoder: decoder
    )
    let user = try await manager.request(for: SnakeCaseEndpoint())

    let bodyString = String(decoding: CapturingInterceptor.lastRequest?.httpBody ?? Data(), as: UTF8.self)
    #expect(bodyString.contains("\"user_name\""))
    #expect(user.userName == "Ada")
}

@Test func rawBodyTakesPrecedenceOverEncodableBody() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let manager = TestSupport.makeManager(customInterceptors: [CapturingInterceptor()])
    _ = try await manager.request(for: RawBodyEndpoint())

    let captured = CapturingInterceptor.lastRequest
    #expect(captured?.httpBody == Data([0x01, 0x02, 0x03]))
    #expect(captured?.value(forHTTPHeaderField: "Content-Type") == ContentType.protobuf.rawValue)
}

@Test func contentTypeHeaderIsAbsentForBodylessGET() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 200), Data([0x01]))
    }

    let manager = TestSupport.makeManager(customInterceptors: [CapturingInterceptor()])
    _ = try await manager.requestData(for: ProtobufGetEndpoint())

    let captured = CapturingInterceptor.lastRequest
    #expect(captured?.httpBody == nil)
    #expect(captured?.value(forHTTPHeaderField: "Content-Type") == nil)
}

@Test func contentTypeHeaderIsSetWhenBodyExists() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        let response = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), response)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manager = TestSupport.makeManager(
        customInterceptors: [CapturingInterceptor()],
        decoder: decoder
    )
    _ = try await manager.request(for: JSONBodyEndpoint())

    let captured = CapturingInterceptor.lastRequest
    #expect(captured?.httpBody != nil)
    #expect(captured?.value(forHTTPHeaderField: "Content-Type") == ContentType.json.rawValue)
}

@Test func authInterceptorAppliesDiscogsTokenCredential() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let authManager = StaticCredentialAuthManager(
        storedCredential: .token(scheme: "Discogs", token: "my-discogs-token")
    )
    let manager = TestSupport.makeManager(
        authManager: authManager,
        customInterceptors: [CapturingInterceptor()]
    )

    _ = try await manager.requestData(for: DefaultGetEndpoint(path: "releases/1"))

    let captured = CapturingInterceptor.lastRequest
    #expect(captured?.value(forHTTPHeaderField: "Authorization") == "Discogs token=my-discogs-token")
}

@Test func authInterceptorAppliesCustomHeaderCredential() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let authManager = StaticCredentialAuthManager(
        storedCredential: .header(field: "X-API-Key", value: "secret-key")
    )
    let manager = TestSupport.makeManager(
        authManager: authManager,
        customInterceptors: [CapturingInterceptor()]
    )

    _ = try await manager.requestData(for: DefaultGetEndpoint(path: "resource"))

    let captured = CapturingInterceptor.lastRequest
    #expect(captured?.value(forHTTPHeaderField: "X-API-Key") == "secret-key")
    #expect(captured?.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func authInterceptorUsesCustomShouldRefreshStatusCode() async throws {
    resetMockState()
    defer { resetMockState() }

    let authManager = CustomRefreshAuthManager()
    let attemptCounter = AttemptCounter()

    setHandler { request in
        let currentAttempt = attemptCounter.increment()

        if currentAttempt == 1 {
            return (TestSupport.httpResponse(for: request, statusCode: 403), Data())
        }

        let response = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), response)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manager = TestSupport.makeManager(authManager: authManager, decoder: decoder)

    let user = try await manager.request(for: DefaultGetEndpoint(path: "protected"))
    #expect(user.userName == "Ada")
    #expect(await authManager.refreshCount == 1)
}

@Test func authInterceptorRefreshesAndRetriesOn401() async throws {
    resetMockState()
    defer { resetMockState() }

    let authManager = MockAuthManager()
    let attemptCounter = AttemptCounter()

    setHandler { request in
        let currentAttempt = attemptCounter.increment()

        if currentAttempt == 1 {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (TestSupport.httpResponse(for: request, statusCode: 401), Data())
        }

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let response = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), response)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manager = TestSupport.makeManager(authManager: authManager, decoder: decoder)

    let user = try await manager.request(for: DefaultGetEndpoint(path: "protected"))
    #expect(user.userName == "Ada")
    #expect(await authManager.refreshCount == 1)
}

@Test func concurrent401sTriggerSingleRefresh() async throws {
    resetMockState()
    defer { resetMockState() }

    let authManager = MockAuthManager()
    let attemptCounter = AttemptCounter()

    setHandler { request in
        let currentAttempt = attemptCounter.increment()

        if currentAttempt <= 3 {
            return (TestSupport.httpResponse(for: request, statusCode: 401), Data())
        }

        let response = Data("{\"user_name\":\"Ada\"}".utf8)
        return (TestSupport.httpResponse(for: request, statusCode: 200), response)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manager = TestSupport.makeManager(authManager: authManager, decoder: decoder)

    try await withThrowingTaskGroup(of: UserResponse.self) { group in
        for _ in 0..<3 {
            group.addTask {
                try await manager.request(for: DefaultGetEndpoint(path: "protected"))
            }
        }

        for try await user in group {
            #expect(user.userName == "Ada")
        }
    }

    #expect(await authManager.refreshCount == 1)
}

@Test func refreshFailureSurfacesUnauthorized() async throws {
    resetMockState()
    defer { resetMockState() }

    let authManager = MockAuthManager()
    await authManager.setShouldFailRefresh(true)

    setHandler { request in
        (TestSupport.httpResponse(for: request, statusCode: 401), Data())
    }

    let manager = TestSupport.makeManager(authManager: authManager, maxRetryCount: 1)

    do {
        _ = try await manager.requestData(for: DefaultGetEndpoint(path: "protected"))
        Issue.record("Expected unauthorized to be thrown")
    } catch let error as NetworkError {
        guard case .unauthorized = error else {
            Issue.record("Expected unauthorized, got \(error)")
            return
        }
    }
}

@Test func cancellationMapsToTaskCancelled() async throws {
    resetMockState()
    defer { resetMockState() }

    MockURLProtocol.shouldHangUntilStopped = true

    let manager = TestSupport.makeManager()
    let endpoint = DefaultGetEndpoint(path: "slow")

    let task = Task {
        try await manager.requestData(for: endpoint)
    }

    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected cancellation error to be thrown")
    } catch is CancellationError {
        return
    } catch let error as NetworkError {
        guard case .taskCancelled = error else {
            Issue.record("Expected taskCancelled, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func queryItemsAndHostResolutionBuildExpectedURL() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        #expect(request.url?.absoluteString == "https://api.example.com/search?q=swift&page=2")
        return (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let manager = TestSupport.makeManager()
    let endpoint = DefaultGetEndpoint(
        path: "search",
        queryItems: [
            URLQueryItem(name: "q", value: "swift"),
            URLQueryItem(name: "page", value: "2")
        ]
    )
    _ = try await manager.requestData(for: endpoint)
}

@Test func secondaryHostUsesHostResolver() async throws {
    resetMockState()
    defer { resetMockState() }

    setHandler { request in
        #expect(request.url?.absoluteString == "https://secondary.example.com/feed")
        return (TestSupport.httpResponse(for: request, statusCode: 204), Data())
    }

    let manager = TestSupport.makeManager()
    _ = try await manager.request(for: SecondaryHostEndpoint())
}

}