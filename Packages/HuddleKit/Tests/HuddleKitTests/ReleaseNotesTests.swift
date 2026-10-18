import Foundation
import Testing
@testable import HuddleKit

@Suite("ReleaseNotes")
struct ReleaseNotesTests {
    private func v(_ text: String) -> SemanticVersion { SemanticVersion(text)! }

    private func note(_ version: String, title: String = "T") -> ReleaseNote {
        ReleaseNote.parse("---\nversion: \(version)\ntitle: \(title)\n---\nBody", filename: "\(version).md")!
    }

    @Test("Versions compare part by part, and trailing zeros don't matter")
    func versions() {
        #expect(v("0.10.0") > v("0.9.0"))
        #expect(v("1.0") == v("1.0.0"))
        #expect(v("0.9.1") > v("0.9"))
        #expect(v("0.9").description == "0.9.0")
        #expect(SemanticVersion("1.x") == nil)
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("1..2") == nil)
    }

    @Test("Front matter and body are read; quotes and CRLF are fine")
    func parses() throws {
        let text = "---\r\nversion: 0.3.0\r\ndate: 2026-10-17\r\ntitle: \"Your day on one screen\"\r\nchannel: pre-beta\r\n---\r\n\r\nHello **there**.\r\n"
        let note = try #require(ReleaseNote.parse(text, filename: "0.3.0.md"))
        #expect(note.version == v("0.3.0"))
        #expect(note.date == "2026-10-17")
        #expect(note.title == "Your day on one screen")
        #expect(note.channel == "pre-beta")
        #expect(note.body == "Hello **there**.")
    }

    @Test("A note whose version doesn't match its filename is dropped")
    func versionMustMatchFilename() {
        #expect(ReleaseNote.parse("---\nversion: 0.3.0\ntitle: T\n---\n", filename: "0.4.0.md") == nil)
        #expect(ReleaseNote.parse("---\nversion: 0.3\ntitle: T\n---\n", filename: "0.3.0.md") != nil)
    }

    @Test("Files that aren't notes are ignored")
    func notNotes() {
        #expect(ReleaseNote.parse("# Release notes", filename: "README.md") == nil)
        #expect(ReleaseNote.parse("---\nversion: 0.3.0\ntitle: T\n---\n", filename: "0.3.0.txt") == nil)
        #expect(ReleaseNote.parse("---\nversion: 0.3.0\n---\n", filename: "0.3.0.md") == nil) // no title
        #expect(ReleaseNote.parse("version: 0.3.0\ntitle: T\n", filename: "0.3.0.md") == nil) // no front matter
    }

    @Test("The body splits into headings, text, pictures and clips")
    func blocks() {
        let body = """
        Intro line.

        ## Start your day
        - One tap
        - Live timer

        ![The Now screen](assets/0.3.0/now.png)
        ![Taking a break](assets/0.3.0/break.mp4)
        ### Details
        More text with an inline ![icon](x.png) stays text.
        """
        #expect(ReleaseNoteBlock.parse(body) == [
            .text("Intro line."),
            .heading("Start your day", level: 2),
            .text("- One tap\n- Live timer"),
            .image(path: "assets/0.3.0/now.png", caption: "The Now screen"),
            .video(path: "assets/0.3.0/break.mp4", caption: "Taking a break"),
            .heading("Details", level: 3),
            .text("More text with an inline ![icon](x.png) stays text."),
        ])
    }

    @Test("Only notes up to the installed version show, newest first")
    func visible() {
        let notes = ["0.1.0", "0.10.0", "0.9.0", "0.2.0"].map { note($0) }
        #expect(ReleaseNoteCatalog.visible(notes, appVersion: v("0.9.0")).map(\.id) == ["0.9.0", "0.2.0", "0.1.0"])
    }

    @Test("Announce the newest unseen note; never on a fresh install")
    func announcement() {
        let notes = ["0.1.0", "0.2.0", "0.3.0"].map { note($0) }
        #expect(ReleaseNoteCatalog.announcement(notes, appVersion: v("0.3.0"), seen: nil) == nil)
        #expect(ReleaseNoteCatalog.announcement(notes, appVersion: v("0.3.0"), seen: v("0.3.0")) == nil)
        #expect(ReleaseNoteCatalog.announcement(notes, appVersion: v("0.3.0"), seen: v("0.1.0"))?.id == "0.3.0")
        #expect(ReleaseNoteCatalog.unread(notes, appVersion: v("0.3.0"), seen: v("0.1.0")) == ["0.2.0", "0.3.0"])
        #expect(ReleaseNoteCatalog.unread(notes, appVersion: v("0.3.0"), seen: nil).isEmpty)
    }

    @Test("Every note in ReleaseNotes/ parses, and its pictures and clips exist")
    func shippedNotes() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HuddleKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // HuddleKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("ReleaseNotes")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") && $0 != "README.md" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            let note = try #require(ReleaseNote.parse(text, filename: file), "\(file) doesn't parse")
            for block in note.blocks {
                switch block {
                case let .image(path, _), let .video(path, _):
                    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "\(file): missing \(path)")
                default: break
                }
            }
        }
    }
}
