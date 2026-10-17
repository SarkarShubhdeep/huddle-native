import HuddleKit
import SwiftUI

/// A Huddle post, edge to edge: who and when, a Plan or Wrap-up badge, the
/// text, a linked ticket, an image, and counts.
struct PostRow: View {
    let authorName: String
    let authorInitials: String
    var isMe = false
    /// "9:01 AM · shift 9:02 AM – now", "Yesterday · 5:40 PM".
    let meta: String
    var kind: HuddlePost.Kind = .post
    /// The post's markdown, as the web app stores it.
    let markdown: String
    var ticketTitle: String?
    var imageURL: URL?
    /// Lowercase first name → user id, so @mentions in the text show as mentions.
    var people: [String: String] = [:]
    var likeCount = 0
    var commentCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PostBody(markdown: markdown, people: people)
            if let ticketTitle {
                Label(ticketTitle, systemImage: "list.bullet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Ticket: \(ticketTitle)")
            }
            if let imageURL {
                PostImage(url: imageURL)
            }
            if likeCount > 0 || commentCount > 0 {
                HStack(spacing: 18) {
                    if likeCount > 0 { Text(likeCount == 1 ? "1 like" : "\(likeCount) likes") }
                    if commentCount > 0 { Text(commentCount == 1 ? "1 comment" : "\(commentCount) comments") }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, Spacing.l)
        .padding(.horizontal, Spacing.xl)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(initials: authorInitials, isMe: isMe)
            VStack(alignment: .leading, spacing: 0) {
                Text(isMe ? "You" : authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch kind {
            case .plan: StatusChip(label: "Plan", tone: .working, style: .badge)
            case .wrapUp: StatusChip(label: "Wrap-up", tone: .done, style: .badge)
            case .post: EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A post's markdown as styled lines: paragraphs, bullets, numbers and
/// checklists, with bold, italic, strikethrough and @mentions, plus any
/// images written into the text.
struct PostBody: View {
    let markdown: String
    var people: [String: String] = [:]

    var body: some View {
        let (text, images) = Self.splitImages(markdown)
        let document = RichMarkdown.document(from: text, people: people)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { index, block in
                line(block, number: number(at: index, in: document))
            }
            ForEach(images, id: \.self) { url in
                PostImage(url: url)
            }
        }
        .font(.body)
        .foregroundStyle(Palette.textPrimary)
        .tint(Palette.limeText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func line(_ block: RichBlock, number: Int) -> some View {
        let text = Text(attributed(block.runs))
        switch block.kind {
        case .paragraph:
            if block.plainText.isEmpty { Color.clear.frame(height: 4) } else { text }
        case .bullet:
            marker(Text("•").foregroundStyle(Palette.textSecondary), text)
        case .numbered:
            marker(Text("\(number).").monospacedDigit().foregroundStyle(Palette.textSecondary), text)
        case let .checklist(done):
            marker(Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Palette.limeText : Palette.textSecondary)
                    .accessibilityLabel(done ? "Done" : "To do"),
                   done ? text.strikethrough().foregroundStyle(Palette.textSecondary) : text)
        }
    }

    private func marker(_ marker: some View, _ text: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            marker.frame(minWidth: 18, alignment: .leading)
            text
        }
    }

    private func number(at index: Int, in document: RichDocument) -> Int {
        var n = 0
        for i in stride(from: index, through: 0, by: -1) {
            guard document.blocks[i].kind == .numbered else { break }
            n += 1
        }
        return n
    }

    private func attributed(_ runs: [RichRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var font = Font.body
            if run.bold || run.mention != nil { font = font.weight(.semibold) }
            if run.italic { font = font.italic() }
            piece.font = font
            if run.strike { piece.strikethroughStyle = .single }
            if run.mention != nil || run.link != nil { piece.foregroundColor = Palette.limeText }
            // Full URLs open; the web app's own paths (/app/...) mean nothing here.
            if let link = run.link, link.hasPrefix("http"), let url = URL(string: link) { piece.link = url }
            out += piece
        }
        return out
    }

    /// Pulls `![alt](url)` images out of the text.
    static func splitImages(_ markdown: String) -> (String, [URL]) {
        let pattern = /!\[[^\]]*\]\(([^)\s]+)\)/
        var urls: [URL] = []
        for match in markdown.matches(of: pattern) {
            if let url = URL(string: String(match.output.1)) { urls.append(url) }
        }
        let text = markdown.replacing(pattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, urls)
    }
}

/// An image in a post: fills the width at a fixed height, rounded.
struct PostImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Palette.fill.overlay {
                    if phase.error != nil {
                        Image(systemName: "photo").foregroundStyle(Palette.textSecondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
        .accessibilityLabel("Image attachment")
    }
}

// MARK: - Previews

struct PostRowPreview: View {
    var body: some View {
        ScrollView {
            EdgeToEdgeList {
                PostRow(authorName: "Me", authorInitials: "SD", isMe: true, meta: "9:01 AM · shift 9:02 AM – now",
                        kind: .plan,
                        markdown: "Finishing the iPad **login redirect** fix, then a pass on onboarding copy with design.",
                        ticketTitle: "Fix login redirect on iPad")
                PostRow(authorName: "Alex Kim", authorInitials: "AK", meta: "Yesterday · 5:40 PM", kind: .wrapUp,
                        markdown: "Export now respects the team time zone. ~~UTC everywhere~~ fixed. Before/after attached.",
                        imageURL: URL(string: "http://127.0.0.1:9/placeholder.png"), likeCount: 3, commentCount: 2)
                PostRow(authorName: "Sam Lee", authorInitials: "SL", meta: "Yesterday · 2:15 PM",
                        markdown: "Anyone free to pair on the *flaky* timesheet test?", commentCount: 1)
            }
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { PostRowPreview() }
#Preview("Dark") { PostRowPreview().preferredColorScheme(.dark) }
