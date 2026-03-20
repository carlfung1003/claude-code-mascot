import Cocoa

// MARK: - Menu Bar Controller

class MascotMenuBar {
    private let statusItem: NSStatusItem
    private let handler: MenuHandler
    private let menu: NSMenu
    private let stateFilePath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        stateFilePath = "\(home)/.claude/mascot/state.json"

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        handler = MenuHandler(stateFilePath: stateFilePath)
        menu = NSMenu()

        // Must configure button on main thread
        DispatchQueue.main.async { [self] in
            if let button = self.statusItem.button {
                button.title = "🐱"
                button.font = NSFont.systemFont(ofSize: 14)
            }
            self.buildMenu()
            self.statusItem.menu = self.menu
            self.startPolling()
        }
    }

    private func buildMenu() {
        let toggleItem = NSMenuItem(title: "Toggle Mascot", action: #selector(MenuHandler.toggleMascot), keyEquivalent: "m")
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = handler
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let sizeMenu = NSMenu()
        for (label, size) in [("Small (56)", 56), ("Medium (80)", 80), ("Large (100)", 100), ("XL (120)", 120)] {
            let item = NSMenuItem(title: label, action: #selector(MenuHandler.setSize(_:)), keyEquivalent: "")
            item.tag = size
            item.target = handler
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(NSMenuItem.separator())

        let sessionItem = NSMenuItem(title: "Sessions: --", action: nil, keyEquivalent: "")
        sessionItem.tag = 999
        menu.addItem(sessionItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "Restart Overlay", action: #selector(MenuHandler.restartOverlay), keyEquivalent: "r")
        restartItem.target = handler
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit Mascot", action: #selector(MenuHandler.quitAll), keyEquivalent: "q")
        quitItem.target = handler
        menu.addItem(quitItem)
    }

    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: self.stateFilePath)),
                  let dict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            else { return }

            let hidden = dict["hidden"] as? Bool ?? false
            let sessions = dict["sessions"] as? [String: Any] ?? [:]

            self.statusItem.button?.title = hidden ? "😺" : "🐱"

            if let item = self.menu.item(withTag: 999) {
                item.title = "Sessions: \(sessions.count)"
            }

            if let sMenu = self.menu.item(withTitle: "Size")?.submenu {
                let currentSize = Int(dict["mascotSize"] as? Double ?? 56)
                for item in sMenu.items {
                    item.state = item.tag == currentSize ? .on : .off
                }
            }
        }
    }
}

// MARK: - Menu Actions

class MenuHandler: NSObject {
    let stateFilePath: String

    init(stateFilePath: String) {
        self.stateFilePath = stateFilePath
    }

    @objc func toggleMascot() {
        updateState { data in
            let hidden = data["hidden"] as? Bool ?? false
            data["hidden"] = !hidden
        }
    }

    @objc func setSize(_ sender: NSMenuItem) {
        let size = sender.tag
        updateState { data in
            data["mascotSize"] = Double(size)
        }
    }

    @objc func restartOverlay() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let kill = Process()
        kill.launchPath = "/usr/bin/pkill"
        kill.arguments = ["-x", "ClaudeMascot"]
        try? kill.run()
        kill.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let launch = Process()
            launch.launchPath = "\(home)/.claude/mascot/ClaudeMascot"
            try? launch.run()
        }
    }

    @objc func quitAll() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-x", "ClaudeMascot"]
        try? task.run()
        NSApp.terminate(nil)
    }

    func updateState(_ modify: (inout [String: Any]) -> Void) {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
              var dict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
        else { return }
        modify(&dict)
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            try? jsonStr.write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        }
    }
}
