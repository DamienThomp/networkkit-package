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
    private let decoder: JSONDecoder

    public init(
        hostResolver: @escaping @Sendable (APIHost) -> URL,
        session: URLSession = .shared,
        pipeline: InterceptorPipelineProtocol = InterceptorPipeline(),
        maxRetryCount: Int = 1,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.hostResolver = hostResolver
        self.session = session
        self.pipeline = pipeline
        self.maxRetryCount = maxRetryCount
        self.decoder = decoder
    }

    public func request<E: EndpointProtocol>(for endpoint: E) async throws -> E.Response {
        let data = try await requestData(for: endpoint)
        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    public func requestData<E: EndpointProtocol>(for endpoint: E) async throws -> Data {
        return try await execute(endpoint: endpoint, attempt: 0)
    }

    private func execute<E: EndpointProtocol>(endpoint: E, attempt: Int) async throws -> Data {
        try Task.checkCancellation()

        var request = try buildRequest(from: endpoint)
        try await pipeline.adapt(&request)

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

        if validResponseCodes.contains(httpResponse.statusCode) {
            return data
        }

        let shouldRetry = try await pipeline.shouldRetry(
            request,
            response: httpResponse,
            data: data,
            attempt: attempt,
            maxRetries: maxRetryCount
        )

        if shouldRetry {
            return try await execute(endpoint: endpoint, attempt: attempt + 1)
        }

        throw NetworkError.serverError(
            statusCode: httpResponse.statusCode,
            data: data,
            response: httpResponse
        )
    }

    private func buildRequest<E: EndpointProtocol>(from endpoint: E) throws -> URLRequest {
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

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.httpMethod.rawValue
        request.cachePolicy = endpoint.cachePolicy

        if let contentType = endpoint.contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }

        if let body = endpoint.body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw NetworkError.encodingError(error)
            }
        }

        endpoint.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        return request
    }
}
