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

    private static func copySelectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        return value as? String
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
}
