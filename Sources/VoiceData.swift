import Foundation

public struct VoiceItem: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let category: String
    public let gender: String
    public let lang: String

    public init(id: String, name: String, category: String, gender: String, lang: String = "vi-VN") {
        self.id = id
        self.name = name
        self.category = category
        self.gender = gender
        self.lang = lang
    }

    public var iconName: String {
        switch category {
        case "Review Phim": return "film.stack.fill"
        case "Bản Tin": return "newspaper.fill"
        case "Độc Lạ / Hài": return "theatermasks.fill"
        default:
            return gender == "Nam" ? "person.crop.circle.badge.checkmark" : "sparkles"
        }
    }
}

public struct VoiceCatalog {
    // Đầy đủ 24 giọng đọc tiếng Việt trích xuất chuẩn 100% từ Voice.json của CapCut API
    public static let allVietnameseVoices: [VoiceItem] = [
        VoiceItem(id: "BV421_vivn_streaming", name: "Nhỏ Ngọt Ngào (Review Tri Thức)", category: "Review Phim", gender: "Nam"),
        VoiceItem(id: "multi_female_richgirl_uranus_bigtts", name: "Review Phim new (Sang Trọng)", category: "Review Phim", gender: "Nữ"),
        VoiceItem(id: "multi_female_xyf04auto_uranus_bigtts", name: "Review Phim 2", category: "Review Phim", gender: "Nữ"),
        VoiceItem(id: "multi_female_daqi_uranus_bigtts", name: "Review Phim 3", category: "Review Phim", gender: "Nữ"),
        VoiceItem(id: "multi_female_stokie_uranus_bigtts", name: "Review Phim 4", category: "Review Phim", gender: "Nữ"),

        VoiceItem(id: "multi_male_felipe_uranus_bigtts", name: "Giọng Nam Trầm (Ấm Áp)", category: "Giọng Nam", gender: "Nam"),
        VoiceItem(id: "vi-VN-NamMinhNeural", name: "Nam Minh (Chuẩn Hà Nội)", category: "Giọng Nam", gender: "Nam"),
        VoiceItem(id: "BV075_streaming", name: "Thanh Niên Tự Tin", category: "Giọng Nam", gender: "Nam"),
        VoiceItem(id: "multi_female_xinwenjieshuo_uranus_bigtts", name: "Nam Bản Tin (Thời Sự)", category: "Giọng Nam", gender: "Nam"),

        VoiceItem(id: "BV074_streaming", name: "Cô Gái Hoạt Ngôn", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "vi_female_huong", name: "Giọng Nữ Phổ Thông (Hương)", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "BV562_streaming", name: "Mai (Dịu Dàng)", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "multi_female_yangguangnv_uranus_bigtts", name: "Ban Mai (Nắng Mai)", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "vi-VN-HoaiMyNeural", name: "Hoài My (Truyền Cảm)", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "multi_female_kiwi_uranus_bigtts", name: "Sunny Idol (Tươi Trẻ)", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "multi_female_peiqi_uranus_bigtts", name: "Giọng Gái Mới Lớn", category: "Giọng Nữ", gender: "Nữ"),
        VoiceItem(id: "multi_female_tianmeijieshuo_uranus_bigtts", name: "Ngọt Ngào Tự Nhiên", category: "Giọng Nữ", gender: "Nữ"),

        VoiceItem(id: "multi_female_quanweinv_uranus_bigtts", name: "Bản Tin 1 (Trịnh Trọng)", category: "Bản Tin", gender: "Nữ"),
        VoiceItem(id: "multi_female_sisi_uranus_bigtts", name: "Bản Tin Nữ (Phát Thanh)", category: "Bản Tin", gender: "Nữ"),

        VoiceItem(id: "BV075_streaming_demon_dsp", name: "Kenny Đại Đế (Hùng Hồn)", category: "Độc Lạ / Hài", gender: "Đặc biệt"),
        VoiceItem(id: "BV560_streaming", name: "Alex Đại Đế", category: "Độc Lạ / Hài", gender: "Đặc biệt"),
        VoiceItem(id: "BV075_streaming_robot_dsp", name: "Robot VN (Khoa Học)", category: "Độc Lạ / Hài", gender: "Đặc biệt"),
        VoiceItem(id: "BV074_streaming_dsp", name: "Giọng Bé (Trẻ Con)", category: "Độc Lạ / Hài", gender: "Đặc biệt"),
        VoiceItem(id: "BV075_streaming_vibrato_dsp", name: "Việt Méo (Biến Âm Lạ)", category: "Độc Lạ / Hài", gender: "Đặc biệt")
    ]
}
