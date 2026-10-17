import SwiftUI
import UIKit

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(OrientationLock.self) private var orientation

    var body: some Scene {
        WindowGroup {
            RolePickerView()
        }
    }
}

/// Lets one screen pin the interface orientation. The rear phone rides sideways in the
/// rack with only its Dynamic Island end showing, so its screen stays portrait (that end
/// is the top) however the phone is turned; the camera still levels itself by gravity.
final class OrientationLock: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }

    @MainActor static func set(_ mask: UIInterfaceOrientationMask) {
        Self.mask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
