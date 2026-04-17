import SwiftUI

struct LatestHistoryView: View {
    let scan: HistoryScan?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last scan")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let scan {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(scan.action)
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(scan.city.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formattedTimestamp(scan.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(scan.item)
                        .font(.subheadline)
                    Text(scan.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                Text("No scans yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedTimestamp(_ timestamp: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackParser = ISO8601DateFormatter()
        fallbackParser.formatOptions = [.withInternetDateTime]

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        if let date = parser.date(from: timestamp) ?? fallbackParser.date(from: timestamp) {
            return formatter.string(from: date)
        }
        return timestamp
    }
}
