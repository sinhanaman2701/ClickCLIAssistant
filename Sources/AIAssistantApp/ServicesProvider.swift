import AppKit
import AIAssistantKit

@MainActor
final class ServicesProvider: NSObject {
    private weak var appController: AppController?

    init(appController: AppController) {
        self.appController = appController
    }

    @objc
    func useSkills(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selectedText = pboard.string(forType: .string), !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text available for ClickCLIAssistant."
            return
        }

        appController?.presentServiceSkillChooser(text: selectedText)
    }
}
