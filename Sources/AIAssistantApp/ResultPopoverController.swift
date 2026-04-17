import AppKit
import SwiftUI

@MainActor
final class ResultPopoverController: NSWindowController {
    private let proxy = ResultProxyController()
    private let panel: NSPanel
    private let hostingView: NSHostingView<ResultRootView>
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?

    init() {
        self.hostingView = NSHostingView(rootView: ResultRootView(proxy: proxy))
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 250),
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

    func bind(onCopy: @escaping () -> Void, onReplace: @escaping () -> Void) {
        proxy.onCopy = onCopy
        proxy.onReplace = onReplace
    }

    func showLoading(skillName: String, near frame: CGRect) {
        proxy.title = skillName
        proxy.body = "Working on it..."
        proxy.isLoading = true
        proxy.isError = false
        show(near: frame)
    }

    func showResult(skillName: String, body: String, near frame: CGRect, isError: Bool) {
        proxy.title = skillName
        proxy.body = body
        proxy.isLoading = false
        proxy.isError = isError
        show(near: frame)
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func show(near selectionFrame: CGRect) {
        let width: CGFloat = 560
        let height: CGFloat = 250
        var x = selectionFrame.midX - width / 2
        var y = selectionFrame.maxY + 10

        if let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.visibleFrame, selectionFrame) || $0.visibleFrame.contains(selectionFrame.origin) }) {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
            y = min(max(y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - height - 8)
        }

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        installDismissMonitors()
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

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
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
final class ResultProxyController: ObservableObject {
    @Published var title = "Result"
    @Published var body = ""
    @Published var isLoading = false
    @Published var isError = false
    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
}

private struct ResultRootView: View {
    @ObservedObject var proxy: ResultProxyController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proxy.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)

            Divider()
                .overlay(Color.white.opacity(0.2))

            ScrollView {
                Text(proxy.body)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(proxy.isError ? Color.red.opacity(0.85) : Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Button("Replace") {
                    proxy.onReplace?()
                }
                .disabled(proxy.isLoading || proxy.isError || proxy.body.isEmpty)
                .buttonStyle(.borderedProminent)

                Button("Copy") {
                    proxy.onCopy?()
                }
                .disabled(proxy.isLoading || proxy.body.isEmpty)
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 560, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
        )
    }
}
