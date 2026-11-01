import SwiftUI
import PhotosUI
import AVKit

// MARK: - Voice Model
struct VoiceItem: Identifiable, Hashable {
    let id: String
    let name: String
    let tag: String
    let gender: String
    let iconName: String
}

// MARK: - Main Studio View
public struct ContentView: View {
    @AppStorage("server_url") private var serverURL: String = "http://103.211.206.176:9005"

    // Video State
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var videoDuration: Double = 60.0
    @State private var timeObserverToken: Any? = nil

    // Aspect Ratio & Layout
    @State private var selectedAspectRatio: String = "9:16"

    // Trim State
    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 60.0

    // Mask Sub/Logo State
    @State private var enableMask: Bool = true
    @State private var maskYRatio: CGFloat = 0.82
    @State private var maskHeightRatio: CGFloat = 0.12
    @State private var maskStyle: String = "box_semi"

    // Audio Mixer State
    @State private var dubVolume: Double = 1.0
    @State private var origVolume: Double = 0.12

    // Voice & Translation State
    @State private var selectedVoice: String = "BV421_vivn_streaming"
    @State private var selectedGenre: String = "phim_chung"

    // Subtitle Editor State
    @State private var cues: [SubtitleCue] = []
    @State private var showSubtitleStudio: Bool = false
    @State private var searchSubtitleText: String = ""

    // Bottom Navigation Tool Selection
    @State private var activeToolTab: String = "translate" // translate, edit, sub, mask, audio

    // Task Progress State
    @State private var isProcessing: Bool = false
    @State private var currentTaskId: String = ""
    @State private var progressPercent: Int = 0
    @State private var progressStage: String = ""
    @State private var progressMessage: String = ""
    @State private var pollingTimer: Timer? = nil

