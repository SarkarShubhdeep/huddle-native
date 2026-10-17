import Foundation
import Testing
@testable import HuddleKit

@Suite("ServerEndpoint")
struct ServerEndpointTests {
    @Test("A bare LAN IP becomes http on the backend port")
    func bareLANAddress() throws {
        let endpoint = try #require(ServerEndpoint("192.168.1.24"))
        #expect(endpoint.baseURL.absoluteString == "http://192.168.1.24:3100")
        #expect(endpoint.isLocalNetwork)
    }

    @Test("An explicit port is kept")
    func explicitPort() throws {
        let endpoint = try #require(ServerEndpoint("10.0.0.8:4000"))
        #expect(endpoint.baseURL.absoluteString == "http://10.0.0.8:4000")
    }

    @Test("A full URL loses its trailing slash, query and fragment")
    func fullURL() throws {
        let endpoint = try #require(ServerEndpoint("  http://172.20.1.5:3100/?x=1#top \n"))
        #expect(endpoint.baseURL.absoluteString == "http://172.20.1.5:3100")
    }

    @Test("A public host defaults to https and gets no port")
    func publicHost() throws {
        let endpoint = try #require(ServerEndpoint("timecore-dev.example.org"))
        #expect(endpoint.baseURL.absoluteString == "https://timecore-dev.example.org")
        #expect(!endpoint.isLocalNetwork)
    }

    @Test("mDNS and localhost count as local")
    func localNames() throws {
        #expect(try #require(ServerEndpoint("my-mac.local")).baseURL.absoluteString == "http://my-mac.local:3100")
        #expect(try #require(ServerEndpoint("localhost")).isLocalNetwork)
    }

    @Test("Garbage is rejected", arguments: ["", "   ", "ftp://192.168.1.2", "http://"])
    func rejects(_ input: String) {
        #expect(ServerEndpoint(input) == nil)
    }

    @Test("Only private IPv4 ranges are local", arguments: [
        ("10.1.2.3", true), ("172.16.0.1", true), ("172.31.255.255", true), ("172.32.0.1", false),
        ("192.168.0.1", true), ("169.254.1.1", true), ("8.8.8.8", false), ("192.169.0.1", false),
    ])
    func privateRanges(_ host: String, _ expected: Bool) {
        #expect(ServerEndpoint.isLocalHost(host) == expected)
    }
}
