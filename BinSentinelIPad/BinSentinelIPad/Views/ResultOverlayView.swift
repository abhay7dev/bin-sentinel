import SwiftUI

/// Bottom-sheet style verdict overlay (matches web `ResultOverlay`), separate from the settings panel.
struct ResultOverlayView: View {
    let result: ScanResult
    let onDismiss: () -> Void

    private var accent: Color {
        switch result.actionEnum {
        case .recycle: return .blue
        case .trash: return .red
        case .compost: return .green
        case .special: return .purple
        case .na: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(result.actionEnum.displayTitle)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(result.confidence.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .padding(.bottom, 8)

            Text(result.item)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, 10)

            Text(result.reason)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(result.city) · tap to dismiss")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                accent.opacity(0.82)
                Color.black.opacity(0.25)
            }
            .background(.ultraThinMaterial)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.5))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(accent.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }
}
