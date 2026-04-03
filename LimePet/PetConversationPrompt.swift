import AppKit

enum PetConversationPrompt {
    static func present(characterDisplayName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "和 \(characterDisplayName) 说句话"
        alert.informativeText = "这句会发给 Lime，由宿主侧当前可聊天模型生成回复。"
        alert.alertStyle = .informational

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        inputField.placeholderString = "比如：今天有点累，陪我聊两句"
        alert.accessoryView = inputField

        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
