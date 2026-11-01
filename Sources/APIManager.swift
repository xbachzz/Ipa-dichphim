import Foundation
import AVFoundation

public class APIManager {
    public static let shared = APIManager()
    private var previewAudioPlayer: AVAudioPlayer?

    private init() {}

    // BƯỚC 1: Tải video lên khởi tạo Project
    public func uploadVideo(
        serverURL: String,
        videoURL: URL,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/step/upload") else {
            completion(.failure(NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Đường dẫn server không hợp lệ"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"input.mp4\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi tải video lên"])))
                return
            }
            completion(.success(json))
        }.resume()
    }

    // BƯỚC 2: Chuyển âm thanh thành SRT (CapCut STT)
    public func stepSTT(
        serverURL: String,
        projectId: String,
        sourceLang: String = "zh-CN",
        completion: @escaping (Result<[SubtitleCue], Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/step/stt") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["project_id": projectId, "source_lang": sourceLang]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cuesRaw = json["cues"] as? [[String: Any]],
                  let cuesData = try? JSONSerialization.data(withJSONObject: cuesRaw),
                  let cues = try? JSONDecoder().decode([SubtitleCue].self, from: cuesData) else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không nhận dạng được câu thoại"])))
                return
            }
            completion(.success(cues))
        }.resume()
    }

    // BƯỚC 3: Dịch SRT qua 9Router AI
    public func stepTranslate(
        serverURL: String,
        projectId: String,
        cues: [SubtitleCue],
        genre: String,
        completion: @escaping (Result<[SubtitleCue], Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/step/translate") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let cuesData = try? JSONEncoder().encode(cues),
              let cuesJson = try? JSONSerialization.jsonObject(with: cuesData) else { return }

        let body: [String: Any] = ["project_id": projectId, "cues": cuesJson, "genre": genre]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cuesRaw = json["cues"] as? [[String: Any]],
                  let cuesData = try? JSONSerialization.data(withJSONObject: cuesRaw),
                  let translatedCues = try? JSONDecoder().decode([SubtitleCue].self, from: cuesData) else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi dịch phụ đề qua 9Router"])))
                return
            }
            completion(.success(translatedCues))
        }.resume()
    }

    // BƯỚC 4: Chuyển văn bản thành âm thanh (CapCut TTS)
    public func stepTTS(
        serverURL: String,
        projectId: String,
        cues: [SubtitleCue],
        voiceId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/step/tts") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let cuesData = try? JSONEncoder().encode(cues),
              let cuesJson = try? JSONSerialization.jsonObject(with: cuesData) else { return }

        let body: [String: Any] = ["project_id": projectId, "cues": cuesJson, "voice_id": voiceId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success else {
                let errMsg = (data != nil ? (try? JSONSerialization.jsonObject(with: data!) as? [String: Any])?["error"] as? String : nil) ?? "Lỗi tạo giọng đọc CapCut"
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])))
                return
            }
            completion(.success(true))
        }.resume()
    }

    // BƯỚC 5 & 6: Ghép vào video & Render xuất file
    public func stepRender(
        serverURL: String,
        projectId: String,
        cues: [SubtitleCue],
        maskRect: MaskRect?,
        logoRect: MaskRect?,
        dubVolume: Double,
        origVolume: Double,
        trimStart: Double,
        trimEnd: Double,
        renderPreset: String = "ultrafast",
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/step/render") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let cuesData = try? JSONEncoder().encode(cues),
              let cuesJson = try? JSONSerialization.jsonObject(with: cuesData) else { return }

        var body: [String: Any] = [
            "project_id": projectId,
            "cues": cuesJson,
            "dub_volume": dubVolume,
            "orig_volume": origVolume,
            "trim_start": trimStart,
            "trim_end": trimEnd,
            "render_preset": renderPreset
        ]
        if let mask = maskRect, let mData = try? JSONEncoder().encode(mask), let mJson = try? JSONSerialization.jsonObject(with: mData) {
            body["mask_rect"] = mJson
        }
        if let logo = logoRect, let lData = try? JSONEncoder().encode(logo), let lJson = try? JSONSerialization.jsonObject(with: lData) {
            body["logo_rect"] = lJson
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let downloadUrlPath = json["download_url"] as? String else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi render video"])))
                return
            }

            let renderTime = json["render_time_sec"] as? Double ?? 0.0
            let speedRatio = json["speed_ratio"] as? Double ?? 1.0

            // Tải file về
            let fullDownloadURL = "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))\(downloadUrlPath)"
            self?.downloadFinalFile(from: fullDownloadURL, projectId: projectId, renderTime: renderTime, speedRatio: speedRatio, completion: completion)
        }.resume()
    }

    private func downloadFinalFile(from urlString: String, projectId: String, renderTime: Double, speedRatio: Double, completion: @escaping (Result<RenderResult, Error>) -> Void) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi tải video"])))
                return
            }
            let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = outputDir.appendingPathComponent("final_\(projectId).mp4")
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                let result = RenderResult(url: destURL, renderTimeSec: renderTime, speedRatio: speedRatio)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    public func playTTSPreview(serverURL: String, text: String, voiceID: String) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/tts/preview") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "voice_id": voiceID]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data = data else { return }
            DispatchQueue.main.async {
                self?.previewAudioPlayer = try? AVAudioPlayer(data: data)
                self?.previewAudioPlayer?.play()
            }
        }.resume()
    }

    // Kiểm tra kết nối máy chủ VPS
    public func testConnection(serverURL: String, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/voices") else {
            completion(false, "Đường dẫn server không hợp lệ")
            return
        }
        let startTime = Date()
        var req = URLRequest(url: url)
        req.timeoutInterval = 8

        URLSession.shared.dataTask(with: req) { data, resp, err in
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            if let err = err {
                completion(false, "Không thể kết nối (\(ms)ms): \(err.localizedDescription)")
            } else if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                completion(true, "Kết nối thành công (\(ms)ms) - Server & Voice API sẵn sàng")
            } else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                completion(false, "Server phản hồi mã lỗi HTTP \(code)")
            }
        }.resume()
    }
}
