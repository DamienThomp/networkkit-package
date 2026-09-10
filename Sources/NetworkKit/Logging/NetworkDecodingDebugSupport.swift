//
//  NetworkDecodingDebugSupport.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-10.
//

import Foundation

enum NetworkDecodingDebugSupport {
    static func decodingFailureMessage<E: EndpointProtocol>(
        endpoint: E.Type,
        data: Data,
        error: Error,
        url: URL?,
        statusCode: Int?
    ) -> String {
        var lines = [
            "Decoding failed",
            "Endpoint: \(String(describing: endpoint))",
            "Expected: \(E.Response.self)"
        ]

        if let url {
            lines.append("URL: \(url.absoluteString)")
        }

        if let statusCode {
            lines.append("Status: \(statusCode)")
        }

        lines.append("Body (\(data.count) bytes):")
        lines.append(prettyJSONString(from: data) ?? utf8Preview(data))
        lines.append("Error: \(describeDecodingError(error))")

        return lines.joined(separator: "\n")
    }

    static func utf8Preview(_ data: Data, limit: Int = 4_096) -> String {
        let clipped = data.prefix(limit)
        let suffix = data.count > limit ? "\n… truncated (\(data.count) total bytes)" : ""
        let preview = String(data: clipped, encoding: .utf8) ?? "<non-UTF8 binary>"
        return preview + suffix
    }

    static func prettyJSONString(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: error)
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))"
        case .typeMismatch(let type, let context):
            return "Type mismatch: expected \(type) at \(codingPathDescription(context.codingPath))"
        case .valueNotFound(let type, let context):
            return "Null/missing value for \(type) at \(codingPathDescription(context.codingPath))"
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        codingPath.map(\.stringValue).joined(separator: ".")
    }
}
