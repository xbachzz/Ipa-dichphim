import SwiftUI
import PhotosUI
import AVKit

struct VoiceItem: Identifiable, Hashable {
    let id: String
    let name: String
}

public struct ContentView: View {
    // Cấu hình kết nối VPS
    @AppStorage("server_url") private var serverURL: String = "http://103.211.206.176:9005"
    
    // Video State
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var player: AVPlayer? = nil
    @State private var videoDuration: Double = 60.0
    
    // Trim State
    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 60.0
    
    // Mask Sub/Logo State (Tọa độ tương đối 0.0 - 1.0)
    @State private var enableMask: Bool = true
    @State private var maskYRatio: CGFloat = 0.82
    @State private var maskHeightRatio: CGFloat = 0.12
    @State private var maskStyle: String = "box_semi"
    
    // Audio Mixer State
    @State private var dubVolume: Double = 1.0
    @State private var origVolume: Double = 0.12
    
    // AI & Voice State
    @State private var selectedVoice: String = "BV421_vivn_streaming"
    @State private var selectedGenre: String = "phim_chung"
    
    // Subtitle Editor State
    @State private var cues: [SubtitleCue] = []
    @State private var showSubtitleStudio: Bool = false
    
    // Task Progress State
    @State private var isProcessing: Bool = false
    @State private var currentTaskId: String = ""
    @State private var progressPercent: Int = 0
    @State private var progressStage: String = ""
    @State private var progressMessage: String = ""
    @State private var timer: Timer? = nil
    
