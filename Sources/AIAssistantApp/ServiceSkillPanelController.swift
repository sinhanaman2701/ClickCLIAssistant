import AppKit
import AIAssistantKit
import SwiftUI

@MainActor
final class ServiceSkillPanelController: NSWindowController {
    private let hostingView: NSHostingView<ServiceSkillsView>
    private let windowRef: NSPanel

    init() {
        let rootView = ServiceSkillsView()
        self.hostingView = NSHostingView(rootView: rootView)
        self.windowRef = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        windowRef.title = "Use Skills"
        windowRef.isOpaque = false
        windowRef.backgroundColor = .windowBackgroundColor
        windowRef.hasShadow = true
        windowRef.level = .floating
        windowRef.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        windowRef.contentView = hostingView
        super.init(window: windowRef)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(skills: [Skill], selectedText: String, anchor: CGPoint, onSelect: @escaping (Skill) -> Void) {
        hostingView.rootView = ServiceSkillsView(skills: skills, selectedText: selectedText, onSelect: onSelect)
        let width: CGFloat = 320
        let height: CGFloat = min(260, max(180, CGFloat(skills.count) * 44 + 90))
        windowRef.setFrame(NSRect(x: anchor.x - width / 2, y: anchor.y + 8, width: width, height: height), display: true)
        windowRef.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        windowRef.orderOut(nil)
    }
}

private struct ServiceSkillsView: View {
    let skills: [Skill]
    let selectedText: String
    var onSelect: ((Skill) -> Void)?

    init(skills: [Skill] = [], selectedText: String = "", onSelect: ((Skill) -> Void)? = nil) {
        self.skills = skills
        self.selectedText = selectedText
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use Skills")
                .font(.system(size: 18, weight: .semibold))

            Text(selectedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(skills) { skill in
                        Button {
                            onSelect?(skill)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 13, weight: .semibold))
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
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
