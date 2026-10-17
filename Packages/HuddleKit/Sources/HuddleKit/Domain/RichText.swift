import Foundation

/// The composer's document, independent of any UI: lines of styled runs.
/// It converts to and from the markdown the web app renders (GitHub
/// flavor): `**bold**`, `*italic*`, `~~strike~~`, `- ` bullets, `1. `
/// numbers and `- [ ]` / `- [x]` checklists.
public struct RichDocument: Equatable, Sendable {
    public var blocks: [RichBlock]

    public init(_ blocks: [RichBlock] = []) { self.blocks = blocks }

    public var isEmpty: Bool { blocks.allSatisfy { $0.plainText.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Everyone @mentioned, in order, without repeats.
    public var mentionedUserIds: [String] {
        var seen = Set<String>()
        return blocks.flatMap(\.runs).compactMap { run in
            guard case let .person(id)? = run.mention, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    /// The first ticket mentioned; it becomes the post's `ticketId`.
    public var firstTicketId: String? {
        blocks.flatMap(\.runs).lazy.compactMap { run -> String? in
            if case let .ticket(id)? = run.mention { return id }
            return nil
        }.first
    }
}

public struct RichBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph
        case bullet
        case numbered
        case checklist(done: Bool)
    }

    public var kind: Kind
    public var runs: [RichRun]

    public init(_ kind: Kind = .paragraph, _ runs: [RichRun]) {
        self.kind = kind
        self.runs = runs
    }

    public var plainText: String { runs.map(\.text).joined() }
}

public struct RichRun: Equatable, Sendable {
    public enum Mention: Equatable, Sendable {
        case person(userId: String)
        case ticket(ticketId: String)
    }

    public var text: String
    public var bold = false
    public var italic = false
    public var strike = false
    public var mention: Mention?
    /// A markdown link's target, kept so posts written elsewhere round-trip.
    public var link: String?

    public init(_ text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false, mention: Mention? = nil, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.mention = mention
        self.link = link
    }

    fileprivate var style: [Bool] { [bold, italic, strike] }
}

// MARK: - Markdown

public enum RichMarkdown {
    /// Markdown for `document`. Person mentions are written `@Firstname`
    /// (the web app's mention token); ticket mentions as the ticket's title.
    public static func markdown(from document: RichDocument) -> String {
        var number = 0
        return document.blocks.map { block in
            if block.kind == .numbered { number += 1 } else { number = 0 }
            let prefix: String = switch block.kind {
            case .paragraph: ""
            case .bullet: "- "
            case .numbered: "\(number). "
            case let .checklist(done): done ? "- [x] " : "- [ ] "
            }
            // Trailing spaces mean nothing in markdown (and two would make a line break).
            let line = prefix + inline(merged(block.runs))
            return String(line.reversed().drop { $0 == " " }.reversed())
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .newlines)
    }

    /// Reads markdown back into a document. `people` maps a mention token's
    /// lowercase first name to its user id, so `@sam` becomes a mention again
    /// (names two teammates share stay plain text, as on the web).
    public static func document(from markdown: String, people: [String: String] = [:]) -> RichDocument {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let blocks = lines.map { line -> RichBlock in
            let (kind, rest) = blockKind(of: line)
            return RichBlock(kind, parseInline(rest, people: people))
        }
        // Drop trailing empty lines so a round trip doesn't grow the post.
        var trimmed = blocks
        while let last = trimmed.last, last.kind == .paragraph, last.plainText.isEmpty, trimmed.count > 1 { trimmed.removeLast() }
        return RichDocument(trimmed)
    }

    // MARK: Writing

    /// Joins neighbouring runs with the same style so `**a****b**` never appears.
    private static func merged(_ runs: [RichRun]) -> [RichRun] {
        var out: [RichRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = out.last, last.style == run.style, last.mention == nil, run.mention == nil,
               last.link == run.link {
                out[out.count - 1].text += run.text
            } else {
                out.append(run)
            }
        }
        return out
    }

    private static func inline(_ runs: [RichRun]) -> String {
        runs.map { run in
            var text = run.mention == nil ? escape(run.text) : mentionText(run)
            if let link = run.link { text = "[\(text)](\(link))" }
            // Markers can't wrap surrounding spaces in markdown, so keep them outside.
            let leading = text.prefix { $0 == " " }
            let trailing = String(text.reversed().prefix { $0 == " " })
            let core = text.dropFirst(leading.count).dropLast(trailing.count)
            guard !core.isEmpty else { return text }
            text = String(core)
            if run.strike { text = "~~\(text)~~" }
            if run.italic { text = "*\(text)*" }
            if run.bold { text = "**\(text)**" }
            return leading + text + trailing
        }
        .joined()
    }

    private static func mentionText(_ run: RichRun) -> String {
        switch run.mention {
        case .person?:
            // `@` plus the first word of the name, as the web app expects.
            let name = run.text.hasPrefix("@") ? String(run.text.dropFirst()) : run.text
            return "@" + (name.split(separator: " ").first.map(String.init) ?? name)
        case .ticket?, nil:
            return escape(run.text)
        }
    }

    /// Backslash-escapes characters that would otherwise start formatting.
    private static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if "*_~`\\[".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    // MARK: Reading

    private static func blockKind(of line: String) -> (RichBlock.Kind, String) {
        let body = line.drop { $0 == " " }
        for (marker, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)] {
            if body.hasPrefix(marker) { return (.checklist(done: done), String(body.dropFirst(marker.count))) }
        }
        if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
            return (.bullet, String(body.dropFirst(2)))
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, String(body.dropFirst(digits.count + 2)))
        }
        return (.paragraph, line)
    }

    private static func parseInline(_ text: String, people: [String: String]) -> [RichRun] {
        var runs: [RichRun] = []
        var bold = false, italic = false, strike = false
        var buffer = ""
        let chars = Array(text)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(contentsOf: splitMentions(buffer, bold: bold, italic: italic, strike: strike, people: people))
            buffer = ""
        }
        func closes(_ marker: String, from index: Int) -> Bool {
            // Only treat a marker as formatting when it's closed later on the line.
            let rest = String(chars[index...])
            return rest.range(of: marker) != nil
        }

        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "\\", let next, "*_~`\\[".contains(next) {
                buffer.append(next); i += 2; continue
            }
            if c == "[", let (label, target, length) = link(in: chars, at: i) {
                flush()
                for var run in parseInline(label, people: [:]) {
                    run.bold = run.bold || bold
                    run.italic = run.italic || italic
                    run.strike = run.strike || strike
                    run.link = target
                    runs.append(run)
                }
                i += length
                continue
            }
            if (c == "*" || c == "_"), next == c {
                if bold || closes(String([c, c]), from: i + 2) { flush(); bold.toggle(); i += 2; continue }
            } else if c == "~", next == "~" {
                if strike || closes("~~", from: i + 2) { flush(); strike.toggle(); i += 2; continue }
            } else if c == "*" || c == "_" {
                let opensWord = !italic && next.map { !$0.isWhitespace } == true
                if (italic || (opensWord && closes(String(c), from: i + 1))) {
                    flush(); italic.toggle(); i += 1; continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return runs
    }

    /// `[label](target)` starting at `index`: the label, the target and how many characters it spans.
    private static func link(in chars: [Character], at index: Int) -> (String, String, Int)? {
        var depth = 0
        var i = index
        while i < chars.count {
            if chars[i] == "[" { depth += 1 }
            if chars[i] == "]" { depth -= 1; if depth == 0 { break } }
            i += 1
        }
        guard i + 1 < chars.count, chars[i] == "]", chars[i + 1] == "(" else { return nil }
        guard let close = chars[(i + 2)...].firstIndex(of: ")") else { return nil }
        let label = String(chars[(index + 1)..<i])
        let target = String(chars[(i + 2)..<close])
        guard !target.contains(" "), !label.isEmpty else { return nil }
        return (label, target, close - index + 1)
    }

    /// Splits `@name` tokens that match a teammate into mention runs.
    private static func splitMentions(_ text: String, bold: Bool, italic: Bool, strike: Bool, people: [String: String]) -> [RichRun] {
        guard !people.isEmpty, text.contains("@") else {
            return [RichRun(text, bold: bold, italic: italic, strike: strike)]
        }
        var runs: [RichRun] = []
        var plain = ""
        var rest = Substring(text)
        while let at = rest.firstIndex(of: "@") {
            let before = rest[..<at]
            let afterAt = rest[rest.index(after: at)...]
            let name = afterAt.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "'" }
            let precededByWord = before.last.map { $0.isLetter || $0.isNumber || $0 == "@" } ?? false
            if !name.isEmpty, !precededByWord, let id = people[name.lowercased()] {
                plain += before
                if !plain.isEmpty { runs.append(RichRun(plain, bold: bold, italic: italic, strike: strike)); plain = "" }
                runs.append(RichRun("@" + name, bold: bold, italic: italic, strike: strike, mention: .person(userId: id)))
                rest = afterAt.dropFirst(name.count)
            } else {
                plain += rest[...at]
                rest = afterAt
            }
        }
        plain += rest
        if !plain.isEmpty { runs.append(RichRun(plain, bold: bold, italic: italic, strike: strike)) }
        return runs
    }

    /// Mention tokens for a roster: lowercase first name → user id, leaving
    /// out first names two people share (the web app can't tell them apart).
    public static func mentionTokens(_ members: [(id: String, name: String)]) -> [String: String] {
        var counts: [String: Int] = [:]
        var ids: [String: String] = [:]
        for member in members {
            let token = member.name.split(separator: " ").first.map { $0.lowercased() } ?? ""
            guard !token.isEmpty else { continue }
            counts[token, default: 0] += 1
            ids[token] = member.id
        }
        return ids.filter { counts[$0.key] == 1 }
    }
}
