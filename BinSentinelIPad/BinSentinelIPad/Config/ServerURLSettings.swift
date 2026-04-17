import Foundation

/// Persists the API base URL so you can switch networks without rebuilding.
enum ServerURLSettings {
    private static let key = "binsentinel.apiBaseURL"

    /// Raw string from UserDefaults (may be invalid until normalized).
    static var storedURLString: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                UserDefaults.standard.set(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// URL used for all API calls: saved value if valid, otherwise `AppConfig.defaultBaseURL`.
    static func resolvedBaseURL() -> URL {
        if let s = storedURLString, !s.isEmpty, let url = normalizeToURL(s) {
            return url
        }
        return AppConfig.defaultBaseURL
    }

    /// Accepts `http://host:port`, `host:port`, or `https://...`.
    static func normalizeToURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            s = "http://\(s)"
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard url.host != nil else { return nil }
        return url
    }
}
