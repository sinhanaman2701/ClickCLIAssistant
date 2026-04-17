import AIAssistantKit
import Darwin
import Foundation

@main
struct AIAssistantInstallMain {
    static func main() async {
        do {
            print("AI Assistant setup")
            let result = try await Installer.run()
            Installer.printSummary(result)
        } catch {
            fputs("Installation failed: \(error.localizedDescription)\n", stderr)
            Darwin.exit(1)
        }
    }
}
