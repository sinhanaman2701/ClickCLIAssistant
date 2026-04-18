import AppKit
import AIAssistantKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController {
    let proxy = LauncherProxyController()
    private let panel: NSPanel
    private let hostingView: NSHostingView<LauncherRootView>
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?

    init() {
        self.hostingView = NSHostingView(rootView: LauncherRootView(proxy: proxy))
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.contentView = hostingView
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func bind(onSelect: @escaping (Skill) -> Void) {
        proxy.onSelect = onSelect
    }

    func show(skills: [Skill], status: String? = nil) {
        proxy.skills = skills
        proxy.query = ""
        proxy.status = status
        proxy.selectedIndex = 0
        proxy.viewState = .skills
        
        let size = NSSize(width: 520, height: 260)
        panel.setContentSize(size)
        panel.setFrame(centeredFrame(size: size), display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.proxy.focusSearch?()
        }
    }

    func showLoading(skillName: String) {
        proxy.resultTitle = skillName
        proxy.resultBody = "Working on it..."
        proxy.viewState = .loading
        let size = NSSize(width: 560, height: 350)
        panel.setContentSize(size)
        panel.setFrame(centeredFrame(size: size), display: true)
    }

    func appendStreamedText(_ chunk: String) {
        if proxy.viewState == .loading || proxy.viewState == .error {
            proxy.resultBody = ""
            proxy.viewState = .streaming
        }
        proxy.resultBody += chunk
    }

    func finishStreaming() {
        proxy.viewState = .result
    }

    func showError(_ error: String) {
        proxy.resultBody = error
        proxy.viewState = .error
        let size = NSSize(width: 560, height: 350)
        panel.setContentSize(size)
        panel.setFrame(centeredFrame(size: size), display: true)
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func centeredFrame(size: NSSize = NSSize(width: 520, height: 260)) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 300, y: 300, width: size.width, height: size.height)
        }
        let frame = screen.visibleFrame
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            if !self.panel.frame.contains(point) {
                self.hide()
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let point = NSEvent.mouseLocation
                if !self.panel.frame.contains(point) {
                    self.hide()
                }
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
                    self.hide()
                }
            }
        }
    }

    private func removeDismissMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }
}

@MainActor
final class LauncherProxyController: ObservableObject {
    enum ViewState {
        case skills
        case loading
        case streaming
        case result
        case error
    }

    @Published var viewState: ViewState = .skills
    @Published var query = ""
    @Published var skills: [Skill] = []
    @Published var status: String?
    @Published var selectedIndex = 0

    @Published var resultTitle = ""
    @Published var resultBody = ""

    var onSelect: ((Skill) -> Void)?
    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
    var onBack: (() -> Void)?
    var focusSearch: (() -> Void)?

    var filteredSkills: [Skill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return skills }
        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(q)
            || (skill.description?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    func moveSelection(delta: Int) {
        let count = filteredSkills.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    func submitSelection() {
        let filtered = filteredSkills
        guard !filtered.isEmpty else { return }
        let index = max(0, min(filtered.count - 1, selectedIndex))
        onSelect?(filtered[index])
    }
}

private struct LauncherRootView: View {
    @ObservedObject var proxy: LauncherProxyController
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if proxy.viewState == .skills {
                skillsView
            } else {
                resultView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.28, green: 0.30, blue: 0.35), Color(red: 0.20, green: 0.21, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var skillsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                TextField("Use Skill", text: $proxy.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                    .onSubmit {
                        proxy.submitSelection()
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.14), in: Capsule())

            if let status = proxy.status {
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 8) {
                ForEach(Array(proxy.filteredSkills.prefix(3).enumerated()), id: \.element.id) { index, skill in
                    Button {
                        proxy.onSelect?(skill)
                    } label: {
                        Text(skill.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                index == proxy.selectedIndex
                                    ? Color.white.opacity(0.22)
                                    : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 520, height: 260, alignment: .top)
        .onAppear {
            proxy.focusSearch = {
                searchFocused = true
            }
            searchFocused = true
        }
        .onChange(of: proxy.query) { _ in
            proxy.selectedIndex = 0
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                proxy.moveSelection(delta: 1)
            case .up:
                proxy.moveSelection(delta: -1)
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proxy.resultTitle)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Divider()
                .overlay(Color.white.opacity(0.2))

            ScrollView {
                Text(proxy.resultBody)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(proxy.viewState == .error ? Color.red.opacity(0.85) : Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(action: {
                    proxy.onReplace?()
                }) {
                    Text("Replace")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .disabled(proxy.viewState == .loading || proxy.viewState == .error || proxy.resultBody.isEmpty)
                .buttonStyle(.borderedProminent)

                Button(action: {
                    proxy.onCopy?()
                }) {
                    Text("Copy")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .disabled(proxy.viewState == .loading || proxy.resultBody.isEmpty)
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    proxy.onBack?()
                }) {
                    Text("Back")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 560, height: 350)
    }
}
