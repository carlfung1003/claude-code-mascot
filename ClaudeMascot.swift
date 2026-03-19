import Cocoa
import SwiftUI

// MARK: - Cat Characters (replacing emoji pool)

struct CatCharacter: Identifiable {
    let id: String
    let name: String
    let japaneseName: String
    let themeColor: Color

    func imagePath(for emotion: CatEmotion) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Projects/claude-mascot/media/cats/\(id)/\(emotion.rawValue).png"
    }

    func loadImage(for emotion: CatEmotion) -> NSImage? {
        let path = imagePath(for: emotion)
        return NSImage(contentsOfFile: path)
    }
}

let catPool: [CatCharacter] = [
    CatCharacter(id: "sakura", name: "Sakura", japaneseName: "桜", themeColor: Color(red: 1.0, green: 0.6, blue: 0.7)),
    CatCharacter(id: "kuro", name: "Kuro", japaneseName: "黒", themeColor: Color(red: 0.4, green: 0.3, blue: 0.5)),
    CatCharacter(id: "mochi", name: "Mochi", japaneseName: "餅", themeColor: Color(red: 1.0, green: 0.9, blue: 0.8)),
    CatCharacter(id: "tora", name: "Tora", japaneseName: "虎", themeColor: Color(red: 1.0, green: 0.6, blue: 0.2)),
    CatCharacter(id: "sora", name: "Sora", japaneseName: "空", themeColor: Color(red: 0.5, green: 0.6, blue: 0.9)),
]

func catForSession(_ sessionId: String) -> CatCharacter {
    let hash = abs(sessionId.hashValue)
    return catPool[hash % catPool.count]
}

// MARK: - Cat Emotions (mapped from session state)

enum CatEmotion: String {
    case neutral, focused, happy, frustrated, sleepy
}

// MARK: - State

enum MascotState: String, CaseIterable {
    case thinking, done, error, waiting, idle

    var priority: Int {
        switch self {
        case .error: return 5
        case .waiting: return 4
        case .thinking: return 3
        case .done: return 2
        case .idle: return 1
        }
    }

    var emotion: CatEmotion {
        switch self {
        case .thinking: return .focused
        case .done: return .happy
        case .error: return .frustrated
        case .waiting: return .neutral
        case .idle: return .sleepy
        }
    }

    var statusIcon: String {
        switch self {
        case .thinking: return "💭"
        case .done: return "✅"
        case .error: return "🔥"
        case .waiting: return "👋"
        case .idle: return ""
        }
    }

    var statusLabel: String {
        switch self {
        case .thinking: return "Working..."
        case .done: return "Done!"
        case .error: return "Error!"
        case .waiting: return "Need you!"
        case .idle: return "Idle"
        }
    }

    var bgColor: Color {
        return Color(red: 0.15, green: 0.15, blue: 0.15)
    }

    var glowColor: Color {
        switch self {
        case .thinking: return .indigo
        case .done: return .green
        case .error: return .red
        case .waiting: return .orange
        case .idle: return .gray
        }
    }
}

// MARK: - Session Model

struct SessionData: Identifiable {
    let id: String
    let state: MascotState
    let label: String
    let character: CatCharacter
    let timestamp: Double
    let sessionColor: Color?  // from /color
    let assignedCat: String?  // explicit cat assignment
}

struct SessionInfo: Codable {
    let state: String
    let timestamp: Double
    let label: String?
    let color: String?       // hex color from /color
    let cat: String?         // explicit cat name assignment
}

struct StateFile: Codable {
    var sessions: [String: SessionInfo]
    var mascotSize: Double?  // configurable size (default 48)
    var hidden: Bool?        // toggle visibility
}

// MARK: - Color Parsing

