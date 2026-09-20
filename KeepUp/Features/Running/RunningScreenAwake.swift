import UIKit

/// Own the idle-timer override only while the recording page needs it.
@MainActor final class RunningScreenAwake {
    private let read: @MainActor () -> Bool
    private let write: @MainActor (Bool) -> Void
    private var originalValue: Bool?

    init(read: @escaping @MainActor () -> Bool = { UIApplication.shared.isIdleTimerDisabled },
         write: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.read = read
        self.write = write
    }

    func update(active: Bool) {
        if active {
            if originalValue == nil { originalValue = read(); write(true) }
        } else if let originalValue {
            write(originalValue)
            self.originalValue = nil
        }
    }
}
