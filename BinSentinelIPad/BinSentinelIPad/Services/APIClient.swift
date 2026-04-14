import Foundation
import UIKit

enum APIClientError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, message: String)
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let status, let message):
            return "Server error (\(status)): \(message)"
        case .serializationFailed:
            return "Failed to parse server response."
        }
    }
}

final class APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var baseURL: URL {
        ServerURLSettings.resolvedBaseURL()
    }

    func scan(image: UIImage, city: City) async throws -> ScanResult {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIClientError.serializationFailed
        }

        let endpoint = baseURL.appendingPathComponent("scan")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let body = makeMultipartBody(
            imageData: imageData,
            city: city.rawValue,
            boundary: boundary,
            filename: "scan.jpg",
            mimeType: "image/jpeg"
        )
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            throw try decodeAPIError(statusCode: http.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(ScanResult.self, from: data)
        } catch {
            throw APIClientError.serializationFailed
        }
    }

    func fetchHistory() async throws -> [HistoryScan] {
        let endpoint = baseURL.appendingPathComponent("history")
        let (data, response) = try await session.data(from: endpoint)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            throw try decodeAPIError(statusCode: http.statusCode, data: data)
        }

        do {
            let history = try JSONDecoder().decode(HistoryResponse.self, from: data)
            return history.scans
        } catch {
            throw APIClientError.serializationFailed
        }
    }

    private func decodeAPIError(statusCode: Int, data: Data) throws -> APIClientError {
        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            let detailText = apiError.detail ?? ""
            let detail = detailText.isEmpty ? "" : " (\(detailText))"
            return .httpError(status: statusCode, message: "\(apiError.error)\(detail)")
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return .httpError(status: statusCode, message: raw)
        }

        return .httpError(status: statusCode, message: "Unknown error")
    }

    private func makeMultipartBody(
        imageData: Data,
        city: String,
        boundary: String,
        filename: String,
        mimeType: String
    ) -> Data {
        var data = Data()

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"city\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(city)\r\n".data(using: .utf8)!)

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n".data(using: .utf8)!)

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}
