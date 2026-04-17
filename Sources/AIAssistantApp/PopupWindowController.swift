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
            contentRect: NSRect(x: 0, y: 0, width: 148, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func bind(to appController: AppController, skillStore: SkillStore) {
        hostingView.rootView = PopupRootView(appController: appController, skillStore: skillStore)
    }

    func show(near selectionFrame: CGRect) {
        let width: CGFloat = 148
        let height: CGFloat = 40
        let anchorScreen = screen(for: selectionFrame) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = anchorScreen?.visibleFrame ?? .zero
        let aboveY = selectionFrame.minY - height - 10
        let belowY = selectionFrame.maxY + 10
        let preferredY = aboveY >= visibleFrame.minY + 8 ? aboveY : belowY
        let x = min(
            max(selectionFrame.midX - width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - width - 8
        )
        let y = min(
            max(preferredY, visibleFrame.minY + 8),
            visibleFrame.maxY - height - 8
        )

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

    init(appController: AppController? = nil, skillStore: SkillStore? = nil) {
        self.appController = appController
        self.skillStore = skillStore ?? PreviewDummy.skillStore
    }

    var body: some View {
        Button {
            appController?.showSkillMenu()
        } label: {
            Label("Use Skills", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(6)
    }
}

@MainActor
private enum PreviewDummy {
    static let skillStore = SkillStore(skillsDirectory: FileManager.default.homeDirectoryForCurrentUser)
}

extension PopupWindowController {
    func showSkillMenu(skills: [Skill], onSelect: @escaping (Skill) -> Void) {
        let menu = NSMenu()

        if skills.isEmpty {
            let item = NSMenuItem(title: "No skills found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for skill in skills {
                let item = NSMenuItem(title: skill.name, action: #selector(handleSkillMenuItem(_:)), keyEquivalent: "")
                item.representedObject = SkillMenuAction(skill: skill, onSelect: onSelect)
                item.target = self
                menu.addItem(item)
            }
        }

        guard let contentView = panel.contentView else { return }
        let anchor = NSPoint(x: 16, y: contentView.bounds.height - 2)
        menu.popUp(positioning: nil, at: anchor, in: contentView)
    }

    @objc
    private func handleSkillMenuItem(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SkillMenuAction else { return }
        action.onSelect(action.skill)
    }

    private func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(rect)
        } ?? NSScreen.screens.min(by: { lhs, rhs in
            let lhsDistance = distance(lhs.visibleFrame, to: rect)
            let rhsDistance = distance(rhs.visibleFrame, to: rect)
            return lhsDistance < rhsDistance
        })
    }

    private func distance(_ frame: CGRect, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if rect.midX < frame.minX {
            dx = frame.minX - rect.midX
        } else if rect.midX > frame.maxX {
            dx = rect.midX - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if rect.midY < frame.minY {
            dy = frame.minY - rect.midY
        } else if rect.midY > frame.maxY {
            dy = rect.midY - frame.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}

private final class SkillMenuAction: NSObject {
    let skill: Skill
    let onSelect: (Skill) -> Void

    init(skill: Skill, onSelect: @escaping (Skill) -> Void) {
        self.skill = skill
        self.onSelect = onSelect
    }
}
