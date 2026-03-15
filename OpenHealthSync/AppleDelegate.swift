import UIKit
import OpenWearablesHealthSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        OpenWearablesHealthSDK.setBackgroundCompletionHandler(completionHandler)
    }
}
