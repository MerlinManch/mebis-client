import SwiftUI

@main
struct ByCSLernclientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // A light blue is needed for legible controls on dark system dialogs.
                .tint(Color(uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 1)
                        : UIColor(red: 0.02, green: 0.34, blue: 0.57, alpha: 1)
                }))
        }
    }
}
