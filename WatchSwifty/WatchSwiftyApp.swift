import SwiftUI
import UIKit
import WatchSwiftyCore

@main
struct WatchSwiftyApp: App {
    @State private var model = AppModel(environment: .live(), defaultDeviceName: UIDevice.current.name)

    init() {
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
