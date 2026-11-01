import SwiftUI
import PhotosUI
import AVKit

struct VoiceItem: Identifiable, Hashable {
    let id: String
    let name: String
    let tag: String
    let gender: String
    let iconName: String
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
    @State private var timeObserverToken: Any? = nil

    // CÔNG ĐOẠN 1: Làm mờ phụ đề & làm mờ logo
    @State private var enableMaskSub: Bool = true
    @State private var maskSubYRatio: CGFloat = 0.82
    @State private var maskSubHeightRatio: CGFloat = 0.12
    @State private var maskSubStyle: String = "box_semi" // box_semi, box_black, delogo

    @State private var enableMaskLogo: Bool = false
    @State private var logoXRatio: CGFloat = 0.75
    @State private var logoYRatio: CGFloat = 0.05
    @State private var logoWidthRatio: CGFloat = 0.20
    @State private var logoHeightRatio: CGFloat = 0.08

    // CÔNG ĐOẠN 2: Bóc tách SRT (CapCut STT)
    @State private var sourceLang: String = "zh-CN"
    @State private var cues: [SubtitleCue] = []
    @State private var isExtractingSTT: Bool = false

    // CÔNG ĐOẠN 3: Dịch SRT & Chỉnh sửa tùy chỉnh (9Router)
    @State private var selectedGenre: String = "phim_chung"
    @State private var isTranslating: Bool = false

    // CÔNG ĐOẠN 4: Chuyển thành âm thanh (CapCut TTS)
    @State private var selectedVoice: String = "BV421_vivn_streaming"
    @State private var isGeneratingTTS: Bool = false
    @State private var ttsReady: Bool = false

    // CÔNG ĐOẠN 5 & 6: Ghép vào video, chỉnh sửa tùy chỉnh & xuất
    @State private var dubVolume: Double = 1.0
    @State private var origVolume: Double = 0.12
    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 60.0
    @State private var isRendering: Bool = false
    @State private var outputVideoURL: URL? = nil
    @State private var resultPlayer: AVPlayer? = nil

    // Thông báo & Settings
    @State private var showSettingsModal: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    let voices: [VoiceItem] = [
        VoiceItem(id: "BV421_vivn_streaming", name: "Nam Tri Thức", tag: "Review Phim / Kể chuyện", gender: "Nam", iconName: "person.crop.circle.badge.checkmark"),
        VoiceItem(id: "multi_female_richgirl_uranus_bigtts", name: "Nữ Sang Trọng", tag: "Phim Ngôn Tình / Kịch Tính", gender: "Nữ", iconName: "sparkles"),
        VoiceItem(id: "BV001_streaming", name: "Nữ Truyền Cảm", tag: "Đọc Truyện / Tình Cảm", gender: "Nữ", iconName: "heart.fill"),
        VoiceItem(id: "BV007_streaming", name: "Nam Trầm Ấm", tag: "Thời Sự / Phóng Sự", gender: "Nam", iconName: "mic.fill")
    ]

    let genres = [
        ("phim_chung", "Đời thường / TikTok", "flame.fill"),
        ("kiem_hiep", "Cổ trang / Kiếm hiệp", "shield.fill"),
        ("tong_tai", "Tổng tài / Ngôn tình", "crown.fill"),
        ("hai_huoc", "Hài hước / Bắt trend", "face.smiling.fill")
    ]

    public var body: some View {
        ZStack {
            Color(hex: "0B0C10").ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header
                topNavigationBar

                if selectedVideoURL == nil {
                    // Màn hình chọn video ban đầu
                    emptyStudioState
                } else {
                    // Thanh điều hướng 5 Công Đoạn
                    stepProgressBar
                        .padding(.vertical, 8)
                        .background(Color(hex: "12141C"))

                    // Video Preview Viewport
                    videoCanvasViewport
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.33)
                        .background(Color.black)

                    Divider().background(Color(hex: "232733"))

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
                    .background(Color(hex: "0F1118"))
                }
            }

