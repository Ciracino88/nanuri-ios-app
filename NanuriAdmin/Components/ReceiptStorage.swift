import Foundation

/// Cloudflare Worker(R2) 기반 영수증 이미지 저장소.
/// 원래 청구서 영수증용으로 만든 R2 버킷을, 재정 관리 영수증에서도 공용으로 재사용한다.
enum ReceiptStorage {
    /// 청구서 영수증과 동일한 R2 Worker.
    static let workerBaseUrl = "https://nanuri-bill.church-worker.workers.dev"

    enum StorageError: LocalizedError {
        case invalidEndpoint
        case serverError
        case noURLInResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "업로드 주소가 올바르지 않아요."
            case .serverError: return "서버 응답 오류로 업로드에 실패했어요."
            case .noURLInResponse: return "업로드 응답에서 URL을 찾지 못했어요."
            }
        }
    }

    /// 이미지를 R2에 업로드하고 공개 URL을 반환한다.
    /// - Parameter folder: R2 내 저장 폴더. 미지정 시 Worker 기본값("receipts") 사용.
    static func upload(imageData: Data, filename: String, folder: String? = nil) async throws -> String {
        guard let url = URL(string: "\(workerBaseUrl)/upload") else {
            throw StorageError.invalidEndpoint
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let folder {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(folder)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StorageError.serverError
        }
        guard let urlString = parseURL(from: data) else {
            throw StorageError.noURLInResponse
        }
        return urlString
    }

    /// R2에서 이미지를 삭제한다. (청구서 삭제 시 쓰던 로직과 동일)
    static func delete(receiptUrl: String) async {
        guard let url = URL(string: "\(workerBaseUrl)/delete") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["receiptUrl": receiptUrl])
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Worker 응답에서 이미지 URL을 추출한다.
    /// JSON `{ "url" | "imageUrl" | "receiptUrl": "..." }` 또는 본문이 URL 문자열인 경우를 처리한다.
    private static func parseURL(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["url", "imageUrl", "receiptUrl"] {
                if let value = obj[key] as? String { return value }
            }
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.hasPrefix("http") {
            return text
        }
        return nil
    }
}
