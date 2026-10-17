import HuddleKit
import Observation
import SwiftUI
import UIKit

/// Drives one rich text view: what's typed, which formats are on at the
/// cursor, and an `@` query in progress. Views read it; the toolbar and the
/// mention list call its actions.
@MainActor
@Observable
final class RichEditorController: NSObject, UITextViewDelegate {
    /// Formats that apply at the cursor, for the toolbar's selected states.
    private(set) var active: Set<ComposerFormat> = []
    /// The text after an `@` the cursor is in, or nil.
    private(set) var mentionQuery: String?
    private(set) var isEmpty = true
    /// Bumped on every edit, so views can react.
    private(set) var revision = 0

    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored private var initial: RichDocument

    init(_ document: RichDocument = RichDocument([RichBlock(.paragraph, [])])) {
        initial = document
    }

    var document: RichDocument {
        guard let textView else { return initial }
        return RichTextBridge.document(from: textView.attributedText)
    }

    /// The post as the backend stores it.
    var composed: ComposedText {
        let doc = document
        return ComposedText(markdown: RichMarkdown.markdown(from: doc), mentions: doc.mentionedUserIds, ticketId: doc.firstTicketId)
    }

    func attach(_ textView: UITextView) {
        self.textView = textView
        textView.attributedText = RichTextBridge.attributedString(from: initial)
        textView.typingAttributes = RichTextBridge.baseAttributes
        changed()
    }

    // MARK: Inline formats

    func apply(_ format: ComposerFormat) {
        // A tap on the toolbar must not take the keyboard away from the text.
        if textView?.isFirstResponder == false { textView?.becomeFirstResponder() }
        defer { if textView?.isFirstResponder == false { textView?.becomeFirstResponder() } }
        switch format {
        case .bold, .italic, .strikethrough: toggleInline(format)
        case .bulletList: toggleBlock("bullet")
        case .numberedList: toggleBlock("number")
        case .checklist: toggleBlock("check")
        case .mention: startMention()
        }
    }

    private func toggleInline(_ format: ComposerFormat) {
        guard let textView else { return }
        let range = textView.selectedRange
        let turnOn = !active.contains(format)
        if range.length == 0 {
            textView.typingAttributes = toggled(textView.typingAttributes, format, on: turnOn)
        } else {
            let text = NSMutableAttributedString(attributedString: textView.attributedText)
            text.enumerateAttributes(in: range) { attributes, sub, _ in
                guard attributes[.huddleMarker] == nil else { return }
                text.setAttributes(toggled(attributes, format, on: turnOn), range: sub)
            }
            replace(with: text, selection: range)
        }
        refreshState()
    }

    private func toggled(_ attributes: [NSAttributedString.Key: Any], _ format: ComposerFormat, on: Bool) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        var bold = traits.contains(.traitBold), italic = traits.contains(.traitItalic)
        switch format {
        case .bold: bold = on
        case .italic: italic = on
        case .strikethrough:
            attributes[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        default: break
        }
        attributes[.font] = RichTextBridge.font(bold: bold, italic: italic)
        return attributes
    }

    // MARK: Lists

    private func toggleBlock(_ kind: String) {
        guard let textView else { return }
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        var selection = textView.selectedRange
        let lines = lineStarts(in: text, covering: selection)
        // Turning a list off only when every selected line already is one.
        let allMatch = lines.allSatisfy { start in
            let current = RichTextBridge.markerKind(in: text, lineStart: start)
            return current == kind || (kind == "check" && current == "done")
        }
        for start in lines.reversed() {
            let markerRange = RichTextBridge.markerRange(in: text, lineStart: start)
            let replacement: NSAttributedString = allMatch
                ? NSAttributedString()
                : RichTextBridge.marker(for: RichTextBridge.blockKind(kind), number: 1) ?? NSAttributedString()
            text.replaceCharacters(in: markerRange, with: replacement)
            let delta = replacement.length - markerRange.length
            if start <= selection.location { selection.location = max(start + replacement.length, selection.location + delta) }
            else { selection.length += delta }
        }
        RichTextBridge.renumber(text)
        RichTextBridge.applyParagraphStyles(text)
        replace(with: text, selection: NSRange(location: min(selection.location, text.length), length: max(0, min(selection.length, text.length - selection.location))))
        refreshState()
    }

    private func lineStarts(in text: NSAttributedString, covering range: NSRange) -> [Int] {
        let ns = text.string as NSString
        guard ns.length > 0 else { return [0] }
        var starts: [Int] = []
        var location = range.location
        repeat {
            let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
            if starts.last != line.location { starts.append(line.location) }
            if NSMaxRange(line) <= location { break }
            location = NSMaxRange(line)
        } while location < NSMaxRange(range)
        // A cursor right after a final newline sits on a new, empty line.
        if range.location == ns.length, ns.hasSuffix("\n") { return [ns.length] }
        return starts
    }

