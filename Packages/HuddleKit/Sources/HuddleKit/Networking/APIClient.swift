import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls Meteor methods over the backend's REST bridge.
///
/// Every exposed method is `POST /api/<method with dots → underscores>` with the
/// params object as the JSON body and `Authorization: Bearer <token>`. Success is
/// a `result` envelope; failure is a non-2xx with `{ "error": code, "reason": text }`.
///
/// There is no socket to wait on before a request, so a request is only ever as
/// slow as its own timeout.
public struct APIClient: Sendable {
    public let endpoint: ServerEndpoint
    private let transport: any HTTPTransport
    private let token: @Sendable () async -> String?
    private let onUnauthorized: @Sendable () async -> Void
    private let retryDelay: Duration

    public init(
        endpoint: ServerEndpoint,
        transport: any HTTPTransport = URLSessionTransport(),
        retryDelay: Duration = .milliseconds(300),
        token: @escaping @Sendable () async -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.retryDelay = retryDelay
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    /// A read. Retried once if the connection dropped or timed out.
    public func query<T: Decodable>(
        _ method: String,
        _ params: some Encodable & Sendable = NoParams(),
        as type: T.Type = T.self
    ) async throws -> T {
        do {
            return try await call(method, params)
        } catch let error as APIError where error.isTransient {
            try await Task.sleep(for: retryDelay)
            return try await call(method, params)
        }
    }

    /// A write. Never retried: the first attempt may have landed.
    public func mutate<T: Decodable>(
        _ method: String,
        _ params: some Encodable & Sendable = NoParams(),
        as type: T.Type = T.self
    ) async throws -> T {
        try await call(method, params)
    }

    /// `GET /` — the backend answers `{"service":"timehuddle-meteor-backend","status":"ok"}`.
    /// Used by "Test connection"; on a LAN address it also triggers the
    /// Local Network permission prompt.
    public func ping() async throws -> Bool {
        var request = URLRequest(url: endpoint.baseURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { return false }
        struct Root: Decodable { let service: String? }
        return (try? JSONDecoder().decode(Root.self, from: data))?.service == "timehuddle-meteor-backend"
    }

    // MARK: - Internals

    static func route(for method: String) -> String {
        method.replacingOccurrences(of: ".", with: "_")
    }

    private func call<T: Decodable>(_ method: String, _ params: some Encodable & Sendable) async throws -> T {
        try Task.checkCancellation()

        var request = URLRequest(url: endpoint.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(Self.route(for: method)))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            request.httpBody = try JSONEncoder().encode(params)
        } catch {
            throw APIError.decoding("Couldn’t encode params for \(method): \(error)")
        }

        let (data, response) = try await send(request)

        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let code = body?.error ?? "http-\(response.statusCode)"
            if response.statusCode == 401 || Self.unauthorizedCodes.contains(code) {
                await onUnauthorized()
                throw APIError.unauthorized
            }
            throw APIError.server(
                code: code,
                reason: body?.reason ?? body?.message ?? "",
                status: response.statusCode
            )
        }

        do {
            return try Self.makeDecoder().decode(Envelope<T>.self, from: data).result
        } catch {
            throw APIError.decoding("\(method): \(error)")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            throw APIError.from(error)
        }
    }

    private static let unauthorizedCodes: Set<String> = ["not-authorized", "unauthorized"]

    /// A decoder for backend payloads: dates arrive as epoch milliseconds or
    /// ISO-8601 strings (with or without fractional seconds).
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let ms = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            let text = try container.decode(String.self)
            if let date = FlexibleDate.parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(text)")
        }
        return decoder
    }
}

/// An empty params object, sent as `{}`.
public struct NoParams: Encodable, Sendable {
    public init() {}
}

/// ISO-8601 parsing that accepts both `2026-07-22T14:03:11.123Z` and `2026-07-22T14:03:11Z`.
enum FlexibleDate {
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// The success envelope. A missing or `null` result decodes as `nil` for an optional `T`.
struct Envelope<T: Decodable>: Decodable {
    let result: T

    private enum CodingKeys: String, CodingKey { case result }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let optional = T.self as? any OptionalDecodable.Type,
           try !container.contains(.result) || container.decodeNil(forKey: .result) {
            result = optional.nilValue as! T
        } else {
            result = try container.decode(T.self, forKey: .result)
        }
    }
}

protocol OptionalDecodable {
    static var nilValue: Self { get }
}

extension Optional: OptionalDecodable {
    static var nilValue: Self { nil }
}

/// Meteor errors carry a string code for app errors and a number for some built-ins (e.g. 403).
struct ErrorBody: Decodable {
    let error: String?
    let reason: String?
    let message: String?

    private enum CodingKeys: String, CodingKey { case error, reason, message }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .error) {
            error = text
        } else if let number = try? container.decode(Int.self, forKey: .error) {
            error = String(number)
        } else {
            error = nil
        }
        reason = try? container.decode(String.self, forKey: .reason)
        message = try? container.decode(String.self, forKey: .message)
    }
}
