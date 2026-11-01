import Foundation
import AVFoundation

public class APIManager {
    public static let shared = APIManager()
    private var previewAudioPlayer: AVAudioPlayer?

    private init() {}

    public func createTask(
        serverURL: String,
        videoURL: URL,
        voiceID: String,
        genre: String,
        trimStart: Double,
        trimEnd: Double,
        maskRect: MaskRect?,
        dubVolume: Double,
        origVolume: Double,
        cues: [SubtitleCue]?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/tasks/create") else {
            completion(.failure(NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Đường dẫn server không hợp lệ"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func addField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        addField(name: "voice_id", value: voiceID)
        addField(name: "genre", value: genre)
        addField(name: "trim_start", value: String(format: "%.2f", trimStart))
        addField(name: "trim_end", value: String(format: "%.2f", trimEnd))
        addField(name: "dub_volume", value: String(format: "%.2f", dubVolume))
        addField(name: "orig_volume", value: String(format: "%.2f", origVolume))

        if let mask = maskRect, let maskData = try? JSONEncoder().encode(mask), let maskJson = String(data: maskData, encoding: .utf8) {
            addField(name: "mask_rect", value: maskJson)
        }

        if let cues = cues, let cuesData = try? JSONEncoder().encode(cues), let cuesJson = String(data: cuesData, encoding: .utf8) {
            addField(name: "cues", value: cuesJson)
        }

        // Đính kèm file Video MP4
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"input.mp4\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let taskId = json["task_id"] as? String else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không nhận được Task ID từ máy chủ"])))
                return
            }
            completion(.success(taskId))
        }
        task.resume()
    }

    public func pollTaskStatus(
        serverURL: String,
        taskId: String,
        completion: @escaping (Result<TaskStatusResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/tasks/\(taskId)/status") else {
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu trống"])))
                return
            }
            do {
                let statusRes = try JSONDecoder().decode(TaskStatusResponse.self, from: data)
                completion(.success(statusRes))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    public func downloadResultVideo(
        serverURL: String,
        taskId: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/tasks/\(taskId)/download") else {
            return
        }

        let downloadTask = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi tải file"])))
                return
            }
            let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = outputDir.appendingPathComponent("final_\(taskId).mp4")
            try? FileManager.default.removeItem(at: destURL)

            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                completion(.success(destURL))
            } catch {
                completion(.failure(error))
            }
        }
        downloadTask.resume()
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
}
