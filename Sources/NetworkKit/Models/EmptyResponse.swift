//
//  EmptyResponse.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

/// Marker response type for endpoints that return no body (e.g. HTTP 204).
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
