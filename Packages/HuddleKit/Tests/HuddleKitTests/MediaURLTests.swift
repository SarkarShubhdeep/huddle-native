import Foundation
import Testing
@testable import HuddleKit

@Suite("MediaURL")
struct MediaURLTests {
    let endpoint = ServerEndpoint("192.168.1.24")!

    @Test("Backend media is re-based onto the current server", arguments: [
        ("/uploads/media/a.png", "http://192.168.1.24:3100/uploads/media/a.png"),
        ("http://10.0.0.9:3100/uploads/media/a.png", "http://192.168.1.24:3100/uploads/media/a.png"),
        ("https://old-host.example.org/pulsevault/artifacts/x?t=1", "http://192.168.1.24:3100/pulsevault/artifacts/x?t=1"),
    ])
    func rebases(raw: String, expected: String) {
        #expect(MediaURL.resolve(raw, against: endpoint)?.absoluteString == expected)
    }

    @Test("Links elsewhere are left alone")
    func external() {
        #expect(MediaURL.resolve("https://cdn.example.com/img.png", against: endpoint)?.absoluteString == "https://cdn.example.com/img.png")
        #expect(MediaURL.resolve(nil, against: endpoint) == nil)
        #expect(MediaURL.resolve("", against: endpoint) == nil)
    }

    @Test("Markdown images point at the current server")
    func markdown() {
        let text = "Before ![](http://10.0.0.9:3100/uploads/media/a.png) and ![x](/uploads/thumbnails/b.jpg), not [this](https://example.com/uploads/c)"
        let rebased = MediaURL.rebaseMarkdown(text, against: endpoint)
        #expect(rebased.contains("![](http://192.168.1.24:3100/uploads/media/a.png)"))
        #expect(rebased.contains("![x](http://192.168.1.24:3100/uploads/thumbnails/b.jpg)"))
        // Any host's /uploads/ path is treated as backend media, matching the web app.
        #expect(rebased.contains("[this](http://192.168.1.24:3100/uploads/c)"))
    }
}
