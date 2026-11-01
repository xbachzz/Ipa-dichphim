import SwiftUI
import PhotosUI
import AVKit

struct VoiceItem: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ContentView: View {
    @State private var serverURL: String = "http://YOUR_SERVER_IP:9005"
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var srtFileURL: URL? = nil
    @State private var srtFileName: String = ""
    @State private var showSRTPicker: Bool = false
    
    @State private var selectedVoice: String = "BV421_vivn_streaming"
    @State private var selectedGenre: String = "phim_chung"
    
    @State private var isProcessing: Bool = false
    @State private var progressMessage: String = ""
    @State private var outputVideoURL: URL? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    let voices = [
        VoiceItem(id: "BV421_vivn_streaming", name: "Nam Tri Thức (Review Phim)"),
        VoiceItem(id: "multi_female_richgirl_uranus_bigtts", name: "Nữ Sang Trọng / Kịch Tính"),
        VoiceItem(id: "BV001_streaming", name: "Nữ Đọc Truyện / Truyền Cảm"),
        VoiceItem(id: "BV007_streaming", name: "Nam Trầm Ấm / Thời Sự")
    ]

    let genres = [
        ("phim_chung", "Đời thường / TikTok"),
        ("kiem_hiep", "Cổ trang / Kiếm hiệp"),
        ("tong_tai", "Tổng tài / Ngôn tình"),
        ("hai_huoc", "Hài hước / Dí dỏm")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Cấu hình máy chủ VPS")) {
                    TextField("Server API URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("1. Chọn Video & Phụ đề")) {
                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                        Label(selectedVideoURL == nil ? "Chọn Video từ Thư viện Ảnh" : "Đã chọn: \(selectedVideoURL!.lastPathComponent)",
                              systemImage: "video.badge.plus")
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("input_video.mp4")
                                try? data.write(to: tempURL)
                                selectedVideoURL = tempURL
                            }
                        }
                    }

                    HStack {
                        Button(action: { showSRTPicker = true }) {
                            Label(srtFileName.isEmpty ? "Nhập file SRT (Tùy chọn)" : "File: \(srtFileName)",
                                  systemImage: "doc.text")
                        }
                        if !srtFileName.isEmpty {
                            Spacer()
                            Button("Xóa") {
                                srtFileURL = nil
                                srtFileName = ""
                            }
                            .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("2. Giọng đọc & Phong cách")) {
                    Picker("Giọng đọc (CapCut TTS)", selection: $selectedVoice) {
                        ForEach(voices) { v in
                            Text(v.name).tag(v.id)
                        }
                    }

                    Picker("Văn phong dịch (9Router)", selection: $selectedGenre) {
                        ForEach(genres, id: \.0) { g in
                            Text(g.1).tag(g.0)
                        }
                    }
                }

                Section {
                    Button(action: startTranslating) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text(progressMessage)
                                    .fontWeight(.bold)
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Bắt đầu Dịch & Lồng tiếng")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || selectedVideoURL == nil)
                    .listRowBackground(selectedVideoURL != nil ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                }

                if let outURL = outputVideoURL {
                    Section(header: Text("3. Video Hoàn Thiện")) {
                        VideoPlayer(player: AVPlayer(url: outURL))
                            .frame(height: 250)
                            .cornerRadius(8)

                        Button(action: saveToPhotoLibrary) {
                            Label("Lưu Video vào Album Ảnh", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .navigationTitle("Dịch & Lồng Tiếng AI")
            .fileImporter(isPresented: $showSRTPicker, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    srtFileURL = url
                    srtFileName = url.lastPathComponent
                case .failure(let err):
                    print("Lỗi chọn file: \(err)")
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    func startTranslating() {
        guard let videoURL = selectedVideoURL else { return }
        isProcessing = true
        progressMessage = "Đang tải video lên server VPS..."

        APIManager.shared.uploadAndTranslate(
            serverURL: serverURL,
            videoURL: videoURL,
            srtURL: srtFileURL,
            voiceID: selectedVoice,
            genre: selectedGenre
        ) { result in
            DispatchQueue.main.async {
                isProcessing = false
                switch result {
                case .success(let savedURL):
                    outputVideoURL = savedURL
                    alertMessage = "Hoàn thành! Bạn có thể xem thử hoặc lưu vào Album."
                    showAlert = true
                case .failure(let err):
                    alertMessage = "Lỗi: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func saveToPhotoLibrary() {
        guard let outURL = outputVideoURL else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outURL)
        }) { success, error in
            DispatchQueue.main.async {
                alertMessage = success ? "Đã lưu video thành công vào Photos!" : "Lỗi lưu: \(error?.localizedDescription ?? "Không rõ")"
                showAlert = true
            }
        }
    }
}
