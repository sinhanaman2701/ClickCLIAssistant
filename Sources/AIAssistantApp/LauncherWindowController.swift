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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
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
        
        let size = NSSize(width: 560, height: 260)
        panel.setContentSize(size)
        panel.setFrame(centeredFrame(size: size), display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.proxy.focusSearch?()
        }
    }

    func showLoading(skillName: String, wordCount: Int) {
        proxy.resultTitle = skillName
        proxy.resultBody = "Thinking...\n(Ingesting \(wordCount) words)"
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            proxy.viewState = .loading
        }
        
        let size = NSSize(width: 560, height: 360)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(centeredFrame(size: size), display: true)
        }
    }

    func appendStreamedText(_ chunk: String) {
        if proxy.viewState == .loading || proxy.viewState == .error {
            proxy.resultBody = ""
            withAnimation(.snappy) {
                proxy.viewState = .streaming
            }
        }
        proxy.resultBody += chunk
    }

    func finishStreaming() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            proxy.viewState = .result
        }
    }

    func showError(_ error: String) {
        proxy.resultBody = error
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            proxy.viewState = .error
        }
        let size = NSSize(width: 560, height: 360)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(centeredFrame(size: size), display: true)
        }
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func centeredFrame(size: NSSize = NSSize(width: 560, height: 260)) -> NSRect {
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
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            } else {
                resultView
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var skillsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                TextField("Use Skill", text: $proxy.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                    .onSubmit {
                        proxy.submitSelection()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let status = proxy.status {
                Text(status)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }

            if !proxy.filteredSkills.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(proxy.filteredSkills.prefix(3).enumerated()), id: \.element.id) { index, skill in
                        Button {
                            proxy.onSelect?(skill)
                        } label: {
                            Text(skill.name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(index == proxy.selectedIndex ? Color.white.opacity(0.2) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 560, height: 260, alignment: .top)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if proxy.viewState == .loading || proxy.viewState == .streaming {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if proxy.viewState == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Text(proxy.resultTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 2)

            ScrollView {
                Text(proxy.resultBody)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(proxy.viewState == .error ? Color.red.opacity(0.9) : Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                    .padding(16)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(action: {
                    proxy.onReplace?()
                }) {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Replace")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(proxy.resultBody.isEmpty ? 0.3 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(proxy.viewState == .loading || proxy.viewState == .error || proxy.resultBody.isEmpty)
                .buttonStyle(.plain)

                Button(action: {
                    proxy.onCopy?()
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(proxy.viewState == .loading || proxy.resultBody.isEmpty)
                .buttonStyle(.plain)

                Button(action: {
                    proxy.onBack?()
                }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560, height: 360)
    }
}
