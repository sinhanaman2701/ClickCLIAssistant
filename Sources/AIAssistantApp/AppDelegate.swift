import AppKit
import AIAssistantKit
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let config = try ConfigStore.load()
            let controller = try AppController(config: config)
            controller.start()
            appController = controller
        } catch {
            let alert = NSAlert()
            alert.messageText = "AI Assistant Setup Required"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
