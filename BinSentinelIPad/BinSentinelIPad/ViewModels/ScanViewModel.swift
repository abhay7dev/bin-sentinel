import Combine
import Foundation
import UIKit

@MainActor
final class ScanViewModel: ObservableObject {
    enum ScreenState: Equatable {
        case idle
        case capturing
        case uploading
        case success
        case noItem
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

    func onServerURLChanged() async {
        await refreshHistory()
    }

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
            return "Classifying against facility specs..."
        case .success:
            return "Scan complete"
        case .noItem:
            return "No item detected"
        case .failure:
            return "Scan failed"
        }
    }

    var statusIcon: String {
        switch state {
        case .idle: return "viewfinder"
        case .capturing: return "camera.fill"
        case .uploading: return "arrow.up.circle"
        case .success: return "checkmark.circle.fill"
        case .noItem: return "eye.slash"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    func submitScan(image: UIImage) async {
        state = .uploading
        errorMessage = nil

        do {
            let result = try await apiClient.scan(image: image, city: selectedCity)
            if result.shouldShowVerdictPopup {
                latestResult = result
                state = .success
            } else {
                latestResult = nil
                state = .noItem
            }
            await refreshHistory()
        } catch let error as APIClientError {
            state = .failure
            errorMessage = error.errorDescription
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
            // Non-blocking for scan UX.
        }
    }

    func clearResult() {
        latestResult = nil
        if state != .uploading && state != .capturing {
            state = .idle
        }
    }

    func clearNoItem() {
        if state == .noItem {
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
