//
//  NetworkManager.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public final class NetworkManager: NetworkManagerProtocol {

    private let hostResolver: @Sendable (APIHost) -> URL
    private let session: URLSession
    private let pipeline: InterceptorPipelineProtocol
    private let maxRetryCount: Int
    private let validResponseCodes = 200...299
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        hostResolver: @escaping @Sendable (APIHost) -> URL,
        session: URLSession = .shared,
        pipeline: InterceptorPipelineProtocol = InterceptorPipeline(),
        maxRetryCount: Int = 1,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.hostResolver = hostResolver
        self.session = session
        self.pipeline = pipeline
        self.maxRetryCount = maxRetryCount
        self.encoder = encoder
        self.decoder = decoder
    }

    public func request<E: EndpointProtocol>(for endpoint: E) async throws -> E.Response {
        let data = try await requestData(for: endpoint)
        return try decodeResponse(data, as: E.self)
    }

    public func requestData<E: EndpointProtocol>(for endpoint: E) async throws -> Data {
        return try await execute(endpoint: endpoint, attempt: 0)
    }

    // MARK: - Response decoding

    private func decodeResponse<E: EndpointProtocol>(_ data: Data, as type: E.Type) throws -> E.Response {
        if data.isEmpty {
            if let empty = EmptyResponse() as? E.Response {
                return empty
            }
            throw NetworkError.emptyResponse
        }
        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - Request execution

    private func execute<E: EndpointProtocol>(endpoint: E, attempt: Int) async throws -> Data {
        try Task.checkCancellation()

        var request = try buildRequest(from: endpoint)
        try await pipeline.adapt(&request)

        let (data, httpResponse) = try await performDataTask(for: request)
        return try await handleHTTPResponse(
            data: data,
            response: httpResponse,
            request: request,
            endpoint: endpoint,
            attempt: attempt
        )
    }

    private func performDataTask(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw NetworkError.taskCancelled
            }
            throw NetworkError.transportError(urlError)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(
                statusCode: -1,
                data: data,
                response: HTTPURLResponse()
            )
        }

        return (data, httpResponse)
    }

    private func handleHTTPResponse<E: EndpointProtocol>(
        data: Data,
        response: HTTPURLResponse,
        request: URLRequest,
        endpoint: E,
        attempt: Int
    ) async throws -> Data {
        if validResponseCodes.contains(response.statusCode) {
            return data
        }

        let shouldRetry = try await pipeline.shouldRetry(
            request,
            response: response,
            data: data,
            attempt: attempt,
            maxRetries: maxRetryCount
        )

        if shouldRetry {
            return try await execute(endpoint: endpoint, attempt: attempt + 1)
        }

        throw NetworkError.serverError(
            statusCode: response.statusCode,
            data: data,
            response: response
        )
    }

    // MARK: - Request building

    private func buildRequest<E: EndpointProtocol>(from endpoint: E) throws -> URLRequest {
        var request = URLRequest(url: try buildURL(from: endpoint))
        request.httpMethod = endpoint.httpMethod.rawValue
        request.cachePolicy = endpoint.cachePolicy
        try applyBody(to: &request, from: endpoint)
        applyHeaders(to: &request, from: endpoint)
        return request
    }

    private func buildURL<E: EndpointProtocol>(from endpoint: E) throws -> URL {
        let baseURL = hostResolver(endpoint.host)

        let fullURL = endpoint.path.isEmpty
            ? baseURL
            : baseURL.appending(path: endpoint.path)

        guard var components = URLComponents(url: fullURL, resolvingAgainstBaseURL: true) else {
            throw NetworkError.invalidUrl
        }

        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let finalURL = components.url else {
            throw NetworkError.invalidUrl
        }

        return finalURL
    }

    private func applyBody<E: EndpointProtocol>(to request: inout URLRequest, from endpoint: E) throws {
        let hasBody = endpoint.rawBody != nil || endpoint.body != nil

        if let rawBody = endpoint.rawBody {
            request.httpBody = rawBody
        } else if let body = endpoint.body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw NetworkError.encodingError(error)
            }
        }

        if hasBody, let contentType = endpoint.contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
    }

    private func applyHeaders<E: EndpointProtocol>(to request: inout URLRequest, from endpoint: E) {
        endpoint.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }
}
