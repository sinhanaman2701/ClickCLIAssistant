import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyMonitor {
    private let hotKeyID = EventHotKeyID(signature: FourCharCode("CLAS"), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    private let onPressed: () -> Void

    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed
    }

    deinit {
        stop()
    }

    func start() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr else { return noErr }
            if pressedID.signature == monitor.hotKeyID.signature, pressedID.id == monitor.hotKeyID.id {
                monitor.onPressed()
            }
            return noErr
        }

        handlerUPP = handler
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handlerUPP = nil
    }
}

private func FourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.utf8.prefix(4) {
        result = (result << 8) + OSType(scalar)
    }
    return result
}
