import Foundation

/// A version like `0.9.0`, compared part by part (so `0.10.0` is after `0.9.0`).
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        guard !pieces.isEmpty, pieces.count <= 4, numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        // 0.9 and 0.9.0 are the same version.
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        parts = trimmed
    }

    public var description: String {
        (parts + Array(repeating: 0, count: max(0, 3 - parts.count))).map(String.init).joined(separator: ".")
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

/// One release note: a markdown file with front matter, named after its version.
///
/// ```
/// ---
/// version: 0.3.0
/// date: 2026-10-17
/// title: Your day on one screen
/// channel: pre-beta
/// ---
/// Body in markdown…
/// ```
public struct ReleaseNote: Identifiable, Hashable, Sendable {
    public let version: SemanticVersion
    public let date: String
    public let title: String
    /// `pre-beta` for now; later `beta` or `release`.
    public let channel: String
    public let body: String

    public var id: String { version.description }

    /// Parses `text`, the contents of the file named `filename`. Returns nil when
    /// the front matter is missing or incomplete, or when its `version` doesn't
    /// match the filename (so a copied file can't show up under the wrong version).
    public static func parse(_ text: String, filename: String) -> ReleaseNote? {
        let name = (filename as NSString).deletingPathExtension
        guard (filename as NSString).pathExtension == "md", let fileVersion = SemanticVersion(name) else { return nil }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }

        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" { value = String(value.dropFirst().dropLast()) }
            fields[key] = value
        }
        guard let versionText = fields["version"], let version = SemanticVersion(versionText), version == fileVersion,
              let title = fields["title"], !title.isEmpty
        else { return nil }

        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseNote(version: version, date: fields["date"] ?? "", title: title,
                           channel: fields["channel"] ?? "pre-beta", body: body)
    }

    /// The note's body as blocks to render.
    public var blocks: [ReleaseNoteBlock] { ReleaseNoteBlock.parse(body) }
}

/// A piece of a note: markdown text, a heading, or a picture or clip on its own line.
public enum ReleaseNoteBlock: Hashable, Sendable {
    /// `## Heading` (level 2) or `### Heading` (level 3).
    case heading(String, level: Int)
    /// Paragraphs and lists, as markdown for `RichMarkdown`.
    case text(String)
    /// `![caption](assets/0.3.0/now.png)` on a line of its own.
    case image(path: String, caption: String)
    /// The same syntax pointing at `.mp4` or `.mov`: a short looping clip.
    case video(path: String, caption: String)

    public static func parse(_ markdown: String) -> [ReleaseNoteBlock] {
        var blocks: [ReleaseNoteBlock] = []
        var text: [String] = []

        func flush() {
            let joined = text.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.text(joined)) }
            text = []
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
            } else if let media = media(trimmed) {
                flush()
                blocks.append(media)
            } else {
                text.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> ReleaseNoteBlock? {
        for (prefix, level) in [("### ", 3), ("## ", 2), ("# ", 2)] where line.hasPrefix(prefix) {
            let title = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : .heading(title, level: level)
        }
        return nil
    }

    private static func media(_ line: String) -> ReleaseNoteBlock? {
        guard let match = line.wholeMatch(of: /!\[([^\]]*)\]\(([^)\s]+)\)/) else { return nil }
        let caption = String(match.output.1), path = String(match.output.2)
        let ext = (path as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext) ? .video(path: path, caption: caption) : .image(path: path, caption: caption)
    }
}

/// Which notes to show and whether to announce one, given what's installed
/// and what this person has already seen. Nothing here touches the server:
/// the seen version lives on the device.
public enum ReleaseNoteCatalog {
    /// Notes for this build and earlier, newest first. Notes written ahead of
    /// a release (a higher version than the app) stay hidden until it ships.
    public static func visible(_ notes: [ReleaseNote], appVersion: SemanticVersion) -> [ReleaseNote] {
        notes.filter { $0.version <= appVersion }.sorted { $0.version > $1.version }
    }

    /// The note to announce with "Huddle got updated", if any.
    ///
    /// - `seen` nil means a fresh install: nothing is new to someone who just
    ///   installed, so there's nothing to announce (the caller then records the
    ///   current version as seen).
    public static func announcement(_ notes: [ReleaseNote], appVersion: SemanticVersion, seen: SemanticVersion?) -> ReleaseNote? {
        guard let seen else { return nil }
        return visible(notes, appVersion: appVersion).first { $0.version > seen }
    }

    /// Notes newer than `seen`, for unread markers.
    public static func unread(_ notes: [ReleaseNote], appVersion: SemanticVersion, seen: SemanticVersion?) -> Set<String> {
        guard let seen else { return [] }
        return Set(visible(notes, appVersion: appVersion).filter { $0.version > seen }.map(\.id))
    }
}