            // Loading Overlay khi đang xử lý
            if isExtractingSTT || isTranslating || isGeneratingTTS || isRendering {
                loadingOverlayView
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettingsModal) {
            serverSettingsModal
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông Báo"), message: Text(alertMessage), dismissButton: .default(Text("Đóng")))
        }
    }

    // MARK: - Top Navigation Bar
    var topNavigationBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "film.stack.fill")
                    .foregroundColor(Color(hex: "00ADB5"))
                    .font(.system(size: 18, weight: .bold))
                Text("DUB STUDIO")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("PRO")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(4)
            }

            Spacer()

            if selectedVideoURL != nil {
                Button(action: resetProject) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Đổi Video")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "1F2433"))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            Button(action: { showSettingsModal = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "8D99AE"))
                    .padding(6)
                    .background(Color(hex: "1E232F"))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "12141C"))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: "232733")), alignment: .bottom)
    }

    // MARK: - Thanh Tiến Trình Tách Từng Công Đoạn (5 Bước)
    var stepProgressBar: some View {
        HStack(spacing: 4) {
            stepBadge(step: 1, title: "1. Che Sub/Logo", icon: "square.dashed")
            stepArrow
            stepBadge(step: 2, title: "2. Tạo SRT", icon: "doc.text")
            stepArrow
            stepBadge(step: 3, title: "3. Dịch AI", icon: "character.book.closed.fill")
            stepArrow
            stepBadge(step: 4, title: "4. Lồng Tiếng", icon: "mic.fill")
            stepArrow
            stepBadge(step: 5, title: "5. Ghép & Xuất", icon: "square.and.arrow.up.fill")
        }
        .padding(.horizontal, 10)
    }

    func stepBadge(step: Int, title: String, icon: String) -> some View {
        Button(action: {
            if step <= currentStep || (step == 2 && !projectId.isEmpty) || (step == 3 && !cues.isEmpty) {
                currentStep = step
            }
        }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: currentStep == step ? .bold : .medium))
                    .foregroundColor(currentStep == step ? Color(hex: "00ADB5") : (step < currentStep ? .green : Color(hex: "555E6D")))
                Text(title)
                    .font(.system(size: 9, weight: currentStep == step ? .bold : .regular))
                    .foregroundColor(currentStep == step ? .white : (step < currentStep ? .white.opacity(0.8) : Color(hex: "555E6D")))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(currentStep == step ? Color(hex: "00ADB5").opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
    }

    var stepArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(Color(hex: "404859"))
    }

    // MARK: - Video Canvas Viewport với Vùng Che Sub & Logo
    var videoCanvasViewport: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Color.black

                if let p = player {
                    VideoPlayer(player: p)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                }

                // 1. Hộp Vùng Che Sub Gốc (Kéo thả)
                if enableMaskSub {
                    let boxH = geo.size.height * maskSubHeightRatio
                    let boxY = geo.size.height * maskSubYRatio

                    ZStack {
                        Rectangle()
                            .fill(maskSubStyle == "box_black" ? Color.black : Color.black.opacity(0.72))
                            .overlay(
                                Text("VÙNG CHE PHỤ ĐỀ GỐC")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
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

                // 2. Hộp Vùng Che Logo (Kéo thả)
                if enableMaskLogo {
                    let logoW = geo.size.width * logoWidthRatio
                    let logoH = geo.size.height * logoHeightRatio
                    let logoX = geo.size.width * logoXRatio
                    let logoY = geo.size.height * logoYRatio

                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                Text("LOGO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
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

                // Nút Play / Pause
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .opacity(isPlaying ? 0.0 : 0.85)
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 1: Làm mờ phụ đề & làm mờ logo
    var step1MaskView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "1", title: "Làm Mờ Phụ Đề & Làm Mờ Logo", desc: "Kéo thả các hộp trên màn hình video để định vị vùng cần che.")

            // 1. Tùy chọn che phụ đề
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Bật làm mờ / che Phụ Đề gốc", isOn: $enableMaskSub)
                    .font(.system(size: 14, weight: .bold))

                if enableMaskSub {
                    Picker("Kiểu che", selection: $maskSubStyle) {
                        Text("Hộp Mờ Đen").tag("box_semi")
                        Text("Đen Tuyền").tag("box_black")
                        Text("Xóa Mờ (Delogo)").tag("delogo")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    HStack {
                        Text("Vị trí theo chiều dọc (Y):")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "8D99AE"))
                        Spacer()
                        Text("\(Int(maskSubYRatio * 100))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "00ADB5"))
                    }
                    Slider(value: Binding(get: { Double(maskSubYRatio) }, set: { maskSubYRatio = CGFloat($0) }), in: 0.2...0.9)
                        .accentColor(Color(hex: "00ADB5"))
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            // 2. Tùy chọn che Logo
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Bật làm mờ Logo (Xóa logo góc video)", isOn: $enableMaskLogo)
                    .font(.system(size: 14, weight: .bold))

                if enableMaskLogo {
                    Text("Hộp màu vàng đã xuất hiện ở góc video, bạn hãy kéo hộp vào đúng vị trí logo.")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            // Nút chuyển sang Bước 2
            Button(action: {
                if projectId.isEmpty {
                    uploadAndProceedToSTT()
                } else {
                    currentStep = 2
                }
            }) {
                HStack {
                    Spacer()
                    Text("Xác Nhận & Sang Bước 2: Bóc Tách SRT")
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                    Spacer()
                }
                .padding()
                .background(Color(hex: "00ADB5"))
                .foregroundColor(.black)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 2: Bóc tách SRT (CapCut STT)
    var step2STTView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "2", title: "Chuyển Văn Bản Thành SRT", desc: "CapCut Cloud STT sẽ bóc tách âm thanh và tạo các câu thoại kèm mốc thời gian.")

            HStack {
                Text("Ngôn ngữ giọng nói trong video:")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "8D99AE"))
                Spacer()
                Picker("Ngôn ngữ", selection: $sourceLang) {
                    Text("Tiếng Trung (zh-CN)").tag("zh-CN")
                    Text("Tiếng Anh (en-US)").tag("en-US")
                    Text("Tiếng Việt (vi-VN)").tag("vi-VN")
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            if cues.isEmpty {
                Button(action: runSTT) {
                    HStack {
                        Spacer()
                        Image(systemName: "waveform.badge.mic")
                        Text("Bắt Đầu Bóc Tách SRT (CapCut STT)")
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("✅ Đã trích xuất thành công \(cues.count) câu thoại")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                        Spacer()
                        Button("Quét Lại") { runSTT() }
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }

                    // Danh sách câu thoại gốc
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(cues) { cue in
                                HStack {
                                    Text("[\(cue.timeFormatted)]")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "00ADB5"))
                                    Text(cue.original_text)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(hex: "1A202C"))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)

                Button(action: { currentStep = 3 }) {
                    HStack {
                        Spacer()
                        Text("Sang Bước 3: Dịch SRT Bằng 9Router")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                        Spacer()
                    }
                    .padding()
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 3: Dịch SRT & Chỉnh sửa tùy chỉnh
    var step3TranslateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "3", title: "Dịch SRT & Chỉnh Sửa Tùy Chỉnh", desc: "9Router dịch chuẩn ngữ cảnh. Bạn có thể sửa trực tiếp từng câu tiếng Việt.")

            // Chọn văn phong dịch
            VStack(alignment: .leading, spacing: 8) {
                Text("CHỌN VĂN PHONG DỊCH THUẬT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "8D99AE"))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(genres, id: \.0) { g in
                        Button(action: { selectedGenre = g.0 }) {
                            HStack(spacing: 6) {
                                Image(systemName: g.2)
                                    .font(.system(size: 12))
                                    .foregroundColor(selectedGenre == g.0 ? Color(hex: "00ADB5") : .white)
                                Text(g.1)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(selectedGenre == g.0 ? .white : Color(hex: "8D99AE"))
                                Spacer()
                            }
                            .padding(8)
                            .background(selectedGenre == g.0 ? Color(hex: "1A2B38") : Color(hex: "141824"))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedGenre == g.0 ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.2))
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            Button(action: runTranslate) {
                HStack {
                    Spacer()
                    Image(systemName: "sparkles")
                    Text("Dịch Sang Tiếng Việt (9Router AI)")
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Danh sách chỉnh sửa tùy chỉnh
            if !cues.isEmpty && cues.contains(where: { !$0.translated_text.isEmpty }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("BẢNG CHỈNH SỬA TÙY CHỈNH (CHẠM ĐỂ SỬA CÂU TỪ)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "8D99AE"))

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach($cues) { $cue in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("[\(cue.timeFormatted)]")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                        Text(cue.original_text)
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(hex: "8D99AE"))
                                        Spacer()
                                    }
                                    TextField("Câu dịch tiếng Việt", text: $cue.translated_text)
                                        .font(.system(size: 13))
                                        .padding(8)
                                        .background(Color(hex: "1E2433"))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                .padding(8)
                                .background(Color(hex: "161A26"))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)

                Button(action: { currentStep = 4 }) {
                    HStack {
                        Spacer()
                        Text("Sang Bước 4: Chuyển Thành Âm Thanh")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                        Spacer()
                    }
                    .padding()
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - CÔNG ĐOẠN 4: Chuyển thành âm thanh (CapCut TTS)
    var step4TTSView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(stepNum: "4", title: "Chuyển Văn Bản Thành Âm Thanh", desc: "CapCut SAMI TTS sẽ sinh file giọng đọc cảm xúc cho từng câu thoại.")

            VStack(spacing: 8) {
                ForEach(voices) { v in
                    Button(action: { selectedVoice = v.id }) {
                        HStack(spacing: 12) {
                            Image(systemName: v.iconName)
                                .font(.system(size: 18))
                                .foregroundColor(selectedVoice == v.id ? Color(hex: "00ADB5") : .white)
                                .frame(width: 36, height: 36)
                                .background(selectedVoice == v.id ? Color(hex: "00ADB5").opacity(0.18) : Color(hex: "1A202C"))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text(v.tag)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "8D99AE"))
                            }
                            Spacer()
                            if selectedVoice == v.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(hex: "00ADB5"))
                            }
                        }
                        .padding(10)
                        .background(selectedVoice == v.id ? Color(hex: "16222F") : Color(hex: "141824"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedVoice == v.id ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.2))
                    }
                }
            }

            Button(action: runTTS) {
                HStack {
                    Spacer()
                    Image(systemName: "waveform.and.mic")
                    Text("Tạo Giọng Đọc Lồng Tiếng (CapCut TTS)")
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            if ttsReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ Giọng đọc đã sẵn sàng! Bạn có thể bấm loa nghe thử:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)

                    ScrollView {
                        VStack(spacing: 6) {
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
                    .frame(maxHeight: 180)
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)

                Button(action: { currentStep = 5 }) {
                    HStack {
                        Spacer()
                        Text("Sang Bước 5: Ghép Video & Xuất File")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                        Spacer()
                    }
                    .padding()
                    .background(Color(hex: "00ADB5"))
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

            // Cắt đoạn
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cắt đoạn video (Trim):")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(String(format: "%.1fs - %.1fs", trimStart, trimEnd))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $trimStart, in: 0...max(1.0, trimEnd - 1.0))
                    .accentColor(Color(hex: "00ADB5"))
                Slider(value: $trimEnd, in: min(videoDuration, trimStart + 1.0)...videoDuration)
                    .accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            // Cân bằng âm thanh
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Âm lượng giọng đọc lồng tiếng:")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(dubVolume * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $dubVolume, in: 0.2...2.0).accentColor(Color(hex: "00ADB5"))

                HStack {
                    Text("Dìm âm thanh video gốc (Ducking):")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(origVolume * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $origVolume, in: 0.0...0.5).accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            // Nút Render Xuất Video
            Button(action: runRender) {
                HStack {
                    Spacer()
                    Image(systemName: "film.fill")
                    Text("Render & Xuất Video Hoàn Thiện")
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding()
                .background(
                    LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color(hex: "00ADB5").opacity(0.4), radius: 8, y: 3)
            }

            // Video thành phẩm
            if let _ = outputVideoURL, let resP = resultPlayer {
                VStack(alignment: .leading, spacing: 10) {
                    Text("🎬 VIDEO THÀNH PHẨM")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)

                    VideoPlayer(player: resP)
                        .frame(height: 220)
                        .cornerRadius(12)

                    Button(action: saveToPhotoLibrary) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Lưu Video Vào Thư Viện Ảnh (Photos)")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(14)
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
                case .failure(let err):
                    alertMessage = "Lỗi bóc tách SRT: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func runTranslate() {
        isTranslating = true
        APIManager.shared.stepTranslate(serverURL: serverURL, projectId: projectId, cues: cues, genre: selectedGenre) { res in
            DispatchQueue.main.async {
                isTranslating = false
                switch res {
                case .success(let translatedCues):
                    cues = translatedCues
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
                case .failure(let err):
                    alertMessage = "Lỗi tạo giọng đọc: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func runRender() {
        isRendering = true
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
            trimEnd: trimEnd
        ) { res in
            DispatchQueue.main.async {
                isRendering = false
                switch res {
                case .success(let destURL):
                    outputVideoURL = destURL
                    resultPlayer = AVPlayer(url: destURL)
                    alertMessage = "🎉 Video đã render hoàn tất! Bạn có thể lưu vào Thư viện Ảnh."
                    showAlert = true
                case .failure(let err):
                    alertMessage = "Lỗi render video: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    var loadingOverlayView: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .accentColor(Color(hex: "00ADB5"))
                Text(
                    isExtractingSTT ? "Đang trích xuất SRT qua CapCut..." :
                    (isTranslating ? "Đang dịch kịch bản qua 9Router AI..." :
                    (isGeneratingTTS ? "Đang tạo giọng đọc CapCut SAMI..." : "Đang render video FFmpeg..."))
                )
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            }
            .padding(28)
            .background(Color(hex: "141824"))
            .cornerRadius(18)
        }
    }

    // Màn hình chọn video ban đầu
    var emptyStudioState: some View {
        PhotosPicker(selection: $selectedItem, matching: .videos) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "00ADB5").opacity(0.2))
                        .frame(width: 80, height: 80)
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 38))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                VStack(spacing: 4) {
                    Text("Bắt Đầu Biên Tập & Dịch Phim")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("Chọn video MP4 từ Thư viện Ảnh để tách từng công đoạn.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8D99AE"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(Color(hex: "141824"))
            .cornerRadius(18)
            .padding(20)
        }
        .onChange(of: selectedItem) { newItem in
            loadSelectedVideo(newItem)
        }
    }

    func loadSelectedVideo(_ item: PhotosPickerItem?) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("input_video.mp4")
                try? data.write(to: tempURL)
                DispatchQueue.main.async {
                    selectedVideoURL = tempURL
                    let newPlayer = AVPlayer(url: tempURL)
                    player = newPlayer
                    setupTimeObserver(newPlayer)

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
        if isPlaying { p.pause(); isPlaying = false }
        else { p.play(); isPlaying = true }
    }

    func resetProject() {
        selectedItem = nil
        selectedVideoURL = nil
        projectId = ""
        cues = []
        currentStep = 1
        outputVideoURL = nil
        ttsReady = false
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

    var serverSettingsModal: some View {
        NavigationView {
            Form {
                Section(header: Text("ĐỊA CHỈ MÁY CHỦ VPS")) {
                    TextField("Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Cài Đặt")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { showSettingsModal = false }
                }
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
