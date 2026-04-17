import Combine
import Darwin
import Foundation

@MainActor
public final class SkillStore: ObservableObject {
    @Published public private(set) var skills: [Skill] = []

    private let skillsDirectory: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var watchDescriptor: Int32 = -1

    public init(skillsDirectory: URL) {
        self.skillsDirectory = skillsDirectory
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
