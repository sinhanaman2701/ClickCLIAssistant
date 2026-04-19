import AppKit
import AIAssistantKit
import Combine
import Foundation
import SwiftUI

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
    private var cancellables = Set<AnyCancellable>()

    init(config: AppConfig) throws {
        self.config = config
        let skillsURL = URL(fileURLWithPath: config.skillsDirectory, isDirectory: true)
        self.skillStore = SkillStore(skillsDirectory: skillsURL)
        guard let host = URL(string: config.ollamaHost) else {
            throw AppError.ollamaUnavailable("Invalid host \(config.ollamaHost)")
        }
        self.ollamaClient = OllamaClient(host: host, model: config.defaultModel, apiKey: config.apiKey)
        self.launcherController = LauncherWindowController()
    }

    func start() {
        _ = SelectionReader.accessibilityTrusted(promptIfNeeded: true)
        skillStore.start()
        
        skillStore.$skills
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSkills in
                self?.launcherController.proxy.skills = newSkills
            }
            .store(in: &cancellables)
        
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
                if self?.launcherController.proxy.viewState == .createInput {
                    self?.launcherController.proxy.viewState = .skills
                } else {
                    await self?.showLauncher()
                }
            }
        }

        launcherController.proxy.onStartCreate = { [weak self] in
            Task { @MainActor in
                guard let proxy = self?.launcherController.proxy else { return }
                proxy.newSkillName = ""
                proxy.newSkillDescription = ""
                proxy.newSkillPrompt = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.viewState = .createInput
                }
            }
        }

        launcherController.proxy.onGeneratePrompt = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                withAnimation(.spring()) {
                    self.launcherController.proxy.viewState = .createGenerating
                }
                
                let desc = self.launcherController.proxy.newSkillDescription
                self.launcherController.proxy.newSkillPrompt = ""
                
                do {
                    let stream = self.ollamaClient.generateSkillPrompt(description: desc)
                    
                    withAnimation(.spring()) {
                        self.launcherController.proxy.viewState = .createReview
                    }
                    
                    for try await chunk in stream {
                        self.launcherController.proxy.newSkillPrompt += chunk
                    }
                } catch {
                    self.launcherController.showError("Failed to generate prompt: \(error.localizedDescription)")
                }
            }
        }

        launcherController.proxy.onSaveSkill = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let name = self.launcherController.proxy.newSkillName
                let prompt = self.launcherController.proxy.newSkillPrompt
                do {
                    try self.skillStore.saveSkill(name: name, prompt: prompt)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.launcherController.proxy.viewState = .skills
                    }
                } catch {
                    self.launcherController.showError("Failed to save skill: \(error.localizedDescription)")
                }
            }
        }

        launcherController.proxy.onDeleteSkill = { [weak self] skill in
            Task { @MainActor in
                guard let self = self else { return }
                do {
                    try self.skillStore.deleteSkill(skill)
                } catch {
                    self.launcherController.showError("Failed to delete skill: \(error.localizedDescription)")
                }
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
        let launchStart = Date()
        try? String("[\(Date())] Triggering showLauncher...\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
        
        guard SelectionReader.accessibilityTrusted() else {
            launcherController.show(skills: skillStore.skills, status: "Enable Accessibility permission for this app first.")
            return
        }

        try? String("[\(Date())] Starting SelectionReader... (+ \(-launchStart.timeIntervalSinceNow)s)\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
        guard let snapshot = await SelectionReader.currentSelectionWithClipboardFallback(),
              isReasonableSelection(snapshot.text) else {
            currentSelection = nil
            launcherController.show(skills: skillStore.skills, status: "Select text first, then press Cmd+Shift+Space.")
            return
        }

        currentSelection = snapshot
        try? String("[\(Date())] Selection gathered! Length: \(snapshot.text.count) (+ \(-launchStart.timeIntervalSinceNow)s)\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
        launcherController.show(skills: skillStore.skills, status: nil)
    }

    private func run(skill: Skill) {
        print("[AppController] Attempting to run skill: \(skill.name)")
        if isRunningSkill {
            print("[AppController] Skill already running, ignoring request.")
            return
        }
        guard let selection = currentSelection else {
            print("[AppController] No current selection, cannot run skill.")
            launcherController.show(skills: skillStore.skills, status: "No selected text available.")
            return
        }
        
        // Remove .hide() so we stay in the same window, just transitioning state
        isRunningSkill = true
        let wordCount = selection.text.split(separator: .init(" ")).count
        launcherController.showLoading(skillName: skill.name, wordCount: wordCount)

        Task {
            let runStart = Date()
            try? String("[\(Date())] Calling OllamaClient.transform... (+ \(-runStart.timeIntervalSinceNow)s)\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
            do {
                let stream = ollamaClient.transform(text: selection.text, using: skill)
                var fullText = ""
                var buffer = ""
                var lastRender = Date()
                var chunkCount = 0
                
                print("[AppController] Starting stream capture for text block length: \(selection.text.count)")
                for try await chunk in stream {
                    if chunkCount == 0 {
                        try? String("[\(Date())] Received FIRST token: \(chunk.debugDescription) (+ \(-runStart.timeIntervalSinceNow)s)\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
                        print("[AppController] Received FIRST token: \(chunk.debugDescription)")
                    }
                    chunkCount += 1
                    fullText += chunk
                    buffer += chunk
                    
                    if Date().timeIntervalSince(lastRender) > 0.05 {
                        let toRender = buffer
                        buffer = ""
                        lastRender = Date()
                        await MainActor.run {
                            self.launcherController.appendStreamedText(toRender)
                        }
                    }
                }
                
                try? String("[\(Date())] Stream finished successfully. Total chunks: \(chunkCount) (+ \(-runStart.timeIntervalSinceNow)s)\n").write(toFile: "/tmp/app_flow.log", atomically: false, encoding: .utf8)
                print("[AppController] Stream finished successfully. Total chunks: \(chunkCount)")
                // Flush any remaining
                if !buffer.isEmpty {
                    let toRender = buffer
                    await MainActor.run {
                        self.launcherController.appendStreamedText(toRender)
                    }
                }
                
                await MainActor.run {
                    self.isRunningSkill = false
                    self.lastOutput = fullText
                    self.launcherController.finishStreaming()
                }
            } catch {
                print("[AppController] Stream execution failed! Error: \(error.localizedDescription)")
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
        // Limits removed as per user request. 
        // Note: Very large selections may take longer to process and hit model context limits.
        return true
    }
}
