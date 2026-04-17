import AppKit
import AIAssistantKit
import SwiftUI

@MainActor
final class PopupWindowController: NSWindowController {
    private let hostingView: NSHostingView<PopupRootView>
    private let panel: NSPanel

    init() {
        let rootView = PopupRootView()
        self.hostingView = NSHostingView(rootView: rootView)
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = hostingView
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func bind(to appController: AppController, skillStore: SkillStore) {
        hostingView.rootView = PopupRootView(appController: appController, skillStore: skillStore)
    }

    func show(near selectionFrame: CGRect) {
        let width: CGFloat = 140
        let height: CGFloat = 44
        let x = selectionFrame.midX - width / 2
        let y = selectionFrame.maxY + 8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct PopupRootView: View {
    var appController: AppController?
    @ObservedObject var skillStore: SkillStore
    @State private var isExpanded = false

    init(appController: AppController? = nil, skillStore: SkillStore? = nil) {
        self.appController = appController
        self.skillStore = skillStore ?? PreviewDummy.skillStore
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                Label("Use Skills", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(skillStore.skills) { skill in
                        Button {
                            isExpanded = false
                            appController?.run(skill: skill)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 12, weight: .semibold))
                                if let description = skill.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if skill.id != skillStore.skills.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(width: 260)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(6)
    }
}

@MainActor
private enum PreviewDummy {
    static let skillStore = SkillStore(skillsDirectory: FileManager.default.homeDirectoryForCurrentUser)
}
