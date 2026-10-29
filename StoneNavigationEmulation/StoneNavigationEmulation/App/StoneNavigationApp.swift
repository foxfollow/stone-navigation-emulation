import SwiftUI

@main
struct StoneNavigationApp: App {
    @State private var container = AppContainer.make(
        launch: LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.session)
                .environment(container.settingsModel)
                .environment(container.appModel)
                .environment(container.searchModel)
                .environment(container.savedPlaces)
                .preferredColorScheme(.dark)
        }
    }
}
