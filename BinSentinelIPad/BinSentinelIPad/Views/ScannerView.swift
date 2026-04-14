import AVFoundation
import SwiftUI
import UIKit

struct ScannerView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var viewModel = ScanViewModel()
    @StateObject private var locationProvider = LocationCityProvider()
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var autoScanEnabled = true
    @State private var isAutoCooldown = false
    /// Collapses city/scan controls so the camera preview uses more of the screen (e.g. iPhone).
    @State private var isScanPanelMinimized = false
    @State private var serverURLDraft = ""
    @State private var serverURLError: String?
    /// When true, `selectedCity` follows GPS; debug menu sets this to false.
    @State private var useAutomaticCity = true

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                cameraSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                if isScanPanelMinimized {
                    minimizedScanPanelBar
                } else {
                    controlsOverlay
                }

                if let result = viewModel.latestResult {
                    ResultOverlayView(result: result) {
                        autoDismissTask?.cancel()
                        viewModel.clearResult()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.latestResult?.id)
            .background(Color.black)
            .task {
                locationProvider.start()
                if useAutomaticCity, let city = locationProvider.resolvedCity {
                    viewModel.selectedCity = city
                }
                await cameraService.configureSession()
                cameraService.startRunning()
                if serverURLDraft.isEmpty {
                    serverURLDraft = ServerURLSettings.storedURLString ?? AppConfig.defaultBaseURLString
                }
                await viewModel.refreshHistory()
            }
            .onDisappear {
                autoDismissTask?.cancel()
                cameraService.stopRunning()
            }
            .onChange(of: viewModel.selectedCity) { _ in
                viewModel.clearResult()
                viewModel.clearError()
            }
            .onChange(of: viewModel.latestResult?.id) { _ in
                scheduleAutoDismissResult()
            }
            .onChange(of: cameraService.autoCaptureSignal) { _ in
                Task {
                    await handleAutoScanTrigger()
                }
            }
            .onChange(of: locationProvider.resolvedCity) { newCity in
                guard useAutomaticCity, let city = newCity else { return }
                viewModel.selectedCity = city
            }
            .navigationTitle("Bin Sentinel")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private var cameraSection: some View {
        Group {
            if cameraService.authorizationStatus == .authorized {
                CameraPreviewView(
                    session: cameraService.session,
                    highlightMetadataRect: cameraService.salientMetadataRect
                ) { orientation in
                    cameraService.syncCaptureConnections(videoOrientation: orientation)
                }
            } else if cameraService.authorizationStatus == .denied || cameraService.authorizationStatus == .restricted {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                    Text("Camera access is required.")
                        .font(.headline)
                    Text("Enable camera permissions in Settings to scan items.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ProgressView("Preparing camera...")
            }
        }
    }

    private var minimizedScanPanelBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isScanPanelMinimized = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                Text("Scan controls")
                    .fontWeight(.semibold)
                Spacer()
                if viewModel.isBusy {
                    ProgressView()
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isScanPanelMinimized = true
                }
            } label: {
                HStack {
                    Text("Hide controls")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            ScrollView {
                VStack(spacing: 12) {
            Text(locationProvider.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Toggle(isOn: $autoScanEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: autoScanEnabled ? "bolt.circle.fill" : "bolt.circle")
                    Text("Auto scan")
                }
                .font(.subheadline)
            }
            .padding(.horizontal)

            ProgressView(value: cameraService.motionLevel)
                .padding(.horizontal)
                .tint(.mint)

            Text(autoScanStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.clearError()
                    }
                    .font(.footnote)
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await captureAndSubmit()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isBusy {
                        ProgressView()
                    }
                    Text(viewModel.isBusy ? "Scanning..." : "Scan item")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isBusy ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.isBusy || cameraService.authorizationStatus != .authorized)
            .padding(.horizontal)

            LatestHistoryView(scan: viewModel.mostRecentHistoryScan, isLoading: viewModel.isHistoryLoading)
                .padding(.horizontal)

            debugCitySection
                .padding(.horizontal)

            serverURLSection
                .padding(.horizontal)
                .padding(.bottom, 12)
                }
                .padding(.top, 8)
            }
        }
        .background(.regularMaterial)
    }

    private var debugCitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug: MRF city")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("MRF city", selection: Binding(
                get: { viewModel.selectedCity },
                set: { newCity in
                    useAutomaticCity = false
                    viewModel.selectedCity = newCity
                }
            )) {
                ForEach(City.allCases) { city in
                    Text(city.displayName).tag(city)
                }
            }
            .pickerStyle(.menu)

            Button("Use location-based city") {
                useAutomaticCity = true
                if let city = locationProvider.resolvedCity {
                    viewModel.selectedCity = city
                }
            }
            .font(.caption)
        }
        .padding(.top, 4)
    }

    private var serverURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API server")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField("http://192.168.1.10:8000", text: $serverURLDraft)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button("Apply") {
                    applyServerURL()
                }
                .buttonStyle(.borderedProminent)

                Button("Use default") {
                    serverURLDraft = AppConfig.defaultBaseURLString
                    ServerURLSettings.storedURLString = nil
                    serverURLError = nil
                    Task { await viewModel.onServerURLChanged() }
                }
                .font(.subheadline)
            }

            if let serverURLError {
                Text(serverURLError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Saved on this device. Use your Mac’s LAN IP when testing on a phone (backend: uvicorn --host 0.0.0.0).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func applyServerURL() {
        let trimmed = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ServerURLSettings.normalizeToURL(trimmed) else {
            serverURLError = "Enter a valid URL or host:port (e.g. 192.168.1.5:8000)."
            return
        }
        serverURLError = nil
        ServerURLSettings.storedURLString = url.absoluteString
        serverURLDraft = url.absoluteString
        Task { await viewModel.onServerURLChanged() }
    }

    private func captureAndSubmit() async {
        autoDismissTask?.cancel()
        viewModel.errorMessage = nil
        viewModel.state = .capturing

        do {
            let image = try await cameraService.capturePhoto()
            await viewModel.submitScan(image: image)
        } catch {
            viewModel.state = .failure
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var autoScanStatusText: String {
        if !autoScanEnabled {
            return "Auto scan is off."
        }
        if isAutoCooldown {
            return "Auto scan cooldown..."
        }
        if viewModel.isBusy {
            return "Auto scan waiting for current request..."
        }
        return "Auto scan armed: move item into frame, then hold steady."
    }

    private func handleAutoScanTrigger() async {
        guard autoScanEnabled else { return }
        guard !viewModel.isBusy else { return }
        guard !isAutoCooldown else { return }
        guard cameraService.authorizationStatus == .authorized else { return }

        await captureAndSubmit()
        await startAutoCooldown()
    }

    private func startAutoCooldown() async {
        isAutoCooldown = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !Task.isCancelled {
            isAutoCooldown = false
        }
    }

    private func scheduleAutoDismissResult() {
        autoDismissTask?.cancel()
        guard viewModel.latestResult != nil else { return }

        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            viewModel.clearResult()
        }
    }
}

#Preview {
    ScannerView()
}