func parseHexColor(_ hex: String?) -> Color? {
    guard let hex = hex, !hex.isEmpty else { return nil }
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard clean.count == 6,
          let val = UInt64(clean, radix: 16) else { return nil }
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - Color Name Map

let colorNameMap: [String: String] = [
    "red": "#FF4444", "green": "#44BB44", "blue": "#4488FF",
    "yellow": "#FFD700", "orange": "#FF8C00", "purple": "#9966FF",
    "pink": "#FF69B4", "cyan": "#00CED1", "white": "#FFFFFF",
    "magenta": "#FF00FF", "lime": "#00FF00", "teal": "#008080",
    "indigo": "#4B0082", "violet": "#EE82EE", "coral": "#FF7F50",
    "salmon": "#FA8072", "gold": "#FFD700", "silver": "#C0C0C0",
    "crimson": "#DC143C", "turquoise": "#40E0D0",
]

// MARK: - Transcript Scanner

class TranscriptScanner {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var lastScanSizes: [String: UInt64] = [:]  // track file sizes to only read new content

    struct TranscriptInfo {
        var label: String?
        var color: String?  // hex
        var sessionId: String
    }

    /// Scan all recent transcript files for /color and /rename commands
    func scanTranscripts() -> [TranscriptInfo] {
        var results: [TranscriptInfo] = []
        let projectDir = "\(home)/.claude/projects/-Users-cfung"

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: projectDir) else {
            return results
        }

        for entry in entries {
            guard entry.hasSuffix(".jsonl") else { continue }
            let path = "\(projectDir)/\(entry)"
            let sessionId = entry.replacingOccurrences(of: ".jsonl", with: "")

            // Check file size — skip if unchanged
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? UInt64 else { continue }

            // Only scan files modified in last 8 hours
            if let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > 28800 { continue }

            var label: String? = nil
            var color: String? = nil

            guard let fileHandle = FileHandle(forReadingAtPath: path) else { continue }
            defer { fileHandle.closeFile() }

            let data = fileHandle.readDataToEndOfFile()
            guard let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let entryType = entry["type"] as? String
                else { continue }

                // Format 1: direct metadata entries (written immediately by /rename and /color)
                if entryType == "custom-title" || entryType == "agent-name" {
                    if let name = entry["customTitle"] as? String ?? entry["agentName"] as? String {
                        label = name
                    }
                }
                if entryType == "agent-color" {
                    if let colorName = (entry["agentColor"] as? String)?.lowercased() {
                        if colorName.hasPrefix("#") {
                            color = colorName
                        } else {
                            color = colorNameMap[colorName]
                        }
                    }
                }

                // Format 2: local_command stdout (legacy/hook-based)
                if entryType == "system",
                   entry["subtype"] as? String == "local_command",
                   let raw = entry["content"] as? String,
                   raw.contains("local-command-stdout") {

                    if let range = raw.range(of: "Session renamed to: ") {
                        let start = range.upperBound
                        let rest = raw[start...]
                        if let end = rest.range(of: "</local-command-stdout>") ?? rest.range(of: "<") {
                            label = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                        }
                    }

                    if let range = raw.range(of: "Session color set to: ") {
                        let start = range.upperBound
                        let rest = raw[start...]
                        if let end = rest.range(of: "</local-command-stdout>") ?? rest.range(of: "<") {
                            let colorName = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
                            if colorName.hasPrefix("#") {
                                color = colorName
                            } else {
                                color = colorNameMap[colorName]
                            }
                        }
                    }
                }
            }

            if label != nil || color != nil {
                results.append(TranscriptInfo(label: label, color: color, sessionId: sessionId))
            }
        }
        return results
    }
}

// MARK: - State Manager

class StateManager: ObservableObject {
    @Published var sessions: [SessionData] = []
    @Published var mascotSize: CGFloat = 56
    @Published var hidden: Bool = false

