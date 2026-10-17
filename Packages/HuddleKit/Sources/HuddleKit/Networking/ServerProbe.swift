import Foundation

/// The server picker's "Test connection": is there a TimeHuddle backend at this
/// address, and how quickly does it answer? On a LAN address the request also
/// triggers iOS's Local Network permission prompt.
public struct ServerProbe: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// A TimeHuddle backend answered, after this many milliseconds.
        case reachable(milliseconds: Int)
        /// Something answered, but it isn't a TimeHuddle backend.
        case notTimeHuddle
        /// Nothing answered in time, or the connection failed.
        case unreachable(APIError)
    }

    private let transport: any HTTPTransport
    private let timeout: Duration

    public init(transport: any HTTPTransport = URLSessionTransport(), timeout: Duration = .seconds(5)) {
        self.transport = transport
        self.timeout = timeout
    }

    public func check(_ endpoint: ServerEndpoint) async -> Outcome {
        let client = APIClient(endpoint: endpoint, transport: transport, token: { nil })
        let timeout = self.timeout
        let clock = ContinuousClock()
        let start = clock.now

        let result: Result<Bool, APIError> = await withTaskGroup(of: Result<Bool, APIError>.self) { group in
            group.addTask {
                do { return .success(try await client.ping()) } catch { return .failure(APIError.from(error)) }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.timeout)
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        switch result {
        case .success(true):
            let elapsed = clock.now - start
            let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            return .reachable(milliseconds: max(1, ms))
        case .success(false):
            return .notTimeHuddle
        case let .failure(error):
            // A non-JSON reply decodes as "not TimeHuddle" inside ping; anything
            // else here is a transport failure.
            return .unreachable(error)
        }
    }
}
