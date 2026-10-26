import BrushCore
import Foundation
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

enum Haptics {
    static func play(_ haptic: Cue.Haptic) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(haptic == .success ? .success : .click)
        #else
        if haptic == .success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        #endif
    }

    static func warning() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
