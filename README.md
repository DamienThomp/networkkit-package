# NetworkKit

Swift 6 concurrency-compliant networking library for modular iOS and macOS applications.

NetworkKit is a reusable transport layer: it builds requests, executes them through an optional interceptor pipeline, and returns raw `Data` or decoded models. Decoding strategy, auth refresh, multi-host routing, and debug logging are configurable per app. Interceptor conformance follows Swift concurrency guidelines — see [Concurrency](#concurrency) below.

## Requirements

- Swift 6.3+
- iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

## Installation

Add NetworkKit as a local or remote Swift Package dependency:

```swift
dependencies: [
    .package(path: "../NetworkKit")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["NetworkKit"]
    )
]
```

## Quick start

### 1. Define an endpoint

```swift
struct GetUserEndpoint: EndpointProtocol {
    typealias Response = User

    let userID: String

    var path: String { "users/\(userID)" }
    var httpMethod: HTTPMethod { .get }
}
```

Default protocol values provide:

- `host`: `.default`
- `contentType`: `.json` (applied only when a body is present)
- `cachePolicy`: `.useProtocolCachePolicy`

### 2. Configure hosts

Use `APIHost` plus a resolver closure so the same endpoints work across apps and environments:

```swift
extension APIHost {
    static let api = APIHost(rawValue: "api")
    static let gtfs = APIHost(rawValue: "gtfs")
}

let client = NetworkManagerFactory.makeDefaultClient { host in
    switch host {
    case .api:
        URL(string: "https://api.example.com/v1")!
    case .gtfs:
        URL(string: "https://gtfs.example.com")!
    default:
        URL(string: "https://api.example.com/v1")!
    }
}
```

### 3. Make requests

Decoded JSON response:

```swift
let user = try await client.request(for: GetUserEndpoint(userID: "42"))
```

Raw response bytes (protobuf, images, etc.):

```swift
let data = try await client.requestData(for: GTFSRealtimeEndpoint())
// Decode with SwiftProtobuf or another library in your DataFetcher/Interactor layer.
```

No-content endpoints (`204`, empty body):

```swift
struct DeleteUserEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    let userID: String
    var path: String { "users/\(userID)" }
    var httpMethod: HTTPMethod { .delete }
}

_ = try await client.request(for: DeleteUserEndpoint(userID: "42"))
```

### Response envelope (headers + decoded value)

When the caller needs HTTP headers alongside the decoded body — pagination (`Link`), caching (`ETag`), etc. — use `response(for:)`:

```swift
let networkResponse = try await client.response(for: ListUsersEndpoint(page: 1))
let users = networkResponse.value
let linkHeader = networkResponse.header(named: "Link")
```

`NetworkResponse` also includes `statusCode` and `url`. Use `header(named:)` for case-insensitive header lookup.

For raw bytes with headers, use `responseData(for:)`:

```swift
let networkResponse = try await client.responseData(for: GTFSRealtimeEndpoint())
let protobufData = networkResponse.value
let etag = networkResponse.header(named: "ETag")
```

Existing `request(for:)` and `requestData(for:)` are unchanged.

## Request bodies

### JSON (`Encodable`)

```swift
struct CreateUserEndpoint: EndpointProtocol {
    typealias Response = User

    let name: String
    var path: String { "users" }
    var httpMethod: HTTPMethod { .post }
    var body: (any Encodable & Sendable)? { CreateUserBody(name: name) }
}
```

### Raw bytes (`rawBody`)

Use `rawBody` for pre-serialized or non-JSON payloads. **`rawBody` takes precedence over `body`.**

```swift
struct UploadProtobufEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse

    let payload: Data
    var path: String { "ingest" }
    var httpMethod: HTTPMethod { .post }
    var rawBody: Data? { payload }
    var contentType: ContentType? { .protobuf }
}
```

## Content types

`ContentType` is a string-backed extensible value (similar to `APIHost`):

```swift
ContentType.json              // application/json
ContentType.protobuf          // application/x-protobuf
ContentType.octetStream       // application/octet-stream
ContentType.formURLEncoded    // application/x-www-form-urlencoded
"application/custom"          // custom via string literal
```

The `Content-Type` header is set **only when the request has a body** (`rawBody` or `body`). Bodyless GET requests (typical for GTFS Realtime feeds) do not send a bogus JSON content type.

## GTFS Realtime example

GTFS Realtime responses are binary protobuf. Fetch raw bytes and decode outside NetworkKit:

```swift
struct GTFSRealtimeEndpoint: EndpointProtocol {
    typealias Response = EmptyResponse // use requestData, not request

    var host: APIHost { .gtfs }
    var path: String { "gtfs-realtime" }
    var httpMethod: HTTPMethod { .get }
}

let protobufData = try await client.requestData(for: GTFSRealtimeEndpoint())
// let feed = try TransitRealtime_FeedMessage(serializedBytes: protobufData)
```

## Authentication (optional)

Pass an `AuthManagerProtocol` to attach credentials and optionally refresh when a response indicates auth failure.

`AuthCredential` supports common header-based schemes:

```swift
AuthCredential.bearer("oauth-access-token")              // Authorization: Bearer …
AuthCredential.token(scheme: "Discogs", token: "…")      // Authorization: Discogs token=…
AuthCredential.header(field: "X-API-Key", value: "…")    // arbitrary header
```

OAuth 1.0a request signing is not handled here — implement a custom `RequestInterceptor` for per-request signatures.

### Bearer token with refresh (OAuth2-style)

```swift
struct MyAuthManager: AuthManagerProtocol {
    var credential: AuthCredential? {
        get async { .bearer(accessToken) }
    }

    func refreshCredentials() async throws {
        // fetch a new access token
    }
}

let client = NetworkManagerFactory.makeDefaultClient(
    hostResolver: hostResolver,
    authManager: MyAuthManager()
)
```

By default, `shouldRefresh(for:)` returns `true` for HTTP `401`. Override it when an API uses a different status code or does not support refresh:

```swift
func shouldRefresh(for response: HTTPURLResponse) -> Bool {
    response.statusCode == 401
}
```

### Static token (no refresh)

Discogs user tokens and similar credentials do not expire. Return the credential and disable refresh:

```swift
struct DiscogsAuthManager: AuthManagerProtocol {
    let userToken: String

    var credential: AuthCredential? {
        get async { .token(scheme: "Discogs", token: userToken) }
    }

    func refreshCredentials() async throws {}

    func shouldRefresh(for response: HTTPURLResponse) -> Bool {
        false
    }
}
```

If no auth manager is provided, no auth interceptor is installed.

## Custom interceptors

```swift
struct LoggingInterceptor: RequestInterceptor {
    func adapt(_ request: inout URLRequest) async throws {
        print("→ \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
    }
}

let client = NetworkManagerFactory.makeDefaultClient(
    hostResolver: hostResolver,
    customInterceptors: [LoggingInterceptor()]
)
```

Interceptors can:

- **`adapt`**: mutate the outgoing request (headers, signing, logging)
- **`retry`**: return `.retry` to re-run the request after a failed response
- **`didReceive`**: observe every response (2xx included) before decoding

### Concurrency

`RequestInterceptor` conforms to `Sendable`. Interceptors run **sequentially in registration order** for each request, but **concurrent requests** can run their pipelines in parallel.

- **Stateless interceptors** (logging, headers): prefer a `struct`.
- **Shared mutable state** (token refresh, rate-limit counters): use an `actor`, like the built-in `AuthInterceptor`.
- Avoid `@unchecked Sendable` unless you can prove thread safety yourself.

### Response observation

For cross-cutting side effects like rate-limit tracking, implement `didReceive` on a custom interceptor. It runs on every response — success, failure, and each retry attempt — and cannot fail the request. If the tracker holds shared mutable state, implement it as an `actor` rather than a `struct`:

```swift
struct RateLimitTracker: RequestInterceptor {
    func adapt(_ request: inout URLRequest) async throws {}

    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        guard let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
              let count = Int(remaining) else { return }
        // update throttle state (use an actor if this state is shared)
    }
}

let client = NetworkManagerFactory.makeDefaultClient(
    hostResolver: hostResolver,
    customInterceptors: [RateLimitTracker()]
)
```

NetworkKit surfaces raw headers; your app owns parsing and policy (thresholds, `Retry-After`, etc.).

## Encoder and decoder configuration

```swift
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601

let client = NetworkManagerFactory.makeDefaultClient(
    hostResolver: hostResolver,
    encoder: encoder,
    decoder: decoder
)
```

## Debug logging

In **DEBUG** builds, `NetworkManager` logs detailed context when JSON decoding fails. This helps diagnose model mismatches without attaching a proxy or adding one-off prints.

By default:

- **DEBUG** builds use `DebugNetworkLogger` (`os.Logger`, subsystem `NetworkKit`, category `Network`)
- **Release** builds use `NoOpNetworkLogger` (no logging, no overhead)

When decoding fails, the log includes:

- Endpoint and expected response type
- Request URL and HTTP status code
- Response body (pretty-printed JSON when possible, otherwise a UTF-8 preview truncated at 4 KB)
- A formatted `DecodingError` with the coding path (e.g. missing key, type mismatch)

Example Console output:

```
Decoding failed
Endpoint: GetUserEndpoint
Expected: User
URL: https://api.example.com/v1/users/42
Status: 200
Body (58 bytes):
{
  "created_at" : 1699999999,
  "id" : 42
}
Error: Type mismatch: expected String at createdAt
```

### Custom logger

Inject any type conforming to `NetworkLogging` when creating a `NetworkManager`:

```swift
let client = NetworkManager(
    hostResolver: hostResolver,
    logger: DebugNetworkLogger(subsystem: "com.example.app", category: "API")
)
```

Use `NoOpNetworkLogger()` to silence logs even in DEBUG builds. Implement `NetworkLogging` in your app to route messages to your own logging system.

`NetworkManagerFactory.makeDefaultClient` uses the same DEBUG/release default; construct `NetworkManager` directly when you need a custom logger.

## Error handling

`NetworkError` cases:

| Case | When |
|------|------|
| `.invalidUrl` | URL construction failed |
| `.taskCancelled` | Request was cancelled |
| `.serverError(statusCode:data:response:)` | Non-2xx HTTP response |
| `.emptyResponse` | Empty body when a decodable response was expected |
| `.decodingError` | JSON decoding failed (see [Debug logging](#debug-logging) for response body details in DEBUG builds) |
| `.encodingError` | Request body encoding failed |
| `.transportError` | `URLError` from the transport layer |
| `.unauthorized` | Token refresh failed after `401` |

All cases conform to `LocalizedError`.

## Public API note

While this package is private, the public surface may evolve freely. Once published, public symbols become the semver contract.

## Testing

Run tests with:

```bash
swift test
```

Tests use a stubbed `URLSession` backed by `MockURLProtocol` so no network access is required.
