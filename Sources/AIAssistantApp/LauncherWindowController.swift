import AppKit
import AIAssistantKit
import Combine
import SwiftUI

// A native NSTextView wrapper with built-in placeholder support.
private class PlaceholderTextView: NSTextView {
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    // The panel uses .nonactivatingPanel so it never becomes key window.
    // That prevents Cmd+V/C/X/A from reaching the responder chain.
    // We intercept them manually here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "z":
            if event.modifierFlags.contains(.shift) {
                return NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
            }
            return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        NSString(string: placeholder).draw(
            in: bounds,
            withAttributes: attrs
        )
    }
}

private struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: 15)
    var isDisabled: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.isEditable = !isDisabled
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = font
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        textView.isEditable = !isDisabled
        textView.font = font
        textView.placeholder = placeholder
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            tv.needsDisplay = true
        }
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

@MainActor
final class LauncherWindowController: NSWindowController {
    let proxy = LauncherProxyController()
    private let panel: LauncherPanel
    private let hostingView: NSHostingView<LauncherRootView>
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.hostingView = NSHostingView(rootView: LauncherRootView(proxy: proxy))
        self.panel = LauncherPanel(
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
        
        proxy.onStateOrQueryChange = { [weak self] in
            self?.updateFrameSize()
        }
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
        
        updateFrameSize(animate: false)
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
        updateFrameSize(animate: true)
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
        updateFrameSize(animate: true)
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func updateFrameSize(animate: Bool = true) {
        var size = NSSize(width: 560, height: 260)
        switch proxy.viewState {
        case .skills:
            let childCount = max(1, proxy.filteredSkills.count)
            let contentHeight = childCount * 56 + 180
            size.height = CGFloat(max(280, min(contentHeight, 520)))
        case .createInput, .createGenerating, .createReview:
            size.height = 420
        case .loading, .streaming, .result, .error:
            size.height = 360
        }
        
        let targetFrame = centeredFrame(size: size)
        
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setContentSize(size)
            panel.setFrame(targetFrame, display: true)
        }
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
        case createInput
        case createGenerating
        case createReview
    }

    @Published var viewState: ViewState = .skills {
        didSet { onStateOrQueryChange?() }
    }
    @Published var query = "" {
        didSet { onStateOrQueryChange?() }
    }
    @Published var skills: [Skill] = []
    @Published var status: String?
    @Published var selectedIndex = 0

    @Published var resultTitle = ""
    @Published var resultBody = ""

    @Published var newSkillName = ""
    @Published var newSkillDescription = ""
    @Published var newSkillPrompt = ""

    var onStateOrQueryChange: (() -> Void)?

    var onSelect: ((Skill) -> Void)?
    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
    var onBack: (() -> Void)?
    var focusSearch: (() -> Void)?

    var onStartCreate: (() -> Void)?
    var onGeneratePrompt: (() -> Void)?
    var onSaveSkill: (() -> Void)?

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
    @FocusState private var createInputFocused: Bool

    var body: some View {
        Group {
            switch proxy.viewState {
            case .skills:
                skillsView.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            case .createInput, .createGenerating:
                createInputView.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            case .createReview:
                createReviewView.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            default:
                resultView.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var skillsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Use Skill", text: $proxy.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .focused($searchFocused)
                    .onSubmit {
                        proxy.submitSelection()
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            if let status = proxy.status {
                Text(status)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if !proxy.filteredSkills.isEmpty {
                        ForEach(Array(proxy.filteredSkills.enumerated()), id: \.element.id) { index, skill in
                            Button {
                                proxy.selectedIndex = index
                                proxy.onSelect?(skill)
                            } label: {
                                Text(skill.name)
                                    .font(.system(size: 17, weight: index == proxy.selectedIndex ? .semibold : .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(index == proxy.selectedIndex ? Color.accentColor : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    proxy.selectedIndex = index
                                }
                            }
                        }
                    } else {
                        Text("No matching skills")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Spacer(minLength: 0)
            
            Button {
                proxy.onStartCreate?()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create New Skill")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    proxy.onCopy?()
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to Clipboard")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(proxy.resultBody.isEmpty ? 0.3 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(proxy.viewState == .loading || proxy.resultBody.isEmpty)
                .buttonStyle(.plain)

                Button(action: {
                    proxy.onBack?()
                }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 24)
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

    @ViewBuilder
    private var createInputView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create New Skill")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            Text("Describe what you want this skill to do in natural language.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            NativeTextEditor(
                text: $proxy.newSkillDescription,
                placeholder: "e.g., Translate the selected text into casual Spanish, keeping it concise and omitting formal pleasantries.",
                font: .systemFont(ofSize: 15),
                isDisabled: proxy.viewState == .createGenerating
            )
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(action: {
                    proxy.onGeneratePrompt?()
                }) {
                    HStack {
                        if proxy.viewState == .createGenerating {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(proxy.viewState == .createGenerating ? "Generating..." : "Generate Prompt")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(proxy.newSkillDescription.isEmpty ? 0.3 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(proxy.viewState == .createGenerating || proxy.newSkillDescription.isEmpty)
                .buttonStyle(.plain)

                Button(action: {
                    proxy.onBack?()
                }) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .disabled(proxy.viewState == .createGenerating)
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .onAppear {
            createInputFocused = true
        }
    }

    @ViewBuilder
    private var createReviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review & Save Skill")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack {
                Text("Name:")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("e.g. Spanish Translator", text: $proxy.newSkillName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Generated Prompt:")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                NativeTextEditor(
                    text: $proxy.newSkillPrompt,
                    placeholder: "",
                    font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                    isDisabled: false
                )
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 12) {
                Button(action: {
                    proxy.onSaveSkill?()
                }) {
                    Text("Save Skill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(proxy.newSkillName.isEmpty || proxy.newSkillPrompt.isEmpty ? 0.3 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(proxy.newSkillName.isEmpty || proxy.newSkillPrompt.isEmpty)
                .buttonStyle(.plain)

                Button(action: {
                    proxy.viewState = .createInput
                }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}
