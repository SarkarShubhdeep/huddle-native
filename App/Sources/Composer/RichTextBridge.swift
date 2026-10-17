import HuddleKit
import UIKit

extension NSAttributedString.Key {
    /// A list marker at the start of a line: "bullet", "number", "check" or "done".
    static let huddleMarker = NSAttributedString.Key("huddle.marker")
    /// A mention: "p:<userId>" or "t:<ticketId>".
    static let huddleMention = NSAttributedString.Key("huddle.mention")
}

/// Converts between the composer's `RichDocument` and the attributed text in
/// the `UITextView`. Each line is a block; a list line starts with a marker
/// (tagged `.huddleMarker`) that is drawn but never saved as text.
@MainActor
enum RichTextBridge {
    static var bodyFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: UIColor(Palette.textPrimary)]
    }

    // MARK: Document → text

    static func attributedString(from document: RichDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var number = 0
        for (index, block) in document.blocks.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n", attributes: baseAttributes)) }
            if block.kind == .numbered { number += 1 } else { number = 0 }
            if let marker = marker(for: block.kind, number: number) { out.append(marker) }
            for run in block.runs { out.append(attributed(run)) }
        }
        applyParagraphStyles(out)
        return out
    }

    static func attributed(_ run: RichRun) -> NSAttributedString {
        var attributes = baseAttributes
        attributes[.font] = font(bold: run.bold || run.mention != nil, italic: run.italic)
        if run.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        switch run.mention {
        case let .person(id)?:
            attributes[.huddleMention] = "p:\(id)"
            attributes[.foregroundColor] = UIColor(Palette.limeText)
        case let .ticket(id)?:
            attributes[.huddleMention] = "t:\(id)"
            attributes[.foregroundColor] = UIColor(Palette.limeText)
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case nil:
            break
        }
        return NSAttributedString(string: run.text, attributes: attributes)
    }

    static func marker(for kind: RichBlock.Kind, number: Int) -> NSAttributedString? {
        var attributes = baseAttributes
        let text: String
        switch kind {
        case .paragraph: return nil
        case .bullet:
            text = "•\t"
            attributes[.huddleMarker] = "bullet"
        case .numbered:
            text = "\(max(1, number)).\t"
            attributes[.huddleMarker] = "number"
            attributes[.font] = UIFont.monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
        case let .checklist(done):
            text = (done ? "☑" : "☐") + "\t"
            attributes[.huddleMarker] = done ? "done" : "check"
            attributes[.foregroundColor] = UIColor(done ? Palette.limeText : Palette.textSecondary)
        }
        attributes[.foregroundColor] = attributes[.foregroundColor] ?? UIColor(Palette.textSecondary)
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func font(bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty, let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(traits) else { return bodyFont }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// List lines hang their text past the marker.
    static func applyParagraphStyles(_ text: NSMutableAttributedString) {
        let ns = text.string as NSString
        var start = 0
        while start < ns.length {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 4
            if markerKind(in: text, lineStart: line.location) != nil {
                let indent: CGFloat = 26
                style.headIndent = indent
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                style.defaultTabInterval = indent
            }
            text.addAttribute(.paragraphStyle, value: style, range: line)
            start = NSMaxRange(line) // always > start: a line holds at least one character here
        }
    }

    // MARK: Text → document

    static func document(from text: NSAttributedString) -> RichDocument {
        let ns = text.string as NSString
        var blocks: [RichBlock] = []
        var start = 0
        repeat {
            let lineEnd = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start)).location
            let end = lineEnd == NSNotFound ? ns.length : lineEnd
            blocks.append(block(in: text, range: NSRange(location: start, length: end - start)))
            start = end + 1
        } while start <= ns.length
        return RichDocument(blocks)
    }

    private static func block(in text: NSAttributedString, range: NSRange) -> RichBlock {
        var kind = RichBlock.Kind.paragraph
        var runs: [RichRun] = []
        text.enumerateAttributes(in: range) { attributes, sub, _ in
            if let marker = attributes[.huddleMarker] as? String {
                kind = blockKind(marker)
                return
            }
            let string = (text.string as NSString).substring(with: sub)
            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let mention = (attributes[.huddleMention] as? String).flatMap(Self.mention)
            runs.append(RichRun(
                string,
                bold: traits.contains(.traitBold) && mention == nil,
                italic: traits.contains(.traitItalic),
                strike: (attributes[.strikethroughStyle] as? Int ?? 0) != 0,
                mention: mention
            ))
        }
        return RichBlock(kind, runs)
    }

    static func blockKind(_ marker: String) -> RichBlock.Kind {
        switch marker {
        case "number": .numbered
        case "check": .checklist(done: false)
        case "done": .checklist(done: true)
        default: .bullet
        }
    }

    static func mention(_ value: String) -> RichRun.Mention? {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return parts[0] == "p" ? .person(userId: parts[1]) : .ticket(ticketId: parts[1])
    }

    // MARK: Lines

    /// The marker kind of the line starting at `lineStart`, if it has one.
    static func markerKind(in text: NSAttributedString, lineStart: Int) -> String? {
        guard lineStart < text.length else { return nil }
        return text.attribute(.huddleMarker, at: lineStart, effectiveRange: nil) as? String
    }

    /// The marker's range on the line starting at `lineStart` (empty when none).
    static func markerRange(in text: NSAttributedString, lineStart: Int) -> NSRange {
        guard lineStart < text.length,
              text.attribute(.huddleMarker, at: lineStart, effectiveRange: nil) != nil else {
            return NSRange(location: lineStart, length: 0)
        }
        var range = NSRange()
        _ = text.attribute(.huddleMarker, at: lineStart, longestEffectiveRange: &range,
                           in: NSRange(location: lineStart, length: text.length - lineStart))
        return range
    }

    /// Rewrites numbered markers so each run of numbered lines counts from 1.
    static func renumber(_ text: NSMutableAttributedString) {
        var number = 0
        var start = 0
        while start < text.length {
            let ns = text.string as NSString
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            if markerKind(in: text, lineStart: line.location) == "number" {
                number += 1
                let range = markerRange(in: text, lineStart: line.location)
                let label = "\(number).\t"
                if ns.substring(with: range) != label {
                    let attributes = text.attributes(at: range.location, effectiveRange: nil)
                    text.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attributes))
                }
                // Continue after this line in the updated text.
                start = NSMaxRange((text.string as NSString).lineRange(for: NSRange(location: line.location, length: 0)))
            } else {
                number = 0
                start = NSMaxRange(line)
            }
        }
    }
}
