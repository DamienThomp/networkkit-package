//
//  NetworkManagerProtocol.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public protocol NetworkManagerProtocol: Sendable {
    func request<E: EndpointProtocol>(for endpoint: E) async throws -> E.Response
    func requestData<E: EndpointProtocol>(for endpoint: E) async throws -> Data
    func response<E: EndpointProtocol>(for endpoint: E) async throws -> NetworkResponse<E.Response>
    func responseData<E: EndpointProtocol>(for endpoint: E) async throws -> NetworkResponse<Data>
}
