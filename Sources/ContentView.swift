import SwiftUI
import PhotosUI
import AVKit

// MARK: - Haptic Feedback Helper
public struct Haptic {
    public static func play(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Share Sheet Helper (UIActivityViewController)
public struct ShareSheet: UIViewControllerRepresentable {
    public var items: [Any]
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public struct ContentView: View {
    @AppStorage("server_url") private var serverURL: String = "http://103.211.206.176:9005"

    // Project Session
    @State private var projectId: String = ""
    @State private var currentStep: Int = 1 // 1: Mask/Logo -> 2: STT -> 3: Translate -> 4: TTS -> 5: Mix & Export

    // Video State
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var videoDuration: Double = 60.0
    @State private var videoAspectRatio: CGFloat = 9.0 / 16.0
    @State private var isLoadingVideo: Bool = false
    @State private var timeObserverToken: Any? = nil
    @State private var showMaskOverlay: Bool = true

    // CÔNG ĐOẠN 1: Làm mờ phụ đề & làm mờ logo
    @State private var enableMaskSub: Bool = true
    @State private var maskSubYRatio: CGFloat = 0.82
    @State private var maskSubHeightRatio: CGFloat = 0.12
    @State private var maskSubStyle: String = "box_semi" // box_semi, box_black, delogo

    @State private var enableMaskLogo: Bool = false
    @State private var logoXRatio: CGFloat = 0.74
    @State private var logoYRatio: CGFloat = 0.05
    @State private var logoWidthRatio: CGFloat = 0.22
    @State private var logoHeightRatio: CGFloat = 0.08

    // CÔNG ĐOẠN 2: Bóc tách SRT (CapCut STT)
    @State private var sourceLang: String = "zh-CN"
    @State private var cues: [SubtitleCue] = []
    @State private var cueSearchQuery: String = ""
    @State private var isExtractingSTT: Bool = false

    // CÔNG ĐOẠN 3: Dịch SRT & Chỉnh sửa tùy chỉnh (AI Model)
    @AppStorage("selected_translation_model") private var selectedModel: String = "dsk/deepseek-chat"
    @State private var availableModels: [TranslationModel] = [
        TranslationModel(id: "dsk/deepseek-chat", name: "DeepSeek V3 (9Router / DsApiCli - Siêu Tốc)", provider: "DeepSeek", is_default: true),
        TranslationModel(id: "dsk/deepseek-reasoner", name: "DeepSeek R1 (9Router / DsApiCli - Suy Luận)", provider: "DeepSeek"),
        TranslationModel(id: "cd/gpt-4o", name: "GPT-4o (Codex)", provider: "Codex"),
        TranslationModel(id: "cd/gpt-5", name: "GPT-5 (Codex)", provider: "Codex"),
        TranslationModel(id: "cd/gpt-6-astra", name: "GPT-6 Astra (Codex)", provider: "Codex"),
        TranslationModel(id: "cd/o3-mini", name: "o3-mini (Codex)", provider: "Codex")
    ]
    @State private var isFetchingModels: Bool = false
    @State private var showModelPickerSheet: Bool = false
    @State private var selectedGenre: String = "phim_chung"
    @State private var isTranslating: Bool = false

    // CÔNG ĐOẠN 4: Chuyển thành âm thanh (CapCut TTS)
    @State private var selectedVoice: String = "BV421_vivn_streaming"
    @State private var isGeneratingTTS: Bool = false
    @State private var ttsReady: Bool = false
    @State private var selectedVoiceCategory: String = "Tất Cả"
    @State private var voiceSearchQuery: String = ""

    // CÔNG ĐOẠN 5 & 6: Ghép vào video, chỉnh sửa tùy chỉnh & xuất
    @State private var dubVolume: Double = 1.0
    @State private var origVolume: Double = 0.12
    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 60.0
    @State private var isRendering: Bool = false
    @State private var outputVideoURL: URL? = nil
    @State private var resultPlayer: AVPlayer? = nil
    @State private var renderPreset: String = "ultrafast" // "ultrafast" or "veryfast"
    @State private var lastRenderTimeSec: Double = 0.0
    @State private var lastSpeedRatio: Double = 0.0
    @State private var renderElapsedSeconds: Int = 0
    @State private var renderTimerToken: Timer? = nil
    @AppStorage("always_keep_screen_awake") private var alwaysKeepScreenAwake: Bool = true

    // Thông báo, Sheets & Settings
    @State private var showSettingsModal: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false

    // Server test status
    @State private var isTestingServer: Bool = false
    @State private var serverStatusText: String = ""
    @State private var isServerConnected: Bool = true

    let voiceCategories = ["Tất Cả", "Review Phim", "Giọng Nam", "Giọng Nữ", "Bản Tin", "Độc Lạ / Hài"]

    var filteredVoices: [VoiceItem] {
        VoiceCatalog.allVietnameseVoices.filter { v in
            let matchesCat = (selectedVoiceCategory == "Tất Cả") || (v.category == selectedVoiceCategory)
            let q = voiceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = q.isEmpty ||
                v.name.localizedCaseInsensitiveContains(q) ||
                v.category.localizedCaseInsensitiveContains(q) ||
                v.gender.localizedCaseInsensitiveContains(q)
            return matchesCat && matchesSearch
        }
    }

    var currentVoiceItem: VoiceItem? {
        VoiceCatalog.allVietnameseVoices.first(where: { $0.id == selectedVoice })
    }

    var currentModelItem: TranslationModel? {
        availableModels.first(where: { $0.id == selectedModel })
    }

    var filteredCues: [SubtitleCue] {
        if cueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cues
        }
        let q = cueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return cues.filter {
            $0.original_text.localizedCaseInsensitiveContains(q) ||
            $0.translated_text.localizedCaseInsensitiveContains(q)
        }
    }

    func categoryBadgeColor(_ cat: String) -> Color {
        switch cat {
        case "Review Phim": return Color(hex: "A855F7")
        case "Giọng Nam": return Color(hex: "3B82F6")
        case "Giọng Nữ": return Color(hex: "EC4899")
        case "Bản Tin": return Color(hex: "F97316")
        case "Độc Lạ / Hài": return Color(hex: "EAB308")
        default: return Color(hex: "00ADB5")
        }
    }

    let genres = [
        ("phim_chung", "Đời thường / TikTok", "flame.fill"),
        ("kiem_hiep", "Cổ trang / Kiếm hiệp", "shield.fill"),
        ("tong_tai", "Tổng tài / Ngôn tình", "crown.fill"),
        ("hai_huoc", "Hài hước / Bắt trend", "face.smiling.fill"),
        ("kinh_di", "Kinh dị / Giật gân", "theatermasks.fill")
    ]

    public var body: some View {
        ZStack {
            Color(hex: "0B0E14").ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar
                topNavigationBar

                if selectedVideoURL == nil {
                    // Màn hình khởi tạo Studio đẳng cấp
                    emptyStudioState
                } else {
                    // Thanh điều hướng 5 Công Đoạn
                    stepProgressBar
                        .padding(.vertical, 8)
                        .background(Color(hex: "121722"))

                    // Trình phát video chuyên nghiệp kèm Mask Layer
                    videoCanvasViewport
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.32)
                        .background(Color.black)

                    Divider().background(Color(hex: "1F2738"))

                    // Nội dung từng công đoạn theo bước
                    ScrollView {
                        VStack(spacing: 16) {
                            switch currentStep {
                            case 1:
                                step1MaskView
                            case 2:
                                step2STTView
                            case 3:
                                step3TranslateView
                            case 4:
                                step4TTSView
                            case 5:
                                step5MixAndExportView
                            default:
                                step1MaskView
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(hex: "0E121B"))
                }
            }

            // Toast thông báo nổi nhẹ
            if showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "00ADB5"))
                        Text(toastMessage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "1C2433").opacity(0.95))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "00ADB5").opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: showToast)
            }

            // Loading Overlay khi đang xử lý
            if isExtractingSTT || isTranslating || isGeneratingTTS || isRendering || isLoadingVideo {
                loadingOverlayView
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettingsModal) {
            serverSettingsModal
        }
        .sheet(isPresented: $showShareSheet) {
            if let out = outputVideoURL {
                ShareSheet(items: [out])
            }
        }
        .sheet(isPresented: $showModelPickerSheet) {
            modelPickerSheetView
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông Báo"), message: Text(alertMessage), dismissButton: .default(Text("Đóng")))
        }
        .confirmationDialog("Bạn có chắc muốn đổi video mới? Dữ liệu công đoạn hiện tại sẽ được làm mới.", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Đổi Video Mới", role: .destructive) {
                resetProject()
            }
            Button("Hủy", role: .cancel) {}
        }
        .onAppear {
            updateScreenIdleTimer()
            fetchModelsFromServer(isManual: false)
        }
        .onChange(of: serverURL) { _ in
            fetchModelsFromServer(isManual: false)
        }
        .onChange(of: isExtractingSTT) { _ in updateScreenIdleTimer() }
        .onChange(of: isTranslating) { _ in updateScreenIdleTimer() }
        .onChange(of: isGeneratingTTS) { _ in updateScreenIdleTimer() }
        .onChange(of: isRendering) { _ in updateScreenIdleTimer() }
        .onChange(of: isLoadingVideo) { _ in updateScreenIdleTimer() }
        .onChange(of: alwaysKeepScreenAwake) { _ in updateScreenIdleTimer() }
        .onChange(of: selectedVoice) { _ in ttsReady = false }
    }

    // MARK: - Top Navigation Bar
    var topNavigationBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }

                Text("DUB STUDIO")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("PRO")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(4)
            }

            Spacer()

            if selectedVideoURL != nil {
                Button(action: { showResetConfirm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Đổi Video")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "1C2433"))
                    .foregroundColor(Color(hex: "CBD5E1"))
                    .cornerRadius(8)
                }
            }

            Button(action: {
                Haptic.play(.light)
                showSettingsModal = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "8D99AE"))
                    .padding(8)
                    .background(Color(hex: "1A2230"))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "121722"))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: "1F2738")), alignment: .bottom)
    }

    // MARK: - Thanh Tiến Trình Tách Từng Công Đoạn (5 Bước)
    var stepProgressBar: some View {
        HStack(spacing: 4) {
            stepBadge(step: 1, title: "Che Sub/Logo", icon: "square.dashed")
            stepArrow
            stepBadge(step: 2, title: "Tách SRT", icon: "doc.text.fill")
            stepArrow
            stepBadge(step: 3, title: "Dịch AI", icon: "character.book.closed.fill")
            stepArrow
            stepBadge(step: 4, title: "Lồng Tiếng", icon: "mic.fill")
            stepArrow
            stepBadge(step: 5, title: "Ghép & Xuất", icon: "square.and.arrow.up.fill")
        }
        .padding(.horizontal, 10)
    }

    func stepBadge(step: Int, title: String, icon: String) -> some View {
        let isDone = (step < currentStep) || (step == 2 && !cues.isEmpty) || (step == 3 && cues.contains(where: { !$0.translated_text.isEmpty })) || (step == 4 && ttsReady) || (step == 5 && outputVideoURL != nil)
        let isActive = currentStep == step

        return Button(action: {
            Haptic.play(.light)
            if step <= currentStep || (step == 2 && !projectId.isEmpty) || (step == 3 && !cues.isEmpty) || (step == 4 && !cues.isEmpty) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentStep = step
                }
            }
        }) {
            VStack(spacing: 3) {
                ZStack {
                    if isDone && !isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "10B981"))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: isActive ? .bold : .medium))
                            .foregroundColor(isActive ? Color(hex: "00ADB5") : Color(hex: "64748B"))
                    }
                }
                Text(title)
                    .font(.system(size: 9, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .white : (isDone ? Color(hex: "CBD5E1") : Color(hex: "64748B")))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isActive ? Color(hex: "00ADB5").opacity(0.16) : Color.clear)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? Color(hex: "00ADB5").opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }

    var stepArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(Color(hex: "334155"))
    }

    // MARK: - Video Canvas Viewport với Vùng Che Sub & Logo
    var videoCanvasViewport: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Color.black

                if let p = player {
                    VideoPlayer(player: p)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                }

                if showMaskOverlay {
                    // 1. Hộp Vùng Che Sub Gốc (Kéo thả trực tiếp)
                    if enableMaskSub {
                        let boxH = geo.size.height * maskSubHeightRatio
                        let boxY = geo.size.height * maskSubYRatio

                        ZStack {
                            Rectangle()
                                .fill(maskSubStyle == "box_black" ? Color.black : Color.black.opacity(0.75))
                                .overlay(
                                    VStack(spacing: 2) {
                                        Text("VÙNG CHE PHỤ ĐỀ GỐC")
                                            .font(.system(size: 10, weight: .heavy))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                        Text("Kéo để chỉnh vị trí Y: \(Int(maskSubYRatio * 100))%")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                )
                                .border(Color(hex: "00ADB5"), width: 1.5)
                        }
                        .frame(width: geo.size.width * 0.94, height: boxH)
                        .position(x: geo.size.width / 2, y: boxY + boxH / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    let newY = (val.location.y - boxH / 2) / geo.size.height
                                    maskSubYRatio = max(0.05, min(0.90, newY))
                                }
                        )
                    }

                    // 2. Hộp Vùng Che Logo (Kéo thả trực tiếp)
                    if enableMaskLogo {
                        let logoW = geo.size.width * logoWidthRatio
                        let logoH = geo.size.height * logoHeightRatio
                        let logoX = geo.size.width * logoXRatio
                        let logoY = geo.size.height * logoYRatio

                        ZStack {
                            Rectangle()
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    VStack(spacing: 1) {
                                        Text("LOGO")
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundColor(.yellow)
                                    }
                                )
                                .border(Color.yellow, width: 1.5)
                        }
                        .frame(width: logoW, height: logoH)
                        .position(x: logoX + logoW / 2, y: logoY + logoH / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    logoXRatio = max(0.0, min(0.85, (val.location.x - logoW / 2) / geo.size.width))
                                    logoYRatio = max(0.0, min(0.85, (val.location.y - logoH / 2) / geo.size.height))
                                }
                        )
                    }
                }

                // Video Control Bar Overlay dưới đáy viewport
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        // Tua lùi 5s
                        Button(action: { seekBy(seconds: -5) }) {
                            Image(systemName: "gobackward.5")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }

                        // Nút Play / Pause
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "00ADB5"))
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                        }

                        // Tua tới 5s
                        Button(action: { seekBy(seconds: 5) }) {
                            Image(systemName: "goforward.5")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }

                        // Mốc thời gian
                        Text(String(format: "%02d:%02d / %02d:%02d", Int(currentTime) / 60, Int(currentTime) % 60, Int(videoDuration) / 60, Int(videoDuration) % 60))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)

                        Spacer()

                        // Toggle hiển thị khung mask để preview mượt
                        Button(action: { showMaskOverlay.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showMaskOverlay ? "eye.fill" : "eye.slash.fill")
                                Text(showMaskOverlay ? "Ẩn Mask" : "Hiện Mask")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(showMaskOverlay ? Color(hex: "00ADB5") : Color(hex: "94A3B8"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                        }
                    }
                    .padding(8)
                    .background(LinearGradient(colors: [Color.clear, Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 1: Làm mờ phụ đề & làm mờ logo
    var step1MaskView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "1", title: "Làm Mờ Phụ Đề & Xóa Logo", desc: "Tự động che phủ phụ đề gốc và watermark góc video bằng FFmpeg.")

            // 1. Tùy chọn che phụ đề
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Bật Che / Làm Mờ Phụ Đề Gốc", isOn: $enableMaskSub)
                        .font(.system(size: 14, weight: .bold))
                }

                if enableMaskSub {
                    // Kiểu che
                    Picker("Kiểu che", selection: $maskSubStyle) {
                        Text("Mờ Bán Trong Suốt").tag("box_semi")
                        Text("Đen Tuyền").tag("box_black")
                        Text("Xóa Mờ (Delogo)").tag("delogo")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    // Nút Presets nhanh cho vị trí sub
                    HStack(spacing: 8) {
                        Text("Cài nhanh:")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "8D99AE"))
                        Button("Đáy video (82%)") {
                            maskSubYRatio = 0.82
                            maskSubHeightRatio = 0.12
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(Color(hex: "00ADB5"))
                        .cornerRadius(6)

                        Button("Gần đáy (75%)") {
                            maskSubYRatio = 0.75
                            maskSubHeightRatio = 0.14
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(Color(hex: "00ADB5"))
                        .cornerRadius(6)

                        Button("Giữa (50%)") {
                            maskSubYRatio = 0.50
                            maskSubHeightRatio = 0.14
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(Color(hex: "00ADB5"))
                        .cornerRadius(6)
                    }

                    // Tinh chỉnh Y
                    VStack(spacing: 4) {
                        HStack {
                            Text("Vị trí theo chiều dọc (Y):")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "8D99AE"))
                            Spacer()
                            Text("\(Int(maskSubYRatio * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "00ADB5"))
                        }
                        Slider(value: Binding(get: { Double(maskSubYRatio) }, set: { maskSubYRatio = CGFloat($0) }), in: 0.15...0.90)
                            .accentColor(Color(hex: "00ADB5"))
                    }

                    // Tinh chỉnh Chiều cao hộp
                    VStack(spacing: 4) {
                        HStack {
                            Text("Chiều cao hộp che:")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "8D99AE"))
                            Spacer()
                            Text("\(Int(maskSubHeightRatio * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "00ADB5"))
                        }
                        Slider(value: Binding(get: { Double(maskSubHeightRatio) }, set: { maskSubHeightRatio = CGFloat($0) }), in: 0.05...0.25)
                            .accentColor(Color(hex: "00ADB5"))
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "141A26"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // 2. Tùy chọn che Logo
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Bật Xóa / Làm Mờ Logo (Watermark)", isOn: $enableMaskLogo)
                    .font(.system(size: 14, weight: .bold))

                if enableMaskLogo {
                    // Presets vị trí góc logo
                    HStack(spacing: 8) {
                        Text("Vị trí góc:")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "8D99AE"))
                        Button("Trên Phải") {
                            logoXRatio = 0.74; logoYRatio = 0.05
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(.yellow)
                        .cornerRadius(6)

                        Button("Trên Trái") {
                            logoXRatio = 0.04; logoYRatio = 0.05
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(.yellow)
                        .cornerRadius(6)

                        Button("Dưới Phải") {
                            logoXRatio = 0.74; logoYRatio = 0.88
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "1F2738"))
                        .foregroundColor(.yellow)
                        .cornerRadius(6)
                    }

                    Text("💡 Bạn có thể kéo thả trực tiếp hộp màu vàng trên màn hình video.")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
            .padding(14)
            .background(Color(hex: "141A26"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // Nút chuyển sang Bước 2
            Button(action: {
                Haptic.play(.medium)
                if projectId.isEmpty {
                    uploadAndProceedToSTT()
                } else {
                    currentStep = 2
                }
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    Text("Xác Nhận & Sang Bước 2: Bóc Tách SRT")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "0284C7")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.black)
                .cornerRadius(12)
                .shadow(color: Color(hex: "00ADB5").opacity(0.3), radius: 6, y: 3)
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 2: Bóc tách SRT (CapCut STT)
    var step2STTView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "2", title: "Chuyển Văn Bản Thành SRT", desc: "CapCut Cloud STT AI bóc tách giọng nói chính xác thành câu thoại kèm timestamp.")

            HStack {
                Text("Ngôn ngữ giọng nói trong video:")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "8D99AE"))
                Spacer()
                Picker("Ngôn ngữ", selection: $sourceLang) {
                    Text("Tiếng Trung (zh-CN)").tag("zh-CN")
                    Text("Tiếng Anh (en-US)").tag("en-US")
                    Text("Tiếng Việt (vi-VN)").tag("vi-VN")
                    Text("Tiếng Nhật (ja-JP)").tag("ja-JP")
                    Text("Tiếng Hàn (ko-KR)").tag("ko-KR")
                }
                .accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141A26"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            if cues.isEmpty {
                Button(action: {
                    Haptic.play(.medium)
                    runSTT()
                }) {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 16))
                        Text("Bắt Đầu Bóc Tách SRT (CapCut STT)")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "10B981"))
                            Text("Đã tách \(cues.count) câu thoại")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Button(action: copyAllOriginalSRT) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Sao Chép")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "00ADB5"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "1F2738"))
                            .cornerRadius(6)
                        }

                        Button("Quét Lại") {
                            Haptic.play(.light)
                            runSTT()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "8D99AE"))
                    }

                    // Ô tìm kiếm câu thoại
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(hex: "8D99AE"))
                        TextField("Tìm câu thoại gốc...", text: $cueSearchQuery)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        if !cueSearchQuery.isEmpty {
                            Button(action: { cueSearchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(hex: "8D99AE"))
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(hex: "10141E"))
                    .cornerRadius(8)

                    // Danh sách câu thoại gốc
                    LazyVStack(spacing: 6) {
                        ForEach(filteredCues) { cue in
                            HStack(alignment: .top, spacing: 8) {
                                Text("[\(cue.timeFormatted)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "00ADB5"))
                                    .padding(.top, 2)
                                Text(cue.original_text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(hex: "161C28"))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(Color(hex: "141A26"))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

                Button(action: {
                    Haptic.play(.medium)
                    currentStep = 3
                }) {
                    HStack(spacing: 8) {
                        Spacer()
                        Text("Sang Bước 3: Dịch SRT Bằng 9Router AI")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "0284C7")], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 3: Dịch SRT & Chỉnh sửa tùy chỉnh
    var step3TranslateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "3", title: "Dịch SRT & Chỉnh Sửa Tùy Chỉnh", desc: "Dịch AI theo văn phong điện ảnh chuyên nghiệp. Bạn có thể chọn model và sửa câu từ trực tiếp.")

            // Chọn Model AI Dịch Thuật
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("MODEL AI DỊCH THUẬT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "8D99AE"))
                        .tracking(0.5)

                    Spacer()

                    Button(action: {
                        Haptic.play(.light)
                        fetchModelsFromServer(isManual: true)
                    }) {
                        HStack(spacing: 4) {
                            if isFetchingModels {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(Color(hex: "00ADB5"))
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(isFetchingModels ? "Đang tải..." : "Cập nhật từ Server")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "00ADB5"))
                    }
                }

                Button(action: {
                    Haptic.play(.light)
                    showModelPickerSheet = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "00ADB5"))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: "1A2B38"))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(currentModelItem?.name ?? selectedModel)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Spacer()

                                if let p = currentModelItem?.provider {
                                    Text(p)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(p == "DeepSeek" ? Color(hex: "00ADB5").opacity(0.2) : Color(hex: "A855F7").opacity(0.2))
                                        .foregroundColor(p == "DeepSeek" ? Color(hex: "00ADB5") : Color(hex: "A855F7"))
                                        .cornerRadius(4)
                                }
                            }

                            Text("Mã model: \(selectedModel)")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "8D99AE"))
                                .lineLimit(1)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "8D99AE"))
                    }
                    .padding(12)
                    .background(Color(hex: "182030"))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "263248"), lineWidth: 1))
                }
            }
            .padding(14)
            .background(Color(hex: "141A26"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // Chọn văn phong dịch
            VStack(alignment: .leading, spacing: 8) {
                Text("CHỌN VĂN PHONG DỊCH THUẬT PHÙ HỢP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "8D99AE"))
                    .tracking(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.0) { g in
                            Button(action: {
                                Haptic.play(.light)
                                selectedGenre = g.0
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: g.2)
                                        .font(.system(size: 12))
                                        .foregroundColor(selectedGenre == g.0 ? Color(hex: "00ADB5") : Color(hex: "8D99AE"))
                                    Text(g.1)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(selectedGenre == g.0 ? .white : Color(hex: "8D99AE"))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedGenre == g.0 ? Color(hex: "1A2B38") : Color(hex: "141A26"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedGenre == g.0 ? Color(hex: "00ADB5") : Color(hex: "1F2738"), lineWidth: 1.2))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "141A26"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            Button(action: {
                Haptic.play(.medium)
                runTranslate()
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                    Text("Dịch Sang Tiếng Việt (\(currentModelItem?.provider ?? "AI"))")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color(hex: "3B82F6"), Color(hex: "6366F1")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color(hex: "3B82F6").opacity(0.3), radius: 6, y: 3)
            }

            // Danh sách chỉnh sửa tùy chỉnh
            if !cues.isEmpty && cues.contains(where: { !$0.translated_text.isEmpty }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("BẢNG CHỈNH SỬA TÙY CHỈNH (\(cues.count) CÂU)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "8D99AE"))

                        Spacer()

                        Button(action: copyAllTranslatedText) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Sao Chép Bản Dịch")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "00ADB5"))
                        }
                    }

                    LazyVStack(spacing: 10) {
                        ForEach($cues) { $cue in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("[\(cue.timeFormatted)]")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "00ADB5"))
                                    Text(cue.original_text)
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "8D99AE"))
                                        .lineLimit(1)
                                    Spacer()

                                    // Nút nghe thử trực tiếp câu này
                                    Button(action: {
                                        Haptic.play(.light)
                                        APIManager.shared.playTTSPreview(
                                            serverURL: serverURL,
                                            text: cue.translated_text,
                                            voiceID: selectedVoice
                                        )
                                    }) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                            .padding(6)
                                            .background(Color(hex: "1F2738"))
                                            .clipShape(Circle())
                                    }
                                }

                                TextField("Câu dịch tiếng Việt", text: $cue.translated_text)
                                    .font(.system(size: 13))
                                    .padding(9)
                                    .background(Color(hex: "1A2230"))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            .padding(10)
                            .background(Color(hex: "121722"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "1F2738"), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
                .background(Color(hex: "141A26"))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

                Button(action: {
                    Haptic.play(.medium)
                    currentStep = 4
                }) {
                    HStack(spacing: 8) {
                        Spacer()
                        Text("Sang Bước 4: Chuyển Thành Âm Thanh")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "0284C7")], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 4: Chuyển thành âm thanh (CapCut TTS)
    var step4TTSView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "4", title: "Chuyển Văn Bản Thành Âm Thanh", desc: "Thư viện 24 giọng đọc CapCut AI Việt Nam (Review Phim, Thời Sự, Độc Lạ...).")

            // Selected Voice Preview Banner
            if let cur = currentVoiceItem {
                HStack(spacing: 12) {
                    Image(systemName: cur.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "00ADB5"))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: "00ADB5").opacity(0.18))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(cur.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(cur.gender)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(cur.gender == "Nam" ? Color.blue.opacity(0.3) : Color.pink.opacity(0.3))
                                .foregroundColor(cur.gender == "Nam" ? Color.blue : Color.pink)
                                .cornerRadius(4)
                        }
                        Text("Thể loại: \(cur.category)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "8D99AE"))
                    }

                    Spacer()

                    Button(action: {
                        Haptic.play(.light)
                        APIManager.shared.playTTSPreview(
                            serverURL: serverURL,
                            text: "Xin chào! Đây là bản nghe thử giọng \(cur.name).",
                            voiceID: cur.id
                        )
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Nghe thử")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "00ADB5"))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(Color(hex: "1A2333"))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "00ADB5"), lineWidth: 1.5))
            }

            // Search Bar & Filter Section
            VStack(spacing: 10) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(hex: "8D99AE"))
                    TextField("Tìm theo tên, thể loại (vd: Review, Nam, Nữ)...", text: $voiceSearchQuery)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    if !voiceSearchQuery.isEmpty {
                        Button(action: { voiceSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(hex: "8D99AE"))
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "121722"))
                .cornerRadius(10)

                // Category Chips ScrollView
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(voiceCategories, id: \.self) { cat in
                            Button(action: {
                                Haptic.play(.light)
                                selectedVoiceCategory = cat
                            }) {
                                HStack(spacing: 4) {
                                    if cat == "Review Phim" {
                                        Image(systemName: "film.fill")
                                    } else if cat == "Giọng Nam" {
                                        Image(systemName: "person.fill")
                                    } else if cat == "Giọng Nữ" {
                                        Image(systemName: "sparkles")
                                    } else if cat == "Bản Tin" {
                                        Image(systemName: "newspaper.fill")
                                    } else if cat == "Độc Lạ / Hài" {
                                        Image(systemName: "theatermasks.fill")
                                    }
                                    Text(cat)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selectedVoiceCategory == cat ? Color(hex: "00ADB5") : Color(hex: "1A2230"))
                                .foregroundColor(selectedVoiceCategory == cat ? .black : Color(hex: "E0E6ED"))
                                .cornerRadius(16)
                            }
                        }
                    }
                }
            }

            // Voice List (Filtered)
            Text("Danh Sách Giọng Đọc (\(filteredVoices.count)/24)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "8D99AE"))

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredVoices) { v in
                        HStack(spacing: 12) {
                            Button(action: {
                                Haptic.play(.light)
                                selectedVoice = v.id
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: v.iconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(selectedVoice == v.id ? Color(hex: "00ADB5") : .white)
                                        .frame(width: 34, height: 34)
                                        .background(selectedVoice == v.id ? Color(hex: "00ADB5").opacity(0.18) : Color(hex: "1E2433"))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(v.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text(v.category)
                                                .font(.system(size: 10, weight: .medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(categoryBadgeColor(v.category).opacity(0.2))
                                                .foregroundColor(categoryBadgeColor(v.category))
                                                .cornerRadius(4)
                                            Text(v.gender)
                                                .font(.system(size: 10))
                                                .foregroundColor(Color(hex: "8D99AE"))
                                        }
                                    }
                                    Spacer()
                                    if selectedVoice == v.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Preview button
                            Button(action: {
                                Haptic.play(.light)
                                APIManager.shared.playTTSPreview(
                                    serverURL: serverURL,
                                    text: "Xin chào! Đây là bản nghe thử giọng \(v.name).",
                                    voiceID: v.id
                                )
                            }) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "00ADB5"))
                                    .padding(8)
                                    .background(Color(hex: "1F2738"))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(10)
                        .background(selectedVoice == v.id ? Color(hex: "16222F") : Color(hex: "141824"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedVoice == v.id ? Color(hex: "00ADB5") : Color(hex: "232B3E"), lineWidth: 1.2))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)

            Button(action: {
                Haptic.play(.medium)
                runTTS()
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    if isGeneratingTTS {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "waveform.and.mic")
                    }
                    Text(isGeneratingTTS ? "Đang Tạo Giọng Đọc..." : "Tạo Giọng Đọc Lồng Tiếng (CapCut TTS)")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(isGeneratingTTS ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isGeneratingTTS)

            if ttsReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ Giọng đọc đã sẵn sàng! Bạn có thể bấm loa nghe thử:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "10B981"))

                    LazyVStack(spacing: 6) {
                        ForEach(cues) { cue in
                            HStack {
                                Text("[\(cue.timeFormatted)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "00ADB5"))
                                Text(cue.translated_text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    Haptic.play(.light)
                                    APIManager.shared.playTTSPreview(serverURL: serverURL, text: cue.translated_text, voiceID: selectedVoice)
                                }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(Color(hex: "00ADB5"))
                                        .padding(6)
                                        .background(Color(hex: "1E2433"))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(8)
                            .background(Color(hex: "161A26"))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)

                Button(action: {
                    Haptic.play(.medium)
                    currentStep = 5
                }) {
                    HStack(spacing: 8) {
                        Spacer()
                        Text("Sang Bước 5: Ghép Video & Xuất File")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "0284C7")], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 5 & 6: Ghép vào video, chỉnh sửa tùy chỉnh & xuất
    var step5MixAndExportView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "5", title: "Ghép Vào Video, Tùy Chỉnh & Xuất", desc: "Cân chỉnh âm lượng lồng tiếng, dìm âm video gốc và render hoàn thiện.")

            // Cắt đoạn video (Trim)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .foregroundColor(Color(hex: "00ADB5"))
                        Text("Cắt đoạn video (Trim):")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Spacer()
                    Text(String(format: "%02d:%02d - %02d:%02d", Int(trimStart) / 60, Int(trimStart) % 60, Int(trimEnd) / 60, Int(trimEnd) % 60))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00ADB5"))

                    Button("Đặt lại") {
                        trimStart = 0.0
                        trimEnd = videoDuration
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "8D99AE"))
                }

                Slider(value: $trimStart, in: 0...max(1.0, trimEnd - 1.0))
                    .accentColor(Color(hex: "00ADB5"))
                Slider(value: $trimEnd, in: min(videoDuration, trimStart + 1.0)...videoDuration)
                    .accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // Bộ cân bằng âm thanh (Sound Mixer)
            VStack(alignment: .leading, spacing: 14) {
                // Giọng đọc lồng tiếng
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(Color(hex: "00ADB5"))
                        Text("Âm lượng giọng đọc lồng tiếng:")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(Int(dubVolume * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00ADB5"))
                    }
                    Slider(value: $dubVolume, in: 0.2...2.0).accentColor(Color(hex: "00ADB5"))
                    HStack(spacing: 8) {
                        Button("100% (Chuẩn)") { dubVolume = 1.0 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Button("130% (Rõ nét)") { dubVolume = 1.3 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Button("160% (Lớn)") { dubVolume = 1.6 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Spacer()
                    }
                }

                Divider().background(Color(hex: "232B3E"))

                // Dìm âm nền video gốc
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "speaker.wave.1.fill")
                            .foregroundColor(Color(hex: "8D99AE"))
                        Text("Dìm âm thanh video gốc (Ducking):")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(Int(origVolume * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00ADB5"))
                    }
                    Slider(value: $origVolume, in: 0.0...0.5).accentColor(Color(hex: "00ADB5"))
                    HStack(spacing: 8) {
                        Button("0% (Tắt tiếng gốc)") { origVolume = 0.0 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Button("10% (Nhẹ nhàng)") { origVolume = 0.10 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Button("20% (Tiêu chuẩn)") { origVolume = 0.20 }
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(hex: "1F2738")).foregroundColor(.white).cornerRadius(4)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // Tùy chọn tốc độ Render Video
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Color(hex: "00ADB5"))
                    Text("Tùy Chọn Tốc Độ Render Video")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    Button(action: {
                        renderPreset = "ultrafast"
                        Haptic.play(.light)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: renderPreset == "ultrafast" ? "bolt.circle.fill" : "circle")
                                .foregroundColor(renderPreset == "ultrafast" ? Color(hex: "00ADB5") : Color(hex: "8D99AE"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("⚡ Siêu Tốc (Ultrafast)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Nhanh gấp 3-4 lần, nét 1080p")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "8D99AE"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(renderPreset == "ultrafast" ? Color(hex: "00ADB5").opacity(0.18) : Color(hex: "1F2738"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(renderPreset == "ultrafast" ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        renderPreset = "veryfast"
                        Haptic.play(.light)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: renderPreset == "veryfast" ? "circle.fill" : "circle")
                                .foregroundColor(renderPreset == "veryfast" ? Color(hex: "00ADB5") : Color(hex: "8D99AE"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🎨 Tiêu Chuẩn (Veryfast)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Nén chuẩn CRF 23")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "8D99AE"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(renderPreset == "veryfast" ? Color(hex: "00ADB5").opacity(0.18) : Color(hex: "1F2738"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(renderPreset == "veryfast" ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "1F2738"), lineWidth: 1))

            // Nút Render Xuất Video Hoàn Thiện
            Button(action: {
                Haptic.play(.heavy)
                runRender()
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "film.fill")
                        .font(.system(size: 16))
                    Text("Render & Xuất Video Hoàn Thiện")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color(hex: "00ADB5").opacity(0.4), radius: 8, y: 3)
            }

            // Video thành phẩm
            if let outURL = outputVideoURL, let resP = resultPlayer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color(hex: "10B981"))
                        Text("🎬 VIDEO THÀNH PHẨM ĐÃ XUẤT XONG")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                    }

                    if lastRenderTimeSec > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .foregroundColor(Color(hex: "00ADB5"))
                            Text("Thời gian render: \(String(format: "%.1fs", lastRenderTimeSec))")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)

                            if lastSpeedRatio > 0 {
                                Text("• Tốc độ: \(String(format: "%.1fx", lastSpeedRatio))")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(Color(hex: "10B981"))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: "1F2738"))
                        .cornerRadius(8)
                    }

                    VideoPlayer(player: resP)
                        .frame(height: 220)
                        .cornerRadius(12)

                    HStack(spacing: 10) {
                        Button(action: saveToPhotoLibrary) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Lưu Vào Photos")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "10B981"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        Button(action: { showShareSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Chia Sẻ")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(hex: "1F2738"))
                            .foregroundColor(Color(hex: "00ADB5"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "00ADB5").opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "10B981").opacity(0.4), lineWidth: 1.5))
            }
        }
    }

    func stepHeader(stepNum: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CÔNG ĐOẠN \(stepNum)")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(Color(hex: "00ADB5"))
                .tracking(1.0)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "8D99AE"))
        }
    }

    // MARK: - Actions (Từng công đoạn)
    func uploadAndProceedToSTT() {
        guard let url = selectedVideoURL else { return }
        isExtractingSTT = true
        APIManager.shared.uploadVideo(serverURL: serverURL, videoURL: url) { res in
            DispatchQueue.main.async {
                isExtractingSTT = false
                switch res {
                case .success(let data):
                    if let pid = data["project_id"] as? String {
                        projectId = pid
                        currentStep = 2
                        showToastNotification("Tải video lên thành công!")
                    }
                case .failure(let err):
                    alertMessage = "Lỗi tải video: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func runSTT() {
        isExtractingSTT = true
        APIManager.shared.stepSTT(serverURL: serverURL, projectId: projectId, sourceLang: sourceLang) { res in
            DispatchQueue.main.async {
                isExtractingSTT = false
                switch res {
                case .success(let fetchedCues):
                    cues = fetchedCues
                    Haptic.notify(.success)
                    showToastNotification("Đã bóc tách \(fetchedCues.count) câu thoại!")
                case .failure(let err):
                    alertMessage = "Lỗi bóc tách SRT: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func fetchModelsFromServer(isManual: Bool = false) {
        if isFetchingModels { return }
        isFetchingModels = true
        APIManager.shared.fetchModels(serverURL: serverURL) { res in
            DispatchQueue.main.async {
                isFetchingModels = false
                switch res {
                case .success(let models):
                    if !models.isEmpty {
                        availableModels = models
                        if !models.contains(where: { $0.id == selectedModel }) {
                            if let def = models.first(where: { $0.is_default == true }) ?? models.first {
                                selectedModel = def.id
                            }
                        }
                        if isManual {
                            Haptic.notify(.success)
                            showToastNotification("Đã cập nhật \(models.count) model từ server!")
                        }
                    }
                case .failure(let err):
                    if isManual {
                        Haptic.notify(.error)
                        showToastNotification("Không thể lấy model: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    func runTranslate() {
        isTranslating = true
        APIManager.shared.stepTranslate(serverURL: serverURL, projectId: projectId, cues: cues, genre: selectedGenre, model: selectedModel) { res in
            DispatchQueue.main.async {
                isTranslating = false
                switch res {
                case .success(let translatedCues):
                    cues = translatedCues
                    Haptic.notify(.success)
                    showToastNotification("Dịch kịch bản hoàn tất!")
                case .failure(let err):
                    alertMessage = "Lỗi dịch SRT: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func runTTS() {
        isGeneratingTTS = true
        APIManager.shared.stepTTS(serverURL: serverURL, projectId: projectId, cues: cues, voiceId: selectedVoice) { res in
            DispatchQueue.main.async {
                isGeneratingTTS = false
                switch res {
                case .success:
                    ttsReady = true
                    Haptic.notify(.success)
                    showToastNotification("Đã tạo giọng đọc lồng tiếng!")
                case .failure(let err):
                    alertMessage = "Lỗi tạo giọng đọc: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func runRender() {
        isRendering = true
        renderElapsedSeconds = 0
        renderTimerToken?.invalidate()
        renderTimerToken = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            renderElapsedSeconds += 1
        }
        updateScreenIdleTimer()

        let mask = enableMaskSub ? MaskRect(x: 0.03, y: Double(maskSubYRatio), w: 0.94, h: Double(maskSubHeightRatio), style: maskSubStyle) : nil
        let logo = enableMaskLogo ? MaskRect(x: Double(logoXRatio), y: Double(logoYRatio), w: Double(logoWidthRatio), h: Double(logoHeightRatio), style: "delogo") : nil

        APIManager.shared.stepRender(
            serverURL: serverURL,
            projectId: projectId,
            cues: cues,
            maskRect: mask,
            logoRect: logo,
            dubVolume: dubVolume,
            origVolume: origVolume,
            trimStart: trimStart,
            trimEnd: trimEnd,
            renderPreset: renderPreset
        ) { res in
            DispatchQueue.main.async {
                isRendering = false
                renderTimerToken?.invalidate()
                renderTimerToken = nil
                updateScreenIdleTimer()

                switch res {
                case .success(let resResult):
                    outputVideoURL = resResult.url
                    lastRenderTimeSec = resResult.renderTimeSec
                    lastSpeedRatio = resResult.speedRatio
                    resultPlayer = AVPlayer(url: resResult.url)
                    Haptic.notify(.success)
                    let timeInfo = resResult.renderTimeSec > 0 ? " trong \(String(format: "%.1fs", resResult.renderTimeSec))" : ""
                    alertMessage = "🎉 Video đã render hoàn tất\(timeInfo)! Bạn có thể lưu vào Thư viện Ảnh hoặc chia sẻ ngay."
                    showAlert = true
                case .failure(let err):
                    alertMessage = "Lỗi render video: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func copyAllOriginalSRT() {
        let text = cues.map { "\($0.id)\n\($0.timeFormatted)\n\($0.original_text)\n" }.joined(separator: "\n")
        UIPasteboard.general.string = text
        showToastNotification("Đã sao chép kịch bản SRT gốc!")
    }

    func copyAllTranslatedText() {
        let text = cues.map { $0.translated_text }.joined(separator: "\n")
        UIPasteboard.general.string = text
        showToastNotification("Đã sao chép kịch bản tiếng Việt!")
    }

    func showToastNotification(_ msg: String) {
        toastMessage = msg
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showToast = false
        }
    }

    var loadingOverlayView: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .scaleEffect(1.6)
                    .accentColor(Color(hex: "00ADB5"))

                VStack(spacing: 6) {
                    Text(
                        isLoadingVideo ? "Đang nạp video từ thư viện..." :
                        (isExtractingSTT ? "Đang trích xuất SRT qua CapCut STT..." :
                        (isTranslating ? "Đang dịch kịch bản qua 9Router AI..." :
                        (isGeneratingTTS ? "Đang tạo giọng đọc CapCut SAMI..." : "Đang render video FFmpeg siêu tốc...")))
                    )
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                    if isRendering {
                        HStack(spacing: 6) {
                            Image(systemName: "stopwatch")
                                .foregroundColor(Color(hex: "00ADB5"))
                            Text("Thời gian xử lý: \(formatSeconds(renderElapsedSeconds))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "00ADB5"))
                        }
                        .padding(.top, 4)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 12))
                    Text("Màn hình đang được giữ luôn sáng...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "8D99AE"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "1F2738").opacity(0.8))
                .cornerRadius(12)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color(hex: "141824"))
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "00ADB5").opacity(0.5), lineWidth: 1.5))
            .shadow(color: Color(hex: "00ADB5").opacity(0.2), radius: 20)
        }
    }

    func updateScreenIdleTimer() {
        let shouldKeepAwake = alwaysKeepScreenAwake || isExtractingSTT || isTranslating || isGeneratingTTS || isRendering || isLoadingVideo
        UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
    }

    func formatSeconds(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Màn hình chọn video ban đầu (Studio Hub)
    var emptyStudioState: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Banner
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(colors: [Color(hex: "00ADB5").opacity(0.35), Color.clear], center: .center, startRadius: 10, endRadius: 70)
                            )
                            .frame(width: 140, height: 140)

                        Image(systemName: "film.stack")
                            .font(.system(size: 54))
                            .foregroundColor(Color(hex: "00ADB5"))
                    }

                    VStack(spacing: 6) {
                        Text("Dịch & Lồng Tiếng Phim AI")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Biên tập video chuyên nghiệp tách từng công đoạn")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "8D99AE"))
                    }
                }
                .padding(.top, 20)

                // Nút chọn video nổi bật
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    HStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                        Text("Chọn Video Từ Thư Viện")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "00F5FF")], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(14)
                    .shadow(color: Color(hex: "00ADB5").opacity(0.45), radius: 10, y: 4)
                }
                .padding(.horizontal, 20)
                .onChange(of: selectedItem) { newItem in
                    loadSelectedVideo(newItem)
                }

                // Feature Highlights
                VStack(alignment: .leading, spacing: 14) {
                    Text("TÍNH NĂNG ĐỘT PHÁ")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(Color(hex: "64748B"))
                        .tracking(1.0)

                    featureRow(icon: "waveform.badge.mic", title: "Bóc tách phụ đề CapCut STT", desc: "Tự động nhận dạng âm thanh Trung, Anh, Nhật thành SRT chính xác.")
                    featureRow(icon: "character.book.closed.fill", title: "Dịch AI 9Router Đa Văn Phong", desc: "Hỗ trợ văn phong Review Phim, Cổ Trang, Kiếm Hiệp, Hài Hước.")
                    featureRow(icon: "sparkles", title: "24 Giọng Đọc CapCut Bản Quyền", desc: "Đầy đủ giọng Nam Tri Thức, Review Phim new, Mai, Hoài My...")
                    featureRow(icon: "square.dashed", title: "Làm Mờ Sub & Xóa Logo 60FPS", desc: "Kéo thả vùng che trực tiếp trên màn hình video bằng FFmpeg.")
                }
                .padding(18)
                .background(Color(hex: "131722"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "1F2738"), lineWidth: 1))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
    }

    func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "00ADB5"))
                .frame(width: 32, height: 32)
                .background(Color(hex: "00ADB5").opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8D99AE"))
                    .lineLimit(2)
            }
        }
    }

    func loadSelectedVideo(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        isLoadingVideo = true
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let uniqueId = UUID().uuidString.prefix(8)
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("input_\(uniqueId).mp4")
                    try data.write(to: tempURL)

                    let asset = AVAsset(url: tempURL)
                    var detectedRatio: CGFloat = 9.0 / 16.0
                    var durSec: Double = 60.0

                    if let dur = try? await asset.load(.duration) {
                        durSec = CMTimeGetSeconds(dur)
                    }

                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let size = try? await track.load(.naturalSize) {
                        let t = try? await track.load(.preferredTransform)
                        let isPortrait = (t?.a == 0 && abs(t?.b ?? 0) == 1) || (t?.d == 0 && abs(t?.c ?? 0) == 1)
                        let w = isPortrait ? size.height : size.width
                        let h = isPortrait ? size.width : size.height
                        if w > 0 && h > 0 {
                            detectedRatio = CGFloat(w / h)
                        }
                    }

                    await MainActor.run {
                        if let token = timeObserverToken {
                            player?.removeTimeObserver(token)
                            timeObserverToken = nil
                        }
                        player?.pause()
                        player = nil

                        selectedVideoURL = tempURL
                        videoAspectRatio = detectedRatio
                        videoDuration = durSec
                        trimStart = 0.0
                        trimEnd = durSec

                        let newPlayer = AVPlayer(url: tempURL)
                        player = newPlayer
                        setupTimeObserver(newPlayer)
                        isLoadingVideo = false
                    }
                } else {
                    await MainActor.run {
                        isLoadingVideo = false
                        alertMessage = "Không thể đọc dữ liệu video từ thư viện."
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingVideo = false
                    alertMessage = "Lỗi nạp video: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func setupTimeObserver(_ p: AVPlayer) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }
    }

    func togglePlayPause() {
        guard let p = player else { return }
        Haptic.play(.light)
        if isPlaying { p.pause(); isPlaying = false }
        else { p.play(); isPlaying = true }
    }

    func seekBy(seconds: Double) {
        guard let p = player else { return }
        let target = max(0.0, min(videoDuration, currentTime + seconds))
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func resetProject() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        resultPlayer?.pause()
        resultPlayer = nil
        selectedItem = nil
        selectedVideoURL = nil
        projectId = ""
        cues = []
        currentStep = 1
        outputVideoURL = nil
        ttsReady = false
        isPlaying = false
    }

    func saveToPhotoLibrary() {
        guard let url = outputVideoURL else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                alertMessage = success ? "🎉 Đã lưu video thành công vào Photos!" : "Lỗi lưu: \(error?.localizedDescription ?? "")"
                showAlert = true
            }
        }
    }

    // MARK: - Model Picker Sheet
    var modelPickerSheetView: some View {
        NavigationView {
            ZStack {
                Color(hex: "0D1117").ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MÔ HÌNH DỊCH THUẬT HIỆN CÓ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "8D99AE"))
                            Text("Được đồng bộ trực tiếp từ server VPS")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "8D99AE").opacity(0.8))
                        }

                        Spacer()

                        Button(action: {
                            Haptic.play(.light)
                            fetchModelsFromServer(isManual: true)
                        }) {
                            HStack(spacing: 5) {
                                if isFetchingModels {
                                    ProgressView().scaleEffect(0.7).tint(Color(hex: "00ADB5"))
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Text("Làm Mới")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "1C2433"))
                            .foregroundColor(Color(hex: "00ADB5"))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "00ADB5").opacity(0.4), lineWidth: 1))
                        }
                        .disabled(isFetchingModels)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "141A26"))

                    Divider().background(Color(hex: "1F2738"))

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(availableModels) { m in
                                let isSelected = (m.id == selectedModel)
                                Button(action: {
                                    Haptic.play(.medium)
                                    selectedModel = m.id
                                    showModelPickerSheet = false
                                    showToastNotification("Đã chọn model: \(m.name)")
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(isSelected ? Color(hex: "00ADB5") : Color(hex: "4B5563"))

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(m.name)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(isSelected ? .white : Color(hex: "D1D5DB"))
                                                    .lineLimit(1)

                                                if m.is_default == true {
                                                    Text("Khuyên Dùng")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color(hex: "10B981").opacity(0.2))
                                                        .foregroundColor(Color(hex: "10B981"))
                                                        .cornerRadius(4)
                                                }
                                            }

                                            HStack(spacing: 8) {
                                                if let p = m.provider {
                                                    Text(p)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(p == "DeepSeek" ? Color(hex: "00ADB5").opacity(0.15) : Color(hex: "A855F7").opacity(0.15))
                                                        .foregroundColor(p == "DeepSeek" ? Color(hex: "00ADB5") : Color(hex: "A855F7"))
                                                        .cornerRadius(4)
                                                }

                                                Text(m.id)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(Color(hex: "8D99AE"))
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(isSelected ? Color(hex: "1A2B38") : Color(hex: "141A26"))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color(hex: "00ADB5") : Color(hex: "1F2738"), lineWidth: isSelected ? 1.5 : 1)
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Chọn Model AI Dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        showModelPickerSheet = false
                    }
                    .foregroundColor(Color(hex: "00ADB5"))
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }

    var serverSettingsModal: some View {
        NavigationView {
            Form {
                Section(header: Text("ĐỊA CHỈ MÁY CHỦ VPS")) {
                    TextField("Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button(action: checkServerHealth) {
                        HStack {
                            if isTestingServer {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingServer ? "Đang Kiểm Tra..." : "Kiểm Tra Kết Nối")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isTestingServer)

                    if !serverStatusText.isEmpty {
                        Text(serverStatusText)
                            .font(.system(size: 12))
                            .foregroundColor(isServerConnected ? Color(hex: "10B981") : .red)
                    }
                }

                Section(header: Text("TÙY CHỌN MÀN HÌNH & HIỆU NĂNG")) {
                    Toggle("Luôn giữ màn hình sáng khi làm việc", isOn: $alwaysKeepScreenAwake)
                        .font(.system(size: 14, weight: .medium))
                    Text("Tự động ngăn màn hình tắt hoặc khóa khi ứng dụng đang mở hoặc đang xử lý các tác vụ dịch, TTS và render video.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "8D99AE"))
                }

                Section(header: Text("THÔNG TIN HỆ THỐNG")) {
                    HStack {
                        Text("CapCut TTS API")
                        Spacer()
                        Text("24 Giọng Đọc (Active)")
                            .foregroundColor(Color(hex: "00ADB5"))
                    }
                    HStack {
                        Text("9Router AI")
                        Spacer()
                        Text("Gemini / DeepSeek")
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("FFmpeg Engine")
                        Spacer()
                        Text("Hardware Accelerated")
                            .foregroundColor(Color(hex: "8D99AE"))
                    }
                }
            }
            .navigationTitle("Cài Đặt Máy Chủ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showSettingsModal = false }
                }
            }
        }
    }

    func checkServerHealth() {
        isTestingServer = true
        serverStatusText = ""
        APIManager.shared.testConnection(serverURL: serverURL) { success, msg in
            DispatchQueue.main.async {
                isTestingServer = false
                isServerConnected = success
                serverStatusText = msg
            }
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
