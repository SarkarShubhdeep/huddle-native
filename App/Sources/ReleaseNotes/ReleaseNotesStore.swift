import Foundation
import HuddleKit
import Observation

/// The release notes bundled with this build, and which of them this person
/// has seen. "Seen" is kept on the device; the backend has no field for it.
@MainActor
@Observable
final class ReleaseNotesStore {
    /// Notes for this build and earlier, newest first.
    let notes: [ReleaseNote]
    let appVersion: SemanticVersion
    /// The newest version this person has seen the notes for.
    private(set) var seen: SemanticVersion?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let folder: URL?
    private static let seenKey = "releaseNotes.seenVersion"

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(SemanticVersion.init)
            ?? SemanticVersion("0.0.0")!
        appVersion = version
        folder = bundle.url(forResource: "ReleaseNotes", withExtension: nil)
        notes = ReleaseNoteCatalog.visible(Self.load(from: folder), appVersion: version)

        if let saved = defaults.string(forKey: Self.seenKey).flatMap(SemanticVersion.init) {
            seen = saved
        } else {
            // A fresh install: nothing is new yet to someone who just installed.
            seen = version
            defaults.set(version.description, forKey: Self.seenKey)
        }
    }

    /// The note to announce with "Huddle got updated", if any.
    var announcement: ReleaseNote? { ReleaseNoteCatalog.announcement(notes, appVersion: appVersion, seen: seen) }

    var unread: Set<String> { ReleaseNoteCatalog.unread(notes, appVersion: appVersion, seen: seen) }

    /// Marks everything up to this build as seen: the banner goes and stays gone.
    func markAllSeen() {
        guard seen != appVersion else { return }
        seen = appVersion
        defaults.set(appVersion.description, forKey: Self.seenKey)
    }

    /// A file a note refers to, such as `assets/0.3.0/now.jpg`.
    func asset(_ path: String) -> URL? {
        guard let folder, !path.hasPrefix("/") else { return nil }
        // Stay inside the bundled folder, whatever the path says.
        let root = folder.standardizedFileURL.path + "/"
        let url = folder.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func load(from folder: URL?) -> [ReleaseNote] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return ReleaseNote.parse(text, filename: url.lastPathComponent)
        }
    }
}