    private var timer: Timer?
    private var transcriptTimer: Timer?
    private let stateFilePath: String
    private let transcriptScanner = TranscriptScanner()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        stateFilePath = "\(home)/.claude/mascot/state.json"
    }

    func startMonitoring() {
        readState()
        // Poll state.json every 0.5s
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.readState()
        }
        // Scan transcripts every 2s for /color and /rename changes
        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.syncFromTranscripts()
        }
    }

    private func syncFromTranscripts() {
        let infos = transcriptScanner.scanTranscripts()
        guard !infos.isEmpty else { return }

        // Read current state
        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
              var stateDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sessions = stateDict["sessions"] as? [String: [String: Any]]
        else { return }

        var changed = false

        for info in infos {
            // Find matching session by sessionId or label
            var targetKey: String? = nil

            // Direct session ID match
            if sessions[info.sessionId] != nil {
                targetKey = info.sessionId
            } else if let label = info.label {
                // Match by label
                targetKey = sessions.first(where: { ($0.value["label"] as? String) == label })?.key
            }

            guard let key = targetKey else { continue }
            var session = sessions[key] ?? [:]

            if let color = info.color, (session["color"] as? String) != color {
                session["color"] = color
                changed = true
            }
            if let label = info.label, (session["label"] as? String) != label {
                session["label"] = label
                changed = true
            }

            sessions[key] = session
        }

        if changed {
            stateDict["sessions"] = sessions
            if let jsonData = try? JSONSerialization.data(withJSONObject: stateDict),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                let tmp = stateFilePath + ".tmp"
                try? jsonStr.write(toFile: tmp, atomically: true, encoding: .utf8)
                _ = try? FileManager.default.replaceItemAt(
                    URL(fileURLWithPath: stateFilePath),
                    withItemAt: URL(fileURLWithPath: tmp)
                )
            }
        }
    }

    private func readState() {
        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath))
        else {
            DispatchQueue.main.async { self.sessions = [] }
            return
        }

        // Use JSONSerialization for robustness (Codable fails on extra/missing keys)
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DispatchQueue.main.async { self.sessions = [] }
            return
        }

        // Parse hidden + size from top level
        let isHidden = raw["hidden"] as? Bool ?? false
        let size = CGFloat(raw["mascotSize"] as? Double ?? 56)

        // Parse sessions
        guard let sessionsDict = raw["sessions"] as? [String: [String: Any]] else {
            DispatchQueue.main.async {
                self.sessions = []
                self.hidden = isHidden
                self.mascotSize = max(32, min(120, size))
            }
            return
        }

        let stateFile = StateFile(
            sessions: sessionsDict.mapValues { val in
                SessionInfo(
                    state: val["state"] as? String ?? "idle",
                    timestamp: val["timestamp"] as? Double ?? 0,
                    label: val["label"] as? String,
                    color: val["color"] as? String,
                    cat: val["cat"] as? String
                )
            },
            mascotSize: raw["mascotSize"] as? Double,
            hidden: isHidden
        )

        let now = Date().timeIntervalSince1970
        let active = stateFile.sessions
            .filter { now - $0.value.timestamp < 28800 }  // 8 hours
            .map { (key, value) in
                // Resolve cat: explicit assignment > hash-based
                let cat: CatCharacter
                if let assignedName = value.cat,
                   let found = catPool.first(where: { $0.id == assignedName.lowercased() }) {
                    cat = found
                } else {
                    cat = catForSession(key)
                }

                return SessionData(
                    id: key,
                    state: MascotState(rawValue: value.state) ?? .idle,
                    label: value.label ?? "unknown",
                    character: cat,
                    timestamp: value.timestamp,
                    sessionColor: parseHexColor(value.color),
                    assignedCat: value.cat
                )
            }
            .sorted { $0.label.lowercased() < $1.label.lowercased() }

        DispatchQueue.main.async {
            self.sessions = active
            self.mascotSize = max(32, min(120, size))
            self.hidden = isHidden
        }
    }
}

// MARK: - Animation Modifiers

