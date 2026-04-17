import ApplicationServices
import Cocoa
import Foundation

public enum SelectionReader {
    @MainActor
    public static func accessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public static func currentSelection() -> SelectionSnapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )

        guard focusedResult == .success, let focusedElementValue else { return nil }
        let focusedElement = focusedElementValue as! AXUIElement

        guard let text = copySelectedText(from: focusedElement),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let frame = copySelectionBounds(from: focusedElement)
            ?? copyElementFrame(from: focusedElement)
            ?? fallbackFrameNearMouse()
        return SelectionSnapshot(text: text, frame: frame)
    }

    @MainActor
    public static func currentSelectionWithClipboardFallback() async -> SelectionSnapshot? {
        if let selection = currentSelection() {
            return selection
        }

        let pasteboard = NSPasteboard.general
        let snapshot = clipboardSnapshot(from: pasteboard)
        let previousChangeCount = pasteboard.changeCount

        // Fast fallback path:
        // 1) Send Cmd+C once.
        // 2) Poll quickly for clipboard update.
        // 3) Retry one more Cmd+C only if needed.
        let attemptDelays: [[UInt64]] = [
            [40_000_000, 80_000_000, 120_000_000],
            [60_000_000, 120_000_000]
        ]

        for delays in attemptDelays {
            sendCommandC()
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                if pasteboard.changeCount != previousChangeCount,
                   let text = pasteboard.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    restoreClipboard(snapshot, to: pasteboard)
                    let frame = fallbackFrameNearMouse()
                    return SelectionSnapshot(text: text, frame: frame)
                }
            }
        }

        restoreClipboard(snapshot, to: pasteboard)
        return nil
    }

    public static func replaceSelectedText(with text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        guard focusedResult == .success, let focusedElementValue else { return false }
        let focusedElement = focusedElementValue as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return setResult == .success
    }

    private static func copySelectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        if result == .success, let value, let text = value as? String, !text.isEmpty {
            return text
        }

        // Some apps expose range + value instead of selectedText directly.
        if let textFromRangeValue = copyTextFromRangeAndValue(from: element), !textFromRangeValue.isEmpty {
            return textFromRangeValue
        }

        // Some apps expose attributed range extraction parameterized API.
        if let attributed = copyAttributedTextForSelectedRange(from: element), !attributed.isEmpty {
            return attributed
        }

        return nil
    }

    private static func copyTextFromRangeAndValue(from element: AXUIElement) -> String? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success,
              let rangeAX = rangeValue,
              CFGetTypeID(rangeAX) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        AXValueGetValue(rangeAX as! AXValue, .cfRange, &range)
        guard range.location >= 0, range.length > 0 else { return nil }

        var textValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        )
        guard textResult == .success,
              let wholeText = textValue as? String else {
            return nil
        }

        let ns = wholeText as NSString
        guard range.location + range.length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: range.location, length: range.length))
    }

    private static func copyAttributedTextForSelectedRange(from element: AXUIElement) -> String? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var attributedValue: CFTypeRef?
        let attributedResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &attributedValue
        )
        guard attributedResult == .success else { return nil }
        return (attributedValue as? NSAttributedString)?.string
    }

    private static func copySelectionBounds(from element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )

        guard rangeResult == .success,
              let rangeAX = rangeValue,
              CFGetTypeID(rangeAX) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        AXValueGetValue(rangeAX as! AXValue, .cfRange, &range)

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAX,
            &boundsValue
        )

        guard boundsResult == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect)
        return rect
    }

    private static func copyElementFrame(from element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: point, size: size)
    }

    private static func fallbackFrameNearMouse() -> CGRect {
        let location = NSEvent.mouseLocation
        return CGRect(x: location.x, y: location.y, width: 1, height: 1)
    }

    private static func sendCommandC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    @MainActor
    private static func clipboardSnapshot(from pasteboard: NSPasteboard) -> [ClipboardItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let entries = item.types.compactMap { type -> ClipboardEntry? in
                guard let data = item.data(forType: type) else { return nil }
                return ClipboardEntry(type: type.rawValue, data: data)
            }
            return ClipboardItemSnapshot(entries: entries)
        }
    }

    @MainActor
    private static func restoreClipboard(_ snapshot: [ClipboardItemSnapshot], to pasteboard: NSPasteboard) {
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for entry in itemSnapshot.entries {
                item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}

private struct ClipboardItemSnapshot {
    let entries: [ClipboardEntry]
}

private struct ClipboardEntry {
    let type: String
    let data: Data
}
