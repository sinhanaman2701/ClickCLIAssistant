import AppKit
import AIAssistantKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var currentSelection: SelectionSnapshot?
    @Published private(set) var isRunningSkill = false
    @Published var previewText = ""
    @Published var errorMessage: String?

    let config: AppConfig
    let skillStore: SkillStore

    private let ollamaClient: OllamaClient
    private let popupController: PopupWindowController
    private let previewController: PreviewWindowController
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(config: AppConfig) throws {
        self.config = config
        let skillsURL = URL(fileURLWithPath: config.skillsDirectory, isDirectory: true)
        self.skillStore = SkillStore(skillsDirectory: skillsURL)
        guard let host = URL(string: config.ollamaHost) else {
            throw AppError.ollamaUnavailable("Invalid host \(config.ollamaHost)")
        }
        self.ollamaClient = OllamaClient(host: host, model: config.defaultModel)
        self.popupController = PopupWindowController()
        self.previewController = PreviewWindowController()
    }

    func start() {
        skillStore.start()
        popupController.bind(to: self, skillStore: skillStore)
        previewController.bind(to: self)

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollSelection()
            }
        }
        pollSelection()
    }

    func pollSelection() {
        guard SelectionReader.accessibilityTrusted() else {
            errorMessage = "Accessibility permission is required to read selected text."
            popupController.hide()
            return
        }

        guard let snapshot = SelectionReader.currentSelection(),
              snapshot.text.split(whereSeparator: \.isNewline).count < 1500,
              snapshot.text.split(whereSeparator: \.isWhitespace).count <= 1000 else {
            currentSelection = nil
            popupController.hide()
            return
        }

        guard snapshot != currentSelection else { return }
        currentSelection = snapshot
        popupController.show(near: snapshot.frame)
    }

    func run(skill: Skill) {
        guard let selection = currentSelection else { return }
        isRunningSkill = true
        errorMessage = nil

        Task {
            do {
                let output = try await ollamaClient.transform(text: selection.text, using: skill)
                await MainActor.run {
                    self.isRunningSkill = false
                    self.previewText = output
                    self.previewController.show()
                }
            } catch {
                await MainActor.run {
                    self.isRunningSkill = false
                    self.errorMessage = error.localizedDescription
                    self.previewText = ""
                    self.previewController.show()
                }
            }
        }
    }

    func copyPreviewToClipboard() {
        guard !previewText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewText, forType: .string)
    }
}
