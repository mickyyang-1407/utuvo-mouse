import Foundation

/// The updater configuration read from the app bundle.
///
/// The feed URL and the public key decide whether the updater may run at all.
/// A missing or broken key is not a warning: the updater stays off and the
/// interface says that the release is not configured yet.
public struct UpdateConfiguration: Equatable, Sendable {

    /// What keeps the updater from running.
    public enum Problem: Equatable, Sendable {
        case missingFeedURL
        case insecureFeedURL
        case invalidFeedURL
        case missingPublicKey
        case invalidPublicKey
    }

    /// The appcast feed.
    public let feedURL: URL?

    /// The Ed25519 public key that verifies the signed update.
    public let publicEDKey: String?

    /// The reason the updater cannot run, if any.
    public let problem: Problem?

    public init(feedURL: URL?, publicEDKey: String?) {
        let trimmed = publicEDKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = trimmed.isEmpty ? nil : trimmed
        self.feedURL = feedURL
        self.publicEDKey = key
        if feedURL == nil {
            self.problem = .missingFeedURL
        } else if feedURL?.scheme?.lowercased() != "https" {
            self.problem = .insecureFeedURL
        } else if feedURL?.host?.isEmpty != false {
            // A URL without a host is not a feed.
            self.problem = .invalidFeedURL
        } else if let key {
            self.problem = UpdateConfiguration.isValidPublicKey(key) ? nil : .invalidPublicKey
        } else {
            self.problem = .missingPublicKey
        }
    }

    /// Reads the configuration from a bundle.
    public init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String).flatMap { URL(string: $0) }
        self.init(feedURL: feed, publicEDKey: info["SUPublicEDKey"] as? String)
    }

    /// True when the updater may run.
    public var isConfigured: Bool { problem == nil }

    /// A public key is base64 of 32 raw bytes.
    public static func isValidPublicKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.count == 32 else { return false }
        return true
    }
}
