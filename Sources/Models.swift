import Foundation

public struct SubtitleCue: Identifiable, Codable {
    public var id: Int
    public var start_ms: Int
    public var end_ms: Int
    public var duration_ms: Int
    public var original_text: String
    public var translated_text: String

    public var timeFormatted: String {
        let s = start_ms / 1000
        let e = end_ms / 1000
        return String(format: "%02d:%02d - %02d:%02d", s / 60, s % 60, e / 60, e % 60)
    }
}

public struct MaskRect: Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var style: String

    public init(x: Double, y: Double, w: Double, h: Double, style: String = "box_semi") {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.style = style
    }
}

public struct TaskStatusResponse: Codable {
    public var success: Bool
    public var task_id: String?
    public var status: String?
    public var stage: String?
    public var percent: Int?
    public var msg: String?
    public var cues: [SubtitleCue]?
    public var download_url: String?
    public var error: String?
}

public struct RenderResult {
    public var url: URL
    public var renderTimeSec: Double
    public var speedRatio: Double

    public init(url: URL, renderTimeSec: Double = 0.0, speedRatio: Double = 1.0) {
        self.url = url
        self.renderTimeSec = renderTimeSec
        self.speedRatio = speedRatio
    }
}
