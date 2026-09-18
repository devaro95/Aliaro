import Foundation

/// App Group shared between the Aliaro app and the `AliaroWidgetsExtension`
/// widget extension — the only channel between them, since a widget can't
/// see the app's SwiftData store or talk to Supabase directly. Different
/// identifier per build config so Dev and prod don't overwrite each
/// other's widget data if both are installed on the same device.
enum AppGroup {
    #if DEBUG
    static let identifier = "group.com.devaro.aliaro.dev"
    #else
    static let identifier = "group.com.devaro.aliaro"
    #endif

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