    // Result State
    @State private var outputVideoURL: URL? = nil
    @State private var resultPlayer: AVPlayer? = nil
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
        ("hai_huoc", "Hài hước / Bắt trend")
    ]

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // PHẦN 1: VIDEO CANVAS & MASK PREVIEW
                    if let _ = selectedVideoURL {
                        videoCanvasView
                            .frame(height: 280)
                            .background(Color.black)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    } else {
                        emptyVideoPlaceholder
                            .frame(height: 200)
                            .padding(.horizontal)
                    }

                    // PHẦN 2: THANH CÔNG CỤ BIÊN TẬP (TRIM & MASK)
                    if selectedVideoURL != nil {
                        editorControlSection
                            .padding(.horizontal)
                    }

                    // PHẦN 3: GIỌNG ĐỌC & BỘ TRỘN ÂM THANH
                    audioMixerSection
                        .padding(.horizontal)

                    // PHẦN 4: SUBTITLE STUDIO
                    if !cues.isEmpty {
                        subtitlePreviewCard
                            .padding(.horizontal)
                    }

                    // PHẦN 5: TIẾN TRÌNH RENDER THỜI GIAN THỰC
                    if isProcessing {
                        progressTrackerCard
                            .padding(.horizontal)
                    }

                    // NÚT BẮT ĐẦU DỊCH & XUẤT VIDEO
                    Button(action: startExportTask) {
                        HStack {
                            Spacer()
                            Image(systemName: "wand.and.stars.inverse")
                            Text(isProcessing ? "Đang xử lý (\(progressPercent)%)..." : "Xuất Video Lồng Tiếng AI")
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding()
                        .background(isProcessing || selectedVideoURL == nil ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing || selectedVideoURL == nil)
                    .padding(.horizontal)

                    // PHẦN 6: KẾT QUẢ THÀNH PHẨM
                    if let _ = outputVideoURL, let resPlayer = resultPlayer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("🎬 Video Hoàn Thiện")
                                .font(.headline)
                            VideoPlayer(player: resPlayer)
                                .frame(height: 240)
                                .cornerRadius(12)
                            
                            Button(action: saveToPhotoLibrary) {
                                Label("Lưu Video vào Album Ảnh", systemImage: "square.and.arrow.down.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("AI Video Editor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: serverSettingsView) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSubtitleStudio) {
                subtitleStudioSheet
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    // Giao diện khi chưa chọn video
    var emptyVideoPlaceholder: some View {
        PhotosPicker(selection: $selectedItem, matching: .videos) {
            VStack(spacing: 12) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                Text("Nhấn để Chọn Video cần Dịch & Biên tập")
                    .font(.headline)
                Text("Hỗ trợ video MP4, MOV từ Album ảnh")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(.blue.opacity(0.5))
            )
        }
        .onChange(of: selectedItem) { newItem in
            loadSelectedVideo(newItem)
        }
    }

    // Màn hình Canvas tương tác (Video + Hộp che sub)
    var videoCanvasView: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let p = player {
                    VideoPlayer(player: p)
                        .disabled(true)
                }

                // Vùng hộp che sub có thể kéo thả
                if enableMask {
                    let boxH = geo.size.height * maskHeightRatio
                    let boxY = geo.size.height * maskYRatio

                    ZStack {
                        Rectangle()
                            .fill(maskStyle == "box_black" ? Color.black : Color.black.opacity(0.7))
                            .overlay(
                                Text("Vùng che Sub / Logo")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            )
                            .border(Color.red, width: 1.5)
                    }
                    .frame(width: geo.size.width * 0.96, height: boxH)
                    .offset(x: geo.size.width * 0.02, y: boxY)
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                let newY = val.location.y / geo.size.height
                                maskYRatio = max(0.0, min(0.9, newY))
                            }
                    )
                }
            }
        }
    }

    // Bộ điều khiển Cắt (Trim) và Che Sub
    var editorControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("✂️ Biên Tập Video & Che Sub")
                .font(.headline)

            // Cắt đoạn (Trim)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Cắt đoạn:")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fs - %.1fs", trimStart, trimEnd))
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                HStack {
                    Slider(value: $trimStart, in: 0...max(1.0, trimEnd - 1.0))
                    Slider(value: $trimEnd, in: min(videoDuration, trimStart + 1.0)...videoDuration)
                }
            }

            // Tùy chỉnh vùng che phụ đề gốc
            Toggle("Bật vùng che phụ đề cũ / Logo", isOn: $enableMask)
                .font(.subheadline)

            if enableMask {
                Picker("Kiểu che", selection: $maskStyle) {
                    Text("Hộp mờ đen").tag("box_semi")
                    Text("Đen tuyền").tag("box_black")
                    Text("Xóa mờ (Delogo)").tag("delogo")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // Bộ trộn âm thanh & Giọng đọc
    var audioMixerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎙️ Giọng Đọc & Âm Thanh")
                .font(.headline)

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

            HStack {
                Text("Âm lượng lồng tiếng:")
                    .font(.caption)
                Slider(value: $dubVolume, in: 0.2...2.0)
                Text("\(Int(dubVolume * 100))%")
                    .font(.caption)
            }

            HStack {
                Text("Âm lượng video gốc:")
                    .font(.caption)
                Slider(value: $origVolume, in: 0.0...0.5)
                Text("\(Int(origVolume * 100))%")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // Xem trước phụ đề
    var subtitlePreviewCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("📝 Đã nhận diện \(cues.count) câu thoại")
                    .font(.subheadline).bold()
                Text("Chạm để chỉnh sửa lời thoại tiếng Việt trước khi render.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Mở Studio") {
                showSubtitleStudio = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // Thẻ theo dõi tiến trình %
    var progressTrackerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .padding(.trailing, 4)
                Text(progressStage)
                    .font(.subheadline).bold()
                Spacer()
                Text("\(progressPercent)%")
                    .font(.subheadline).bold().foregroundColor(.blue)
            }
            ProgressView(value: Double(progressPercent), total: 100)
                .accentColor(.blue)
            Text(progressMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // Modal Studio chỉnh sửa phụ đề
    var subtitleStudioSheet: some View {
        NavigationView {
            List {
                ForEach($cues) { $cue in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("[\(cue.timeFormatted)]")
                                .font(.caption).bold().foregroundColor(.blue)
                            Spacer()
                            Button(action: {
                                APIManager.shared.playTTSPreview(serverURL: serverURL, text: cue.translated_text, voiceID: selectedVoice)
                            }) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        Text(cue.original_text)
                            .font(.caption).foregroundColor(.secondary)
                        TextField("Câu dịch tiếng Việt", text: $cue.translated_text)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Studio Biên Tập Phụ Đề")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showSubtitleStudio = false }
                }
            }
        }
    }

    // Cài đặt địa chỉ Server
    var serverSettingsView: some View {
        Form {
            Section(header: Text("Địa chỉ VPS")) {
                TextField("Server URL", text: $serverURL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("Cài Đặt")
    }

    // Tải Video vào bộ nhớ tạm
    func loadSelectedVideo(_ item: PhotosPickerItem?) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("input_video.mp4")
                try? data.write(to: tempURL)
                DispatchQueue.main.async {
                    selectedVideoURL = tempURL
                    player = AVPlayer(url: tempURL)
                    let asset = AVAsset(url: tempURL)
                    Task {
                        if let dur = try? await asset.load(.duration) {
                            let sec = CMTimeGetSeconds(dur)
                            DispatchQueue.main.async {
                                videoDuration = sec
                                trimStart = 0.0
                                trimEnd = sec
                            }
                        }
                    }
                }
            }
        }
    }

    // Bắt đầu quy trình biên tập và xuất video
    func startExportTask() {
        guard let vidURL = selectedVideoURL else { return }
        isProcessing = true
        progressPercent = 5
        progressStage = "Đang tải video lên VPS"
        progressMessage = "Đang chuẩn bị gửi file đến máy chủ..."

        let mask = enableMask ? MaskRect(x: 0.02, y: Double(maskYRatio), w: 0.96, h: Double(maskHeightRatio), style: maskStyle) : nil

        APIManager.shared.createTask(
            serverURL: serverURL,
            videoURL: vidURL,
            voiceID: selectedVoice,
            genre: selectedGenre,
            trimStart: trimStart,
            trimEnd: trimEnd,
            maskRect: mask,
            dubVolume: dubVolume,
            origVolume: origVolume,
            cues: cues.isEmpty ? nil : cues
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let taskId):
                    currentTaskId = taskId
                    startPollingProgress()
                case .failure(let err):
                    isProcessing = false
                    alertMessage = "Lỗi khởi tạo: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    // Vòng lặp lấy % tiến trình
    func startPollingProgress() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            APIManager.shared.pollTaskStatus(serverURL: serverURL, taskId: currentTaskId) { res in
                DispatchQueue.main.async {
                    switch res {
                    case .success(let status):
                        progressPercent = status.percent ?? progressPercent
                        progressStage = status.stage ?? progressStage
                        progressMessage = status.msg ?? progressMessage

                        if let fetchedCues = status.cues, cues.isEmpty {
                            cues = fetchedCues
                        }

                        if status.status == "completed" {
                            timer?.invalidate()
                            downloadFinalVideo()
                        } else if status.status == "failed" {
                            timer?.invalidate()
                            isProcessing = false
                            alertMessage = "Lỗi xử lý: \(status.error ?? "Không rõ nguyên nhân")"
                            showAlert = true
                        }
                    case .failure:
                        break
                    }
                }
            }
        }
    }

    // Tải video kết quả
    func downloadFinalVideo() {
        progressStage = "Đang tải video thành phẩm về iPhone..."
        APIManager.shared.downloadResultVideo(serverURL: serverURL, taskId: currentTaskId) { res in
            DispatchQueue.main.async {
                isProcessing = false
                switch res {
                case .success(let fileURL):
                    outputVideoURL = fileURL
                    resultPlayer = AVPlayer(url: fileURL)
                    alertMessage = "🎉 Video đã dịch và biên tập hoàn tất!"
                    showAlert = true
                case .failure(let err):
                    alertMessage = "Lỗi tải video: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    // Lưu vào Album ảnh
    func saveToPhotoLibrary() {
        guard let url = outputVideoURL else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                alertMessage = success ? "Đã lưu video thành công vào Photos!" : "Lỗi lưu: \(error?.localizedDescription ?? "")"
                showAlert = true
            }
        }
    }
}
