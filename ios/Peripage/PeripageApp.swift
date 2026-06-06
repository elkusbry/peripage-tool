import SwiftUI

@main
struct PeripageApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Peripage")
                .padding()
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 640)
        #endif
    }
}