struct BounceEffect: ViewModifier {
    @State private var animating = false
    func body(content: Content) -> some View {
        content
            .offset(y: animating ? -6 : 2)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}

struct PulseEffect: ViewModifier {
    @State private var animating = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(animating ? 1.08 : 0.95)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}

struct ShakeEffect: ViewModifier {
    @State private var animating = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(animating ? 5 : -5))
            .animation(
                .easeInOut(duration: 0.15).repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}

struct SparkleEffect: ViewModifier {
    @State private var animating = false
    func body(content: Content) -> some View {
        content
            .opacity(animating ? 1.0 : 0.4)
            .scaleEffect(animating ? 1.2 : 0.8)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - Cat Image View

struct CatImageView: View {
    let character: CatCharacter
    let emotion: CatEmotion
    let size: CGFloat

    var body: some View {
        if let nsImage = character.loadImage(for: emotion) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Fallback: show cat name if image not found
            Text(character.japaneseName)
                .font(.system(size: size * 0.5))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Single Session Mascot

struct SessionMascotView: View {
    let session: SessionData
    let mascotSize: CGFloat
    @State private var isHovering = false

    private var glowColor: Color {
        session.sessionColor ?? session.state.glowColor
    }

    var body: some View {
        VStack(spacing: 2) {
            // Tooltip on hover
            if isHovering {
                tooltipView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ZStack {
                // Glow ring — uses session /color if set
                Circle()
                    .stroke(glowColor.opacity(0.6), lineWidth: 2.5)
                    .frame(width: mascotSize + 8, height: mascotSize + 8)
                    .blur(radius: 3)

                // Background circle
                Circle()
                    .fill(session.state.bgColor)
                    .frame(width: mascotSize + 4, height: mascotSize + 4)
                    .shadow(color: glowColor.opacity(0.4), radius: 6)

                // Cat image with state animation
                characterView

                // Status icon
                if session.state != .idle {
                    Text(session.state.statusIcon)
                        .font(.system(size: mascotSize * 0.22))
                        .offset(x: mascotSize * 0.38, y: -(mascotSize * 0.38))
                        .modifier(SparkleEffect())
                }
            }

            // Project label
            Text(session.label)
                .font(.system(size: max(7, mascotSize * 0.13), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: mascotSize + 20)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    var characterView: some View {
        let emotion = session.state.emotion
        let catImage = CatImageView(
            character: session.character,
            emotion: emotion,
            size: mascotSize * 0.85
        )

        switch session.state {
        case .thinking:
            catImage.modifier(BounceEffect())
        case .done:
            catImage.modifier(PulseEffect())
        case .error:
            catImage.modifier(ShakeEffect())
        case .waiting:
            catImage.modifier(PulseEffect())
        case .idle:
            catImage.opacity(0.6)
        }
    }

    var tooltipView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(session.character.name) (\(session.character.japaneseName))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(session.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 4) {
                Text(session.state.statusIcon)
                    .font(.system(size: 10))
                Text(session.state.statusLabel)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(glowColor)
            }
            if session.assignedCat != nil {
                Text("🐱 \(session.character.id)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.15))
                .shadow(color: .black.opacity(0.4), radius: 4)
        )
        .padding(.bottom, 2)
    }
}

// MARK: - Main View (stacks all sessions)

struct MascotView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        VStack(spacing: 6) {
            ForEach(stateManager.sessions) { session in
                SessionMascotView(session: session, mascotSize: stateManager.mascotSize)
            }
        }
        .padding(6)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var stateManager = StateManager()
    private var lastCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let rootView = MascotView(stateManager: stateManager)
        let hostingView = NSHostingView(rootView: rootView)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true

        positionPanel()
        panel.orderOut(nil)

        stateManager.startMonitoring()

        // Resize and show/hide based on sessions + hidden flag
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let count = self.stateManager.sessions.count
            let size = self.stateManager.mascotSize
            let isHidden = self.stateManager.hidden

            // Hide/show based on hidden flag
            if isHidden {
                self.panel.orderOut(nil)
                return
            }

            if count > 0 {
                let itemHeight = size + 30  // image + label + spacing
                let height = CGFloat(count) * itemHeight + 12
                let width = max(80, size + 40)
                var frame = self.panel.frame
                let oldHeight = frame.height
                frame.size.height = height
                frame.size.width = width
                frame.origin.y += (oldHeight - height)
                self.panel.setFrame(frame, display: true)

                if self.lastCount == 0 || !self.panel.isVisible {
                    self.positionPanel()
                    self.panel.orderFront(nil)
                }
            } else if count == 0 && self.lastCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.stateManager.sessions.isEmpty {
                        self.panel.orderOut(nil)
                    }
                }
            }
            self.lastCount = count
        }
    }

    func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let size = stateManager.mascotSize
        let count = max(stateManager.sessions.count, 1)
        let itemHeight = size + 30
        let height = CGFloat(count) * itemHeight + 12
        let width = max(80, size + 40)
        let x = visibleFrame.maxX - width - 10
        let y = visibleFrame.minY + 20
        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true
        )
    }

}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

app.run()
