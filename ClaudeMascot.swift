import Cocoa
import SwiftUI

// MARK: - Character Pool

struct MascotCharacter {
    let emoji: String
    let errorEmoji: String
    let name: String
}

let characterPool: [MascotCharacter] = [
    MascotCharacter(emoji: "🐯", errorEmoji: "🙀", name: "Tiger"),
    MascotCharacter(emoji: "🦊", errorEmoji: "😵", name: "Fox"),
    MascotCharacter(emoji: "🐼", errorEmoji: "😰", name: "Panda"),
    MascotCharacter(emoji: "🐙", errorEmoji: "😱", name: "Octo"),
    MascotCharacter(emoji: "🦁", errorEmoji: "🤯", name: "Leo"),
    MascotCharacter(emoji: "🐸", errorEmoji: "💀", name: "Frog"),
    MascotCharacter(emoji: "🐉", errorEmoji: "🔥", name: "Dragon"),
    MascotCharacter(emoji: "🦄", errorEmoji: "😤", name: "Uni"),
    MascotCharacter(emoji: "🐨", errorEmoji: "😵‍💫", name: "Koala"),
    MascotCharacter(emoji: "🐺", errorEmoji: "🫠", name: "Wolf"),
]

func characterForSession(_ sessionId: String) -> MascotCharacter {
    let hash = abs(sessionId.hashValue)
    return characterPool[hash % characterPool.count]
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
        switch self {
        case .thinking: return Color(red: 0.2, green: 0.2, blue: 0.35)
        case .done: return Color(red: 0.15, green: 0.3, blue: 0.15)
        case .error: return Color(red: 0.35, green: 0.12, blue: 0.12)
        case .waiting: return Color(red: 0.35, green: 0.28, blue: 0.1)
        case .idle: return Color(red: 0.2, green: 0.2, blue: 0.2)
        }
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
    let character: MascotCharacter
    let timestamp: Double
}

struct SessionInfo: Codable {
    let state: String
    let timestamp: Double
    let label: String?
}

struct StateFile: Codable {
    var sessions: [String: SessionInfo]
}

// MARK: - State Manager

class StateManager: ObservableObject {
    @Published var sessions: [SessionData] = []

    private var timer: Timer?
    private let stateFilePath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        stateFilePath = "\(home)/.claude/mascot/state.json"
    }

    func startMonitoring() {
        readState()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.readState()
        }
    }

    private func readState() {
        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
              let stateFile = try? JSONDecoder().decode(StateFile.self, from: data)
        else {
            DispatchQueue.main.async { self.sessions = [] }
            return
        }

        let now = Date().timeIntervalSince1970
        let active = stateFile.sessions
            .filter { now - $0.value.timestamp < 120 }
            .map { (key, value) in
                SessionData(
                    id: key,
                    state: MascotState(rawValue: value.state) ?? .idle,
                    label: value.label ?? "unknown",
                    character: characterForSession(key),
                    timestamp: value.timestamp
                )
            }
            .sorted { $0.timestamp < $1.timestamp } // oldest first = bottom

        DispatchQueue.main.async { self.sessions = active }
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

// MARK: - Single Session Mascot

struct SessionMascotView: View {
    let session: SessionData
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 2) {
            // Tooltip on hover
            if isHovering {
                tooltipView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ZStack {
                // Glow ring
                Circle()
                    .stroke(session.state.glowColor.opacity(0.6), lineWidth: 2.5)
                    .frame(width: 52, height: 52)
                    .blur(radius: 3)

                // Background circle
                Circle()
                    .fill(session.state.bgColor)
                    .frame(width: 48, height: 48)
                    .shadow(color: session.state.glowColor.opacity(0.4), radius: 6)

                // Character with state animation
                characterView

                // Status icon
                if session.state != .idle {
                    Text(session.state.statusIcon)
                        .font(.system(size: 12))
                        .offset(x: 18, y: -18)
                        .modifier(SparkleEffect())
                }
            }

            // Project label
            Text(session.label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    var characterView: some View {
        let face = session.state == .error
            ? session.character.errorEmoji
            : session.character.emoji
        let emoji = Text(face).font(.system(size: 24))

        switch session.state {
        case .thinking:
            emoji.modifier(BounceEffect())
        case .done:
            emoji.modifier(PulseEffect())
        case .error:
            emoji.modifier(ShakeEffect())
        case .waiting:
            emoji.modifier(PulseEffect())
        case .idle:
            emoji.opacity(0.6)
        }
    }

    var tooltipView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(session.character.emoji)
                    .font(.system(size: 10))
                Text(session.character.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(session.label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Text(session.state.statusLabel)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(session.state.glowColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
                SessionMascotView(session: session)
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
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 600),
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

        // Resize and show/hide based on sessions
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let count = self.stateManager.sessions.count

            if count > 0 {
                // Resize panel height based on session count
                let height = CGFloat(count) * 76 + 12
                var frame = self.panel.frame
                let oldHeight = frame.height
                frame.size.height = height
                // Keep bottom edge anchored
                frame.origin.y += (oldHeight - height)
                self.panel.setFrame(frame, display: true)

                if self.lastCount == 0 {
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
        let count = max(stateManager.sessions.count, 1)
        let height = CGFloat(count) * 76 + 12
        let x = visibleFrame.maxX - 90
        let y = visibleFrame.minY + 20
        panel.setFrame(
            NSRect(x: x, y: y, width: 80, height: height),
            display: true
        )
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
