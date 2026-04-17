import Foundation

enum AppConfig {
    /// Used when nothing is saved in Settings (see `ServerURLSettings`).
    static let defaultBaseURLString = "http://127.0.0.1:8000"
    static var defaultBaseURL: URL { URL(string: defaultBaseURLString)! }
}
