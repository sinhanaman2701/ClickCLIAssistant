import AIAssistantKit
import Darwin
import Foundation

@main
struct ClickAssistantCLI {
    static func main() async {
        let command = CommandLine.arguments.dropFirst().first ?? "help"

        do {
            switch command {
            case "install":
                print("Click Assistant setup")
                let result = try await Installer.run()
                Installer.printSummary(result)
            case "run":
                if !AppLauncher.launchApp() {
                    throw AppError.missingConfig
                }
                print("AI Assistant app launched.")
            case "bridge":
                try await BridgeServer.run()
            case "doctor":
                let result = await Installer.doctor()
                printDoctor(result)
            case "uninstall":
                let force = CommandLine.arguments.contains("--yes")
                let result = try Uninstaller.run(force: force)
                printUninstall(result)
            case "help", "--help", "-h":
                printHelp()
            default:
                print("Unknown command: \(command)")
                printHelp()
                Darwin.exit(1)
            }
        } catch {
            fputs("Command failed: \(error.localizedDescription)\n", stderr)
            Darwin.exit(1)
        }
    }

    private static func printHelp() {
        print("""
        click-assistant <command>

        Commands:
          install   Run setup, verify Ollama model access, save config, and launch the app
          run       Launch the AI Assistant app
          bridge    Start the local browser bridge on 127.0.0.1:48765
          doctor    Check Ollama and config status
          uninstall Remove ClickCLIAssistant config, skills, and the default source clone
          help      Show this message

        Examples:
          swift run click-assistant install
          swift run click-assistant run
          swift run click-assistant bridge
          swift run click-assistant doctor
          swift run click-assistant uninstall
        """)
    }

    private static func printDoctor(_ result: DoctorResult) {
        print("Ollama installed: \(result.ollamaInstalled ? "yes" : "no")")
        print("Ollama path: \(result.ollamaPath ?? "not found")")
        print("Local Ollama reachable: \(result.localHostReachable ? "yes" : "no")")
        print("Config path: \(result.configPath)")
        print("Config exists: \(result.configExists ? "yes" : "no")")
    }

    private static func printUninstall(_ result: UninstallResult) {
        if result.removedPaths.isEmpty {
            print("Nothing was removed.")
            return
        }

        print("Removed:")
        for path in result.removedPaths {
            print("- \(path)")
        }
    }
}
