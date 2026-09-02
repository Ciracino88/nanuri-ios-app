import Foundation
import Supabase

/// Cloudflare Worker(R2) 기반 영수증 이미지 저장소.
/// 청구서 영수증과 재정 영수증이 같은 버킷을 쓰고, `folder` 로만 갈린다.
enum ReceiptStorage {
    /// 청구 폼 워커. **영수증 R2 도 이 워커가 들고 있다.**
    ///
    /// 예전에는 `nanuri-bill` 이라는 별도 워커였는데 소스가 어디에도 없어서
    /// 고칠 수가 없었다. 버킷을 청구 폼 워커에 옮겨 붙이고 코드를 가져왔다.
    ///
    /// 주소가 `<워커이름>.<계정서브도메인>.workers.dev` 형태라, Cloudflare 대시보드에서
    /// 계정 서브도메인을 바꾸면 여기도 같이 고쳐야 한다. 안 고치면 업로드·삭제가 전부 깨진다.
    /// (이미 저장된 이미지 URL은 pub-*.r2.dev 도메인이라 영향받지 않는다)
    static let workerBaseUrl = "https://nanuri-form.nanuri.workers.dev"

    enum StorageError: LocalizedError {
        case notSignedIn
        case invalidEndpoint
        case serverError
        case noURLInResponse

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "로그인이 필요해요."
            case .invalidEndpoint: return "업로드 주소가 올바르지 않아요."
            case .serverError: return "서버 응답 오류로 업로드에 실패했어요."
            case .noURLInResponse: return "업로드 응답에서 URL을 찾지 못했어요."
            }
        }
    }

    /// 워커에 넘길 Supabase access token.
    ///
    /// 워커가 이 토큰으로 "누구인가" 를 확인하고 `admins` 화이트리스트를 본다.
    /// 없으면 401 이 오므로 부르기 전에 막는다.
    ///
    /// 여기서는 `auth.session` 을 쓴다. 만료됐으면 갱신해서 **쓸 수 있는** 토큰을
    /// 줘야 하기 때문이다. `AuthViewModel.checkSession()` 이 네트워크를 안 타는
    /// `currentSession` 만 보는 것과는 목적이 다르다 — 그쪽은 로그인 화면으로
    /// 보낼지를 정하는 자리라 네트워크가 없다고 로그아웃시키면 안 된다.
    /// **두 곳을 같게 만들지 말 것.**
    private static func accessToken() async throws -> String {
        do {
            return try await supabase.auth.session.accessToken
        } catch {
            throw StorageError.notSignedIn
        }
    }

    /// 이미지를 R2에 업로드하고 공개 URL을 반환한다.
    /// - Parameter folder: R2 내 저장 폴더. 미지정 시 Worker 기본값("receipts") 사용.
    static func upload(imageData: Data, filename: String, folder: String? = nil) async throws -> String {
        guard let url = URL(string: "\(workerBaseUrl)/receipt/upload") else {
            throw StorageError.invalidEndpoint
        }

        let token = try await accessToken()

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
        guard let url = URL(string: "\(workerBaseUrl)/receipt/delete"),
              let token = try? await accessToken() else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