    /// Taps on a checkbox tick it.
    func toggleCheck(at index: Int) {
        guard let textView else { return }
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        let ns = text.string as NSString
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        let range = RichTextBridge.markerRange(in: text, lineStart: line.location)
        guard range.length > 0, let kind = RichTextBridge.markerKind(in: text, lineStart: line.location),
              kind == "check" || kind == "done",
              index <= NSMaxRange(range) else { return }
        let marker = RichTextBridge.marker(for: .checklist(done: kind == "check"), number: 0)!
        text.replaceCharacters(in: range, with: marker)
        replace(with: text, selection: textView.selectedRange)
    }

    // MARK: Mentions

    private func startMention() {
        guard let textView else { return }
        let location = textView.selectedRange.location
        let ns = textView.attributedText.string as NSString
        let needsSpace = location > 0 && !CharacterSet.whitespacesAndNewlines.contains(ns.character(at: location - 1).scalar)
        textView.insertText(needsSpace ? " @" : "@")
    }

    /// Replaces the `@query` being typed with a mention.
    func insertMention(_ run: RichRun) {
        guard let textView, let range = mentionRange() else { return }
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        let mention = NSMutableAttributedString(attributedString: RichTextBridge.attributed(run))
        mention.append(NSAttributedString(string: " ", attributes: RichTextBridge.baseAttributes))
        text.replaceCharacters(in: range, with: mention)
        replace(with: text, selection: NSRange(location: range.location + mention.length, length: 0))
        textView.typingAttributes = RichTextBridge.baseAttributes
        if !textView.isFirstResponder { textView.becomeFirstResponder() }
        refreshState()
    }

    func cancelMention() {
        mentionQuery = nil
    }

    /// The `@...` the cursor is at the end of, when it's a fresh mention.
    private func mentionRange() -> NSRange? {
        guard let textView, textView.selectedRange.length == 0 else { return nil }
        let text = textView.attributedText!
        let ns = text.string as NSString
        let cursor = textView.selectedRange.location
        var i = cursor - 1
        while i >= 0, cursor - i <= 32 {
            let ch = ns.character(at: i)
            if ch == 10 { return nil } // newline
            if ch == 64 { // "@"
                let before = i > 0 ? ns.character(at: i - 1) : 32
                guard CharacterSet.whitespacesAndNewlines.contains(before.scalar),
                      text.attribute(.huddleMention, at: i, effectiveRange: nil) == nil else { return nil }
                return NSRange(location: i, length: cursor - i)
            }
            i -= 1
        }
        return nil
    }

