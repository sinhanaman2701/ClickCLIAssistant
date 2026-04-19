import Combine
import Darwin
import Foundation

@MainActor
public final class SkillStore: ObservableObject {
    @Published public private(set) var skills: [Skill] = []

    public let skillsDirectory: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var watchDescriptor: Int32 = -1

    public init(skillsDirectory: URL) {
        self.skillsDirectory = skillsDirectory
    }

    public func saveSkill(name: String, prompt: String) throws {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { throw AppError.missingConfig }
        let fileName = cleanedName.hasSuffix(".md") ? cleanedName : "\(cleanedName).md"
        let fileURL = skillsDirectory.appendingPathComponent(fileName)
        
        let contents = """
        # \(cleanedName)
        
        ## Description
        A custom skill generated via natural language prompt.
        
        ## Prompt
        \(prompt)
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        refresh()
    }

    public func deleteSkill(_ skill: Skill) throws {
        let fileURL = URL(fileURLWithPath: skill.sourceFile)
        try FileManager.default.removeItem(at: fileURL)
        refresh()
    }

    deinit {
        watcher?.cancel()
        if watchDescriptor >= 0 {
            close(watchDescriptor)
        }
    }

    public func start() {
        refresh()
        startWatcher()
    }

    public func refresh() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: skillsDirectory,
                includingPropertiesForKeys: nil
            )
            let parsed = try urls
                .filter { $0.pathExtension.lowercased() == "md" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .map(SkillParser.parse(url:))
            skills = parsed
        } catch {
            skills = []
        }
    }

    private func startWatcher() {
        watchDescriptor = open(skillsDirectory.path, O_EVTONLY)
        guard watchDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        watcher = source
        source.resume()
    }
}
