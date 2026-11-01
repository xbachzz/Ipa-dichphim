import Foundation

class APIManager {
    static let shared = APIManager()
    private init() {}

    func uploadAndTranslate(
        serverURL: String,
        videoURL: URL,
        srtURL: URL?,
        voiceID: String,
        genre: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/translate-and-dub") else {
            completion(.failure(NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Đường dẫn server không hợp lệ"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600 // 10 phút tối đa cho render video

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Thêm trường voice_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voice_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(voiceID)\r\n".data(using: .utf8)!)

        // Thêm trường genre
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"genre\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(genre)\r\n".data(using: .utf8)!)

        // Đính kèm file Video MP4
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"input.mp4\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Đính kèm file SRT (nếu có)
        if let srtURL = srtURL, let srtData = try? Data(contentsOf: srtURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"srt\"; filename=\"input.srt\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
            body.append(srtData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                completion(.failure(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về lỗi khi xử lý"])))
                return
            }

            // Lưu file video nhận được về thư mục Documents của iPhone
            let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = outputDir.appendingPathComponent("dubbed_\(Int(Date().timeIntervalSince1970)).mp4")

            do {
                try data.write(to: destURL)
                completion(.success(destURL))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