    /// Typing attributes with marker and mention styling removed; bold, italic
    /// and strikethrough carry on.
    static func plainTyping(from typing: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var plain = RichTextBridge.baseAttributes
        let traits = (typing[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        let wasMention = typing[.huddleMention] != nil
        plain[.font] = RichTextBridge.font(bold: traits.contains(.traitBold) && !wasMention, italic: traits.contains(.traitItalic))
        if let strike = typing[.strikethroughStyle] { plain[.strikethroughStyle] = strike }
        return plain
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
        let text = textView.attributedText!
        let ns = text.string as NSString
        let line = ns.lineRange(for: NSRange(location: min(range.location, ns.length), length: 0))
        let lineStart = range.location == ns.length && ns.hasSuffix("\n") ? ns.length : line.location
        let marker = RichTextBridge.markerRange(in: text, lineStart: lineStart)
        let kind = RichTextBridge.markerKind(in: text, lineStart: lineStart)

        // Return in a list: continue it, or leave it from an empty item.
        if string == "\n", let kind, range.length == 0 {
            let content = ns.substring(with: NSRange(location: NSMaxRange(marker), length: NSMaxRange(line) - NSMaxRange(marker)))
            let mutable = NSMutableAttributedString(attributedString: text)
            if content.trimmingCharacters(in: .newlines).isEmpty {
                mutable.replaceCharacters(in: marker, with: "")
                RichTextBridge.renumber(mutable)
                RichTextBridge.applyParagraphStyles(mutable)
                replace(with: mutable, selection: NSRange(location: marker.location, length: 0))
            } else {
                let next = NSMutableAttributedString(string: "\n", attributes: RichTextBridge.baseAttributes)
                next.append(RichTextBridge.marker(for: RichTextBridge.blockKind(kind == "done" ? "check" : kind), number: 1)!)
                mutable.replaceCharacters(in: range, with: next)
                RichTextBridge.renumber(mutable)
                RichTextBridge.applyParagraphStyles(mutable)
                replace(with: mutable, selection: NSRange(location: range.location + next.length, length: 0))
            }
            refreshState()
            return false
        }
        // Backspace into a marker removes the whole marker.
        if string.isEmpty, marker.length > 0, range.length <= 1, NSLocationInRange(range.location, marker) {
            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.replaceCharacters(in: marker, with: "")
            RichTextBridge.renumber(mutable)
            RichTextBridge.applyParagraphStyles(mutable)
            replace(with: mutable, selection: NSRange(location: marker.location, length: 0))
            refreshState()
            return false
        }
        // Never type into a marker or a mention: new text gets plain attributes.
        // Only touch typing attributes when needed; resetting them on every
        // keystroke disturbs the text input system and drops characters.
        if !string.isEmpty {
            let typing = textView.typingAttributes
            let afterMarker = range.location > 0 && range.location <= text.length
                && text.attribute(.huddleMarker, at: range.location - 1, effectiveRange: nil) != nil
            if afterMarker || typing[.huddleMarker] != nil || typing[.huddleMention] != nil {
                textView.typingAttributes = Self.plainTyping(from: typing)
            }
            if marker.length > 0, range.location < NSMaxRange(marker), range.location >= marker.location {
                textView.selectedRange = NSRange(location: NSMaxRange(marker), length: 0)
                textView.insertText(string)
                return false
            }
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        changed()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // Keep the cursor out of list markers.
        let text = textView.attributedText!
        let range = textView.selectedRange
        if range.length == 0, range.location < text.length,
           let _ = text.attribute(.huddleMarker, at: range.location, effectiveRange: nil) {
            let ns = text.string as NSString
            let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let marker = RichTextBridge.markerRange(in: text, lineStart: line.location)
            if range.location > marker.location || marker.location == line.location {
                textView.selectedRange = NSRange(location: NSMaxRange(marker), length: 0)
                return
            }
        }
        refreshState()
    }

    // MARK: State

    private func replace(with text: NSAttributedString, selection: NSRange) {
        guard let textView else { return }
        textView.attributedText = text
        textView.selectedRange = selection
        changed()
    }

    private func changed() {
        revision += 1
        isEmpty = document.isEmpty
        refreshState()
    }

    private func refreshState() {
        guard let textView else { return }
        let text = textView.attributedText!
        var formats: Set<ComposerFormat> = []
        let attributes: [NSAttributedString.Key: Any]
        if textView.selectedRange.length > 0 {
            attributes = text.attributes(at: textView.selectedRange.location, effectiveRange: nil)
        } else {
            attributes = textView.typingAttributes
        }
        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        if traits.contains(.traitBold), attributes[.huddleMention] == nil { formats.insert(.bold) }
        if traits.contains(.traitItalic) { formats.insert(.italic) }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { formats.insert(.strikethrough) }

        let ns = text.string as NSString
        let location = min(textView.selectedRange.location, ns.length)
        let lineStart = location == ns.length && (ns.length == 0 || ns.hasSuffix("\n"))
            ? ns.length : ns.lineRange(for: NSRange(location: min(location, max(0, ns.length - 1)), length: 0)).location
        switch RichTextBridge.markerKind(in: text, lineStart: lineStart) {
        case "bullet": formats.insert(.bulletList)
        case "number": formats.insert(.numberedList)
        case "check", "done": formats.insert(.checklist)
        default: break
        }

        if let range = mentionRange() {
            mentionQuery = String(ns.substring(with: range).dropFirst())
            formats.insert(.mention)
        } else {
            mentionQuery = nil
        }
        if active != formats { active = formats }
    }
}

/// The post text in the shape the backend wants.
struct ComposedText: Equatable, Sendable {
    var markdown: String
    var mentions: [String]
    var ticketId: String?

    var isEmpty: Bool { markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private extension unichar {
    var scalar: Unicode.Scalar { Unicode.Scalar(self) ?? " " }
}

// MARK: - SwiftUI

/// The editable text area. Grows with the sheet; scrolls when long.
struct RichTextEditor: UIViewRepresentable {
    let controller: RichEditorController
    var placeholder: String = ""
    var autofocus = false

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.allowsEditingTextAttributes = true
        view.tintColor = UIColor(Palette.limeText)
        view.delegate = controller
        view.accessibilityLabel = placeholder
        controller.attach(view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        if autofocus { DispatchQueue.main.async { view.becomeFirstResponder() } }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let controller: RichEditorController
        init(controller: RichEditorController) { self.controller = controller }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let position = view.closestPosition(to: gesture.location(in: view)) else { return }
            let index = view.offset(from: view.beginningOfDocument, to: position)
            let text = view.attributedText!
            // The tap lands on either side of the box glyph.
            for candidate in [index, index - 1] where candidate >= 0 && candidate < text.length {
                if let kind = text.attribute(.huddleMarker, at: candidate, effectiveRange: nil) as? String,
                   kind == "check" || kind == "done" {
                    controller.toggleCheck(at: candidate)
                    return
                }
            }
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
