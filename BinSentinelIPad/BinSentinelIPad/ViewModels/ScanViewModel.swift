import Combine
import Foundation
import UIKit

@MainActor
final class ScanViewModel: ObservableObject {
    enum ScreenState {
        case idle
        case capturing
        case uploading
        case success
        case failure
    }

    @Published var selectedCity: City = .seattle
    @Published var latestResult: ScanResult?
    @Published var history: [HistoryScan] = []
    @Published var state: ScreenState = .idle
    @Published var errorMessage: String?
    @Published var isHistoryLoading = false

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    /// Call after changing server URL in settings so history reflects the new backend.
    func onServerURLChanged() async {
        await refreshHistory()
    }

    /// Server returns newest first; UI shows only the latest stored scan.
    var mostRecentHistoryScan: HistoryScan? {
        history.first
    }

    var isBusy: Bool {
        state == .capturing || state == .uploading
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Ready to scan"
        case .capturing:
            return "Capturing image..."
        case .uploading:
            return "Checking facility specs..."
        case .success:
            return "Scan complete"
        case .failure:
            return "Scan failed"
        }
    }

    func submitScan(image: UIImage) async {
        state = .uploading
        errorMessage = nil

        do {
            let result = try await apiClient.scan(image: image, city: selectedCity)
            latestResult = result.shouldShowVerdictPopup ? result : nil
            state = .success
            await refreshHistory()
        } catch {
            state = .failure
            errorMessage = "Unable to complete scan. Check connection and try again."
        }
    }

    func refreshHistory() async {
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            history = try await apiClient.fetchHistory()
        } catch {
            // Keep this non-blocking for scan UX.
        }
    }

    func clearResult() {
        latestResult = nil
        if state != .uploading && state != .capturing {
            state = .idle
        }
    }

    func clearError() {
        errorMessage = nil
        if state == .failure {
            state = .idle
        }
    }
}
