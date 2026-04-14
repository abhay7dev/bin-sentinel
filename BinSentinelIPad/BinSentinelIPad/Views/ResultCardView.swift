import SwiftUI

struct ResultCardView: View {
    let result: ScanResult
    var onDismiss: (() -> Void)? = nil

    private var tintColor: Color {
        switch result.actionEnum {
        case .recycle:
            return .blue
        case .trash:
            return .red
        case .compost:
            return .green
        case .special:
            return .purple
        case .na:
            return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss result")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.actionEnum.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text(result.confidence.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(result.item)
                    .font(.headline)

                Text(result.reason)
                    .font(.body)

                Text("City: \(result.city)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(tintColor.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tintColor.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
