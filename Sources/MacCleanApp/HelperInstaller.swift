import Foundation
import ServiceManagement

/// Registers/unregisters the privileged helper daemon via SMAppService. (SRS FR-14, T5.1)
///
/// `register()` triggers the system's admin authorization prompt; the daemon is
/// installed at Contents/Library/LaunchDaemons inside the app bundle.
enum HelperInstaller {
    static var service: SMAppService {
        SMAppService.daemon(plistName: "com.macclean.helper.plist")
    }

    static var status: SMAppService.Status {
        service.status
    }

    static var isRegistered: Bool {
        status == .enabled
    }

    /// Prompts the user for admin credentials and installs the daemon. Throws with
    /// a readable error if the user cancels or registration fails.
    static func register() throws {
        try service.register()
    }

    static func unregister() throws {
        try service.unregister()
    }
}