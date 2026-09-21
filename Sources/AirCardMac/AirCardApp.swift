import SwiftUI

@main
struct AirCardMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("AirCard macOS") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
