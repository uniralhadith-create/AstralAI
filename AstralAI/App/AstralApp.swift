import SwiftUI
import UIKit

@main
struct AstralApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.providerStore)
                .environmentObject(environment.language)
                .environment(\.layoutDirection, environment.language.layoutDirection)
                .environment(\.locale, Locale(identifier: environment.language.effectiveCode))
                .tint(AstralTheme.nebulaViolet)
        }
    }
}

/// Hosts global UIKit-level hooks (background task registration).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundManager.shared.register()
        return true
    }
}
