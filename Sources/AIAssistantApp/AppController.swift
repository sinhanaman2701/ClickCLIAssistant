import AppKit
import AIAssistantKit
import Combine
import Foundation

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var currentSelection: SelectionSnapshot?

    let config: AppConfig
    let skillStore: SkillStore

    private let ollamaClient: OllamaClient
    private let launcherController: LauncherWindowController
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var lastOutput: String = ""
    private var isRunningSkill = false

    init(config: AppConfig) throws {
        self.config = config
        let skillsURL = URL(fileURLWithPath: config.skillsDirectory, isDirectory: true)
        self.skillStore = SkillStore(skillsDirectory: skillsURL)
        guard let host = URL(string: config.ollamaHost) else {
            throw AppError.ollamaUnavailable("Invalid host \(config.ollamaHost)")
        }
        self.ollamaClient = OllamaClient(host: host, model: config.defaultModel)
        self.launcherController = LauncherWindowController()
    }

    func start() {
        _ = SelectionReader.accessibilityTrusted(promptIfNeeded: true)
        skillStore.start()
        
        launcherController.bind { [weak self] skill in
            self?.run(skill: skill)
        }
        launcherController.proxy.onCopy = { [weak self] in
            self?.copyResultToClipboard()
        }
        launcherController.proxy.onReplace = { [weak self] in
            self?.replaceSelectionWithResult()
        }
        launcherController.proxy.onBack = { [weak self] in
            Task { @MainActor in
                await self?.showLauncher()
            }
        }
        
        hotKeyMonitor = GlobalHotKeyMonitor { [weak self] in
            Task { @MainActor in
                await self?.showLauncher()
            }
        }
        hotKeyMonitor?.start()
    }

    private func showLauncher() async {
        guard SelectionReader.accessibilityTrusted() else {
            launcherController.show(skills: skillStore.skills, status: "Enable Accessibility permission for this app first.")
            return
        }

        guard let snapshot = await SelectionReader.currentSelectionWithClipboardFallback(),
              isReasonableSelection(snapshot.text) else {
            currentSelection = nil
            launcherController.show(skills: skillStore.skills, status: "Select text first, then press Cmd+Shift+Space.")
            return
        }

        currentSelection = snapshot
        launcherController.show(skills: skillStore.skills, status: nil)
    }

    private func run(skill: Skill) {
        guard !isRunningSkill else { return }
        guard let selection = currentSelection else {
            launcherController.show(skills: skillStore.skills, status: "No selected text available.")
            return
        }
        
        // Remove .hide() so we stay in the same window, just transitioning state
        isRunningSkill = true
        launcherController.showLoading(skillName: skill.name)

        Task {
            do {
                let stream = ollamaClient.transform(text: selection.text, using: skill)
                var fullText = ""
                for try await chunk in stream {
                    fullText += chunk
                    await MainActor.run {
                        self.launcherController.appendStreamedText(chunk)
                    }
                }
                
                await MainActor.run {
                    self.isRunningSkill = false
                    self.lastOutput = fullText
                    self.launcherController.finishStreaming()
                }
            } catch {
                await MainActor.run {
                    self.isRunningSkill = false
                    self.lastOutput = ""
                    self.launcherController.showError(error.localizedDescription)
                }
            }
        }
    }

    private func copyResultToClipboard() {
        guard !lastOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastOutput, forType: .string)
        // Optionally close it or reset
        launcherController.hide()
    }

    private func replaceSelectionWithResult() {
        guard !lastOutput.isEmpty else { return }
        let replaced = SelectionReader.replaceSelectedText(with: lastOutput)
        if !replaced {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lastOutput, forType: .string)
        }
        // Close window immediately on replace to remain seamless
        launcherController.hide()
    }

    // Compatibility shim for older preview controller wiring.
    func copyPreviewToClipboard() {
        copyResultToClipboard()
    }

    // Compatibility shim for older popup controller wiring.
    func showSkillMenu() {
        Task { @MainActor in
            await showLauncher()
        }
    }

    private func isReasonableSelection(_ text: String) -> Bool {
        if text.utf16.count > 12_000 { return false }
        var lines = 1
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines += 1
                if lines >= 1_500 { return false }
            }
        }
        return true
    }
}
