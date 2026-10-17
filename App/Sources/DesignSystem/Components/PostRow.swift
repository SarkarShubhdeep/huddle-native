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
    var likeCount = 0
    var commentCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(rendered)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.limeText)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                image(imageURL)
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

    private func image(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Palette.fill.overlay {
                    if phase.error != nil {
                        Image(systemName: "photo").foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
        .accessibilityLabel("Image attachment")
    }

    /// Inline markdown (bold, italic, strikethrough, links). Lists and
    /// checklists get their full rendering with the composer in Step 8.
    private var rendered: AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
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
