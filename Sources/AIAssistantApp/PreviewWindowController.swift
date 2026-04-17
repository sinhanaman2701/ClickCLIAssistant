import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController: NSWindowController {
    private let proxy = PreviewProxyController()
    private let hostingView: NSHostingView<PreviewRootView>
    private let windowRef: NSWindow

    init() {
        let rootView = PreviewRootView(proxy: proxy)
        self.hostingView = NSHostingView(rootView: rootView)
        self.windowRef = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRef.title = "AI Assistant Preview"
        windowRef.contentView = hostingView
        super.init(window: windowRef)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func bind(to appController: AppController) {
        proxy.copyAction = appController.copyPreviewToClipboard
        hostingView.rootView = PreviewRootView(proxy: proxy)
    }

    func update(previewText: String, errorMessage: String?) {
        proxy.previewText = previewText
        proxy.errorMessage = errorMessage
    }

    func show() {
        windowRef.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PreviewRootView: View {
    @ObservedObject var appController: PreviewProxyController

    init(proxy: PreviewProxyController) {
        self.appController = proxy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = appController.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            ScrollView {
                Text(appController.previewText.isEmpty ? "No output yet." : appController.previewText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            HStack {
                Button("Copy Result") {
                    appController.copyAction?()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}

@MainActor
final class PreviewProxyController: ObservableObject {
    @Published var previewText = ""
    @Published var errorMessage: String?
    var copyAction: (() -> Void)?
}
