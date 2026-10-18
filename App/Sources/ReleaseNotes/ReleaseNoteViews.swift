import AVFoundation
import HuddleKit
import SwiftUI
import UIKit

/// Settings › What's new: every note for this build and earlier, newest first.
struct ReleaseNotesList: View {
    @Environment(ReleaseNotesStore.self) private var store
    /// The unread set when the list opened, so the dots stay put while you look.
    @State private var unreadOnOpen: Set<String> = []

    var body: some View {
        List(store.notes) { note in
            // A destination link, not a value link: this list is pushed from Settings
            // and from the What's new sheet, and a value link's destination doesn't
            // register on a view pushed that way.
            NavigationLink { ReleaseNoteDetail(note: note) } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(note.title).font(.headline).foregroundStyle(Palette.textPrimary)
                        HStack(spacing: Spacing.s) {
                            Text(meta(note)).font(.footnote).foregroundStyle(Palette.textSecondary)
                            ChannelChip(channel: note.channel)
                        }
                    }
                    Spacer(minLength: 0)
                    if unreadOnOpen.contains(note.id) {
                        Circle().fill(Palette.limeText).frame(width: 8, height: 8)
                            .accessibilityLabel("New")
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .listRowBackground(Palette.canvas)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("What’s new")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.notes.isEmpty {
                StatusView(systemImage: "sparkles", title: "No release notes", message: "This build doesn’t include any.")
            }
        }
        .onAppear {
            if unreadOnOpen.isEmpty { unreadOnOpen = store.unread }
            store.markAllSeen()
        }
    }

    private func meta(_ note: ReleaseNote) -> String {
        let date = Self.parseDate(note.date).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? note.date
        return date.isEmpty ? "Version \(note.version)" : "Version \(note.version) · \(date)"
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

/// One note: its header, then headings, text, pictures and clips.
struct ReleaseNoteDetail: View {
    let note: ReleaseNote
    @Environment(ReleaseNotesStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(spacing: Spacing.s) {
                        Text(verbatim: "Version \(note.version)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        ChannelChip(channel: note.channel)
                    }
                    Text(note.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let date = ReleaseNotesList.parseDate(note.date) {
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                }
                ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.vertical, Spacing.l)
        }
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func blockView(_ block: ReleaseNoteBlock) -> some View {
        switch block {
        case let .heading(title, level):
            Text(title)
                .font(level == 2 ? .title2.bold() : .headline)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, level == 2 ? Spacing.s : 0)
                .accessibilityAddTraits(.isHeader)
        case let .text(markdown):
            PostBody(markdown: markdown)
        case let .image(path, caption):
            NoteMedia(caption: caption) {
                if let url = store.asset(path), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel(caption.isEmpty ? "Screenshot" : caption)
                } else {
                    MissingAsset(path: path)
                }
            }
        case let .video(path, caption):
            NoteMedia(caption: caption) {
                if let url = store.asset(path) {
                    LoopingClip(url: url, caption: caption)
                } else {
                    MissingAsset(path: path)
                }
            }
        }
    }
}

/// A picture or clip with its caption under it, framed like a phone screen.
private struct NoteMedia<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Spacing.s) {
            content
                .frame(maxWidth: 280)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
            if !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true) // read as the media's label
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
    }
}

private struct MissingAsset: View {
    let path: String

    var body: some View {
        Palette.fill
            .aspectRatio(9 / 19.5, contentMode: .fit)
            .overlay { Image(systemName: "photo").foregroundStyle(Palette.textSecondary) }
            .accessibilityLabel("Missing image")
    }
}

/// A short, muted clip that loops. Under Reduce Motion it starts paused on its
/// first frame; a tap plays or pauses it either way.
struct LoopingClip: View {
    let url: URL
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var isPlaying = false
    @State private var aspect: CGFloat = 9 / 19.5

    var body: some View {
        ZStack {
            if let player { PlayerLayerView(player: player) }
            if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.onLime)
                    .frame(width: 56, height: 56)
                    .background(Palette.lime, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background(Palette.surfaceRaised)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityElement()
        .accessibilityLabel(caption.isEmpty ? "Clip" : caption)
        .accessibilityValue(isPlaying ? "Playing" : "Paused")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isPlaying ? "Pauses the clip" : "Plays the clip")
        .task(id: url) { await prepare() }
        .onDisappear { player?.pause(); isPlaying = false }
    }

    private func prepare() async {
        player?.pause()
        looper = nil
        player = nil
        isPlaying = false
        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = size.applying(transform)
            aspect = abs(oriented.width) / abs(oriented.height)
        }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
        player = queue
        if !reduceMotion {
            queue.play()
            isPlaying = true
        }
    }

    private func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}

/// "Pre-beta" and friends.
struct ChannelChip: View {
    let channel: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.breakText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Palette.breakSoft, in: Capsule())
    }

    private var label: String {
        switch channel {
        case "pre-beta": "Pre-beta"
        case "beta": "Beta"
        default: channel.capitalized
        }
    }
}

/// "Huddle got updated": shown once on Now after an update.
struct UpdatedBanner: View {
    let note: ReleaseNote
    var open: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Huddle got updated").font(.footnote.weight(.bold))
                Text(note.title).font(.footnote)
                Button("See what’s new", action: open)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 30)
                    .background(Palette.surface, in: Capsule())
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .padding(.top, -10)
                .padding(.trailing, -10)
        }
        .foregroundStyle(Palette.limeText)
        .padding(14)
        .background(Palette.limeSoft, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// The note the banner opens, with a way to see them all.
struct WhatsNewSheet: View {
    let note: ReleaseNote
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReleaseNoteDetail(note: note)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        NavigationLink("All release notes") { ReleaseNotesList() }
                    }
                }
        }
        .tint(Palette.limeText)
    }
}
