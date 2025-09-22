import LoopKitUI
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject, DeviceOrientationController {
    var supportedInterfaceOrientations: UIInterfaceOrientationMask = .all

    func setDefaultSupportedInferfaceOrientations() {
        supportedInterfaceOrientations = .all
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set up OrientationLock controller
        OrientationLock.deviceOrientationController = self
        return true
    }
}
