import Cocoa

let stateFilePath = "/Users/cfung/.claude/mascot/state.json"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "🐱"

// Menu actions handler
class MenuHandler: NSObject {
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

    @objc func resetPosition() {
        // Touch state to trigger repositioning
        updateState { _ in }
    }

    @objc func quitAll() {
        // Kill the mascot overlay too
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", "ClaudeMascot"]
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

let handler = MenuHandler()

let menu = NSMenu()

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

let quitItem = NSMenuItem(title: "Quit Mascot", action: #selector(MenuHandler.quitAll), keyEquivalent: "q")
quitItem.target = handler
menu.addItem(quitItem)

statusItem.menu = menu

// Poll state.json to update icon + session count
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
          let dict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
    else { return }

    let hidden = dict["hidden"] as? Bool ?? false
    let sessions = dict["sessions"] as? [String: Any] ?? [:]

    statusItem.button?.title = hidden ? "😺" : "🐱"

    if let item = menu.item(withTag: 999) {
        item.title = "Sessions: \(sessions.count)"
    }

    if let sMenu = menu.item(withTitle: "Size")?.submenu {
        let currentSize = Int(dict["mascotSize"] as? Double ?? 56)
        for item in sMenu.items {
            item.state = item.tag == currentSize ? .on : .off
        }
    }
}

app.run()