    // Result State
    @State private var outputVideoURL: URL? = nil
    @State private var resultPlayer: AVPlayer? = nil
    @State private var showResultModal: Bool = false
    @State private var showSettingsModal: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    // Voice Catalog
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
        ("hai_huoc", "Hài hước / Dí dỏm", "face.smiling.fill")
    ]

    public var body: some View {
        ZStack {
            Color(hex: "0B0C10").ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. TOP HEADER BAR
                topNavigationBar

                if selectedVideoURL == nil {
                    // 2. EMPTY STATE: CHƯA CHỌN VIDEO
                    emptyStudioState
                } else {
                    // 3. PRO EDITOR VIEWPORT & TIMELINE
                    VStack(spacing: 0) {
                        // Video Player Viewport with interactive mask
                        videoCanvasViewport
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.38)
                            .background(Color.black)

                        // Timeline & Playback Bar
                        timelineControlBar
                            .padding(.vertical, 8)
                            .background(Color(hex: "12141C"))

                        Divider().background(Color(hex: "232733"))

                        // Bottom Tool Panels
                        activeToolPanel
                            .frame(maxHeight: .infinity)
                            .background(Color(hex: "0F1118"))

                        // Bottom Tool Dock Bar
                        bottomToolDock
                    }
                }
            }

            // MODAL TIẾN TRÌNH RENDER XUẤT VIDEO
            if isProcessing {
                renderProgressOverlay
            }

            // MODAL KẾT QUẢ VIDEO HOÀN THIỆN
            if showResultModal, let _ = outputVideoURL {
                resultVideoModal
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSubtitleStudio) {
            subtitleStudioView
        }
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
                Image(systemName: "wand.and.stars")
                    .foregroundColor(Color(hex: "00ADB5"))
                    .font(.system(size: 18, weight: .bold))
                Text("DUB STUDIO")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("AI")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(4)
            }

            Spacer()

            if selectedVideoURL != nil {
                Button(action: startExportTask) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Xuất Video")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(color: Color(hex: "00ADB5").opacity(0.4), radius: 6, y: 2)
                }
                .disabled(isProcessing)
            }

            Button(action: { showSettingsModal = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
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

    // MARK: - Empty State (Khi chưa chọn Video)
    var emptyStudioState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // Big Upload Card
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "00ADB5").opacity(0.2), Color(hex: "3B82F6").opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 90, height: 90)
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 42, weight: .medium))
                                .foregroundColor(Color(hex: "00ADB5"))
                        }

                        VStack(spacing: 6) {
                            Text("Bắt đầu Dự Án Mới")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                            Text("Chọn video từ iPhone để tự động Dịch, Lồng tiếng & Biên tập")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "8D99AE"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Mở Thư Viện Ảnh")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(Color(hex: "00ADB5"))
                        .foregroundColor(.black)
                        .cornerRadius(25)
                        .shadow(color: Color(hex: "00ADB5").opacity(0.3), radius: 8, y: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color(hex: "141824"))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundColor(Color(hex: "00ADB5").opacity(0.4))
                    )
                }
                .onChange(of: selectedItem) { newItem in
                    loadSelectedVideo(newItem)
                }
                .padding(.horizontal, 20)

                // Feature Highlights
                VStack(alignment: .leading, spacing: 14) {
                    Text("TÍNH NĂNG NỔI BẬT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "8D99AE"))
                        .tracking(1.2)
                        .padding(.horizontal, 4)

                    featureCard(icon: "waveform.badge.mic", title: "CapCut Cloud STT", desc: "Nhận diện mốc thời gian chuẩn xác từng mili-giây từ giọng nói gốc.")
                    featureCard(icon: "bubble.left.and.bubble.right.fill", title: "9Router AI Dịch Thuật", desc: "Dịch chuẩn ngữ cảnh điện ảnh, khống chế số lượng âm tiết để vừa khít nhịp đọc.")
                    featureCard(icon: "sparkles.tv", title: "Lồng Tiếng CapCut SAMI", desc: "Giọng đọc AI cảm xúc cao, tự động đồng bộ khẩu hình và dìm âm gốc thông minh.")
                    featureCard(icon: "scissors.badge.ellipsis", title: "Biên Tập & Che Sub Gốc", desc: "Kéo thả hộp che phụ đề gốc, cắt gọt video với giao diện Timeline mượt mà.")
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 30)
            }
        }
    }

    func featureCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "00ADB5"))
                .frame(width: 42, height: 42)
                .background(Color(hex: "1E2436"))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "8D99AE"))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: "141824"))
        .cornerRadius(14)
    }

    // MARK: - Video Canvas Viewport
    var videoCanvasViewport: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Color.black

                if let p = player {
                    VideoPlayer(player: p)
                        .aspectRatio(aspectRatioValue, contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                }

                // Interactive Mask Box overlay
                if enableMask {
                    let boxH = geo.size.height * maskHeightRatio
                    let boxY = geo.size.height * maskYRatio

                    ZStack {
                        Rectangle()
                            .fill(maskStyle == "box_black" ? Color.black : Color.black.opacity(0.72))
                            .overlay(
                                HStack {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.system(size: 10))
                                    Text("Vùng Che Phụ Đề Gốc")
                                        .font(.system(size: 11, weight: .bold))
                                }
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
                                maskYRatio = max(0.05, min(0.90, newY))
                            }
                    )
                }

                // Floating Play/Pause Button on tap
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .opacity(isPlaying ? 0.0 : 0.85)

                // Timecode pill
                VStack {
                    HStack {
                        Text(formatSeconds(currentTime) + " / " + formatSeconds(videoDuration))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                }
            }
        }
    }

    var aspectRatioValue: CGFloat {
        switch selectedAspectRatio {
        case "9:16": return 9.0 / 16.0
        case "16:9": return 16.0 / 9.0
        case "1:1": return 1.0
        default: return 9.0 / 16.0
        }
    }

    // MARK: - Timeline Control Bar
    var timelineControlBar: some View {
        VStack(spacing: 6) {
            // Ruler & Track representation
            HStack(spacing: 12) {
                Button(action: { seekRelative(-5) }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Interactive Scrubber Slider
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newTime in
                            seekToTime(newTime)
                        }
                    ),
                    in: 0...max(1.0, videoDuration)
                )
                .accentColor(Color(hex: "00ADB5"))

                Button(action: { seekRelative(5) }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)

            // Filmstrip / Subtitle Strip Indicator
            HStack {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [Color(hex: "1F2833"), Color(hex: "2D3748")], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 18)
                    .cornerRadius(4)
                    .overlay(
                        HStack(spacing: 4) {
                            Text("🎬 Track Video (Cắt: \(String(format: "%.1fs", trimStart)) - \(String(format: "%.1fs", trimEnd)))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "00ADB5"))
                                .padding(.leading, 6)
                            Spacer()
                        }
                    )
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Bottom Tool Panels
    var activeToolPanel: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch activeToolTab {
                case "translate":
                    voiceAndGenrePanel
                case "edit":
                    trimAndAspectPanel
                case "sub":
                    subtitleToolsPanel
                case "mask":
                    maskSettingsPanel
                case "audio":
                    audioMixerPanel
                default:
                    voiceAndGenrePanel
                }
            }
            .padding(16)
        }
    }

    // Panel 1: Giọng đọc & Dịch thuật
    var voiceAndGenrePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GIỌNG ĐỌC CAPCUT TTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "8D99AE"))
                Spacer()
                Text("Bản quyền ByteDance SAMI")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "00ADB5"))
            }

            // Voice Selector Cards
            VStack(spacing: 8) {
                ForEach(voices) { v in
                    Button(action: { selectedVoice = v.id }) {
                        HStack(spacing: 12) {
                            Image(systemName: v.iconName)
                                .font(.system(size: 18))
                                .foregroundColor(selectedVoice == v.id ? Color(hex: "00ADB5") : .white)
                                .frame(width: 38, height: 38)
                                .background(selectedVoice == v.id ? Color(hex: "00ADB5").opacity(0.18) : Color(hex: "1A202C"))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(v.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(v.gender)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(v.gender == "Nam" ? Color.blue.opacity(0.25) : Color.pink.opacity(0.25))
                                        .foregroundColor(v.gender == "Nam" ? .blue : .pink)
                                        .cornerRadius(4)
                                }
                                Text(v.tag)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "8D99AE"))
                            }

                            Spacer()

                            if selectedVoice == v.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(hex: "00ADB5"))
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(12)
                        .background(selectedVoice == v.id ? Color(hex: "16222F") : Color(hex: "141824"))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedVoice == v.id ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            // Genre Selector
            Text("VĂN PHONG DỊCH THUẬT (9ROUTER AI)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "8D99AE"))
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(genres, id: \.0) { g in
                    Button(action: { selectedGenre = g.0 }) {
                        HStack(spacing: 8) {
                            Image(systemName: g.2)
                                .font(.system(size: 13))
                                .foregroundColor(selectedGenre == g.0 ? Color(hex: "00ADB5") : .white)
                            Text(g.1)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedGenre == g.0 ? .white : Color(hex: "8D99AE"))
                            Spacer()
                        }
                        .padding(10)
                        .background(selectedGenre == g.0 ? Color(hex: "1A2B38") : Color(hex: "141824"))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedGenre == g.0 ? Color(hex: "00ADB5") : Color.clear, lineWidth: 1.2)
                        )
                    }
                }
            }
        }
    }

    // Panel 2: Biên tập Cắt & Tỷ lệ
    var trimAndAspectPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TỶ LỆ KHUNG HÌNH (ASPECT RATIO)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "8D99AE"))

            HStack(spacing: 10) {
                ForEach(["9:16", "16:9", "1:1"], id: \.self) { ratio in
                    Button(action: { selectedAspectRatio = ratio }) {
                        VStack(spacing: 4) {
                            Text(ratio)
                                .font(.system(size: 13, weight: .bold))
                            Text(ratio == "9:16" ? "TikTok" : (ratio == "16:9" ? "YouTube" : "Feed"))
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedAspectRatio == ratio ? Color(hex: "00ADB5") : Color(hex: "141824"))
                        .foregroundColor(selectedAspectRatio == ratio ? .black : .white)
                        .cornerRadius(10)
                    }
                }
            }

            Text("CẮT ĐOẠN VIDEO (TRIM)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "8D99AE"))
                .padding(.top, 6)

            VStack(spacing: 10) {
                HStack {
                    Text("Bắt đầu:")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8D99AE"))
                    Spacer()
                    Text(formatSeconds(trimStart))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $trimStart, in: 0...max(1.0, trimEnd - 1.0))
                    .accentColor(Color(hex: "00ADB5"))

                HStack {
                    Text("Kết thúc:")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8D99AE"))
                    Spacer()
                    Text(formatSeconds(trimEnd))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $trimEnd, in: min(videoDuration, trimStart + 1.0)...videoDuration)
                    .accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)
        }
    }

    // Panel 3: Phụ Đề
    var subtitleToolsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("STUDIO PHỤ ĐỀ SONG NGỮ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "8D99AE"))
                Spacer()
                Text("\(cues.count) câu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "00ADB5"))
            }

            Button(action: { showSubtitleStudio = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "00ADB5"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mở Bảng Biên Soạn Phụ Đề")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Xem và chỉnh sửa trực tiếp từng câu dịch tiếng Việt.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "8D99AE"))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color(hex: "8D99AE"))
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)
            }

            if cues.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Color(hex: "00ADB5"))
                    Text("Khi bấm 'Xuất Video', hệ thống sẽ tự động quét STT CapCut và gửi vào bảng này.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8D99AE"))
                }
                .padding(12)
                .background(Color(hex: "141824").opacity(0.6))
                .cornerRadius(10)
            }
        }
    }

    // Panel 4: Che Phụ Đề / Logo
    var maskSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $enableMask) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bật Vùng Che Phụ Đề Gốc")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("Hiển thị hộp che để phủ kín sub tiếng Trung/Anh gốc.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "8D99AE"))
                }
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            if enableMask {
                VStack(alignment: .leading, spacing: 10) {
                    Text("KIỂU VÙNG CHE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "8D99AE"))

                    Picker("Kiểu che", selection: $maskStyle) {
                        Text("Hộp Mờ Đen").tag("box_semi")
                        Text("Đen Tuyền").tag("box_black")
                        Text("Xóa Logo (Delogo)").tag("delogo")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text("VỊ TRÍ CHIỀU DỌC (Y-OFFSET)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "8D99AE"))
                        .padding(.top, 4)

                    Slider(value: Binding(get: { Double(maskYRatio) }, set: { maskYRatio = CGFloat($0) }), in: 0.1...0.9)
                        .accentColor(Color(hex: "00ADB5"))

                    Text("Bạn cũng có thể chạm và kéo trực tiếp hộp đỏ trên màn hình video để căn chỉnh.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                .padding(14)
                .background(Color(hex: "141824"))
                .cornerRadius(12)
            }
        }
    }

    // Panel 5: Trộn Âm Thanh
    var audioMixerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Âm Lượng Giọng Lồng Tiếng (AI)", systemImage: "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(dubVolume * 100))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $dubVolume, in: 0.2...2.0)
                    .accentColor(Color(hex: "00ADB5"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Dìm Âm Thanh Video Gốc (Ducking)", systemImage: "speaker.wave.1.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(origVolume * 100))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "00ADB5"))
                }
                Slider(value: $origVolume, in: 0.0...0.5)
                    .accentColor(Color(hex: "00ADB5"))
                Text("Mức 10% - 15% là tiêu chuẩn vàng để giữ nhạc nền phim và làm nổi bật giọng lồng tiếng.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8D99AE"))
            }
            .padding(14)
            .background(Color(hex: "141824"))
            .cornerRadius(12)
        }
    }

    // MARK: - Bottom Tool Dock Bar
    var bottomToolDock: some View {
        HStack(spacing: 0) {
            toolDockButton(id: "translate", title: "Lồng Tiếng", icon: "waveform.and.mic")
            toolDockButton(id: "edit", title: "Biên Tập", icon: "scissors")
            toolDockButton(id: "sub", title: "Phụ Đề", icon: "captions.bubble.fill")
            toolDockButton(id: "mask", title: "Che Sub", icon: "square.dashed")
            toolDockButton(id: "audio", title: "Âm Thanh", icon: "slider.vertical.3")
        }
        .padding(.vertical, 8)
        .background(Color(hex: "12141C"))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: "232733")), alignment: .top)
    }

    func toolDockButton(id: String, title: String, icon: String) -> some View {
        Button(action: { activeToolTab = id }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: activeToolTab == id ? .bold : .regular))
                    .foregroundColor(activeToolTab == id ? Color(hex: "00ADB5") : Color(hex: "8D99AE"))
                Text(title)
                    .font(.system(size: 10, weight: activeToolTab == id ? .bold : .medium))
                    .foregroundColor(activeToolTab == id ? .white : Color(hex: "8D99AE"))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Modal Studio Chỉnh Sửa Phụ Đề
    var subtitleStudioView: some View {
        NavigationView {
            ZStack {
                Color(hex: "0B0C10").ignoresSafeArea()

                VStack(spacing: 0) {
                    if cues.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 40))
                                .foregroundColor(Color(hex: "00ADB5"))
                            Text("Chưa Có Dữ Liệu Phụ Đề")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Khi xuất video, câu thoại sẽ tự động xuất hiện tại đây để bạn chỉnh sửa.")
                                .font(.caption)
                                .foregroundColor(Color(hex: "8D99AE"))
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach($cues) { $cue in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("[\(cue.timeFormatted)]")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                        Spacer()
                                        Button(action: {
                                            APIManager.shared.playTTSPreview(serverURL: serverURL, text: cue.translated_text, voiceID: selectedVoice)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                Text("Nghe thử")
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(Color(hex: "00ADB5"))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(hex: "00ADB5").opacity(0.15))
                                            .cornerRadius(6)
                                        }
                                    }

                                    Text(cue.original_text)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "8D99AE"))

                                    TextField("Câu dịch tiếng Việt", text: $cue.translated_text)
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(8)
                                        .background(Color(hex: "1F2433"))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(Color(hex: "141824"))
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
            }
            .navigationTitle("Studio Phụ Đề")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hoàn Tất") { showSubtitleStudio = false }
                        .foregroundColor(Color(hex: "00ADB5"))
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }

    // MARK: - Modal Cài Đặt Server
    var serverSettingsModal: some View {
        NavigationView {
            Form {
                Section(header: Text("ĐỊA CHỈ MÁY CHỦ VPS")) {
                    TextField("Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section(header: Text("THÔNG TIN DỊCH VỤ")) {
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        Text("Hoạt động")
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("CapCut Engine")
                        Spacer()
                        Text("ByteDance SAMI")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Dịch thuật AI")
                        Spacer()
                        Text("9Router Local")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cấu Hình")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { showSettingsModal = false }
                }
            }
        }
    }

    // MARK: - Overlay Tiến Trình Xuất Video
    var renderProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "1F2833"), lineWidth: 8)
                        .frame(width: 110, height: 110)

                    Circle()
                        .trim(from: 0.0, to: CGFloat(progressPercent) / 100.0)
                        .stroke(
                            LinearGradient(colors: [Color(hex: "00ADB5"), Color(hex: "3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 110)

                    Text("\(progressPercent)%")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text(progressStage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(progressMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8D99AE"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                HStack(spacing: 6) {
                    Circle().fill(progressPercent >= 20 ? Color(hex: "00ADB5") : Color.gray).frame(width: 8, height: 8)
                    Circle().fill(progressPercent >= 50 ? Color(hex: "00ADB5") : Color.gray).frame(width: 8, height: 8)
                    Circle().fill(progressPercent >= 75 ? Color(hex: "00ADB5") : Color.gray).frame(width: 8, height: 8)
                    Circle().fill(progressPercent >= 95 ? Color(hex: "00ADB5") : Color.gray).frame(width: 8, height: 8)
                }
            }
            .padding(32)
            .background(Color(hex: "141824"))
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.6), radius: 20)
            .padding(.horizontal, 36)
        }
    }

    // MARK: - Modal Video Thành Phẩm
    var resultVideoModal: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("🎬 VIDEO HOÀN THIỆN")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { showResultModal = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if let p = resultPlayer {
                    VideoPlayer(player: p)
                        .frame(height: UIScreen.main.bounds.height * 0.55)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                }

                Button(action: saveToPhotoLibrary) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Lưu Video vào Thư Viện Ảnh")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "00ADB5"))
                    .foregroundColor(.black)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(hex: "12141C"))
            .cornerRadius(24)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers & Player Controls
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
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func seekToTime(_ sec: Double) {
        let cmTime = CMTime(seconds: sec, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = sec
    }

    func seekRelative(_ delta: Double) {
        let target = max(0.0, min(videoDuration, currentTime + delta))
        seekToTime(target)
    }

    func formatSeconds(_ sec: Double) -> String {
        let s = Int(sec)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // Bắt đầu Render Task
    func startExportTask() {
        guard let vidURL = selectedVideoURL else { return }
        isProcessing = true
        progressPercent = 5
        progressStage = "Đang gửi dữ liệu lên VPS"
        progressMessage = "Đang tải video và cấu hình biên tập đến máy chủ..."

        let mask = enableMask ? MaskRect(x: 0.03, y: Double(maskYRatio), w: 0.94, h: Double(maskHeightRatio), style: maskStyle) : nil

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

    func startPollingProgress() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
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
                            pollingTimer?.invalidate()
                            downloadFinalVideo()
                        } else if status.status == "failed" {
                            pollingTimer?.invalidate()
                            isProcessing = false
                            alertMessage = "Lỗi xử lý: \(status.error ?? "Không rõ")"
                            showAlert = true
                        }
                    case .failure:
                        break
                    }
                }
            }
        }
    }

    func downloadFinalVideo() {
        progressStage = "Đang tải video hoàn thiện về máy..."
        APIManager.shared.downloadResultVideo(serverURL: serverURL, taskId: currentTaskId) { res in
            DispatchQueue.main.async {
                isProcessing = false
                switch res {
                case .success(let fileURL):
                    outputVideoURL = fileURL
                    resultPlayer = AVPlayer(url: fileURL)
                    showResultModal = true
                case .failure(let err):
                    alertMessage = "Lỗi tải video: \(err.localizedDescription)"
                    showAlert = true
                }
            }
        }
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
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
