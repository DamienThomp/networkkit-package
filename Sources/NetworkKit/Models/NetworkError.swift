//
//  NetworkError.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public enum NetworkError: Error, LocalizedError, Sendable {
    case invalidUrl
    case taskCancelled
    case serverError(statusCode: Int, data: Data, response: HTTPURLResponse)
    case decodingError(Error)
    case encodingError(Error)
    case transportError(URLError)
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "The request URL was invalid."
        case .taskCancelled:
            return "The network task was cancelled."
        case .serverError(let code, _, _):
            return "Server responded with status code \(code)."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request body: \(error.localizedDescription)"
        case .transportError(let error):
            return "Transport error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication failed. Session expired."
        }
    }
}
