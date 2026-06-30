import UIKit
import OpenWearablesHealthSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LBAppearance.apply()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier.hasPrefix("com.openwearables") {
            OpenWearablesHealthSDK.setBackgroundCompletionHandler(completionHandler)
        } else {
            completionHandler()
        }
    }
}
