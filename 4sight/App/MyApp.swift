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

/// Keeps every screen portrait. The front rides upright on the handlebar and its views are
/// laid out for portrait; the rear rides sideways in the rack with only its Dynamic Island
/// end showing, which is the top in portrait. The rear camera levels itself by gravity.
final class OrientationLock: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

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
