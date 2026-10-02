import Cocoa
import FlutterMacOS

/// Flutter plugin for managing macOS security-scoped bookmarks.
///
/// This plugin provides methods to:
/// - Pick a folder via NSOpenPanel and create a security-scoped bookmark
/// - Resolve a bookmark to get the actual path
/// - Manage bookmark persistence
class FsBookmarkPlugin: NSObject, FlutterPlugin {
    private var accessedBookmarks: [Data: URL] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "localsend/fs_bookmark",
            binaryMessenger: registrar.messenger
        )
        let instance = FsBookmarkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickFolder":
            pickFolder(result: result)
        case "resolveBookmark":
            resolveBookmark(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Opens a folder picker dialog and returns the selected path.
    private func pickFolder(result: @escaping FlutterResult) {
        guard let window = NSApplication.shared.mainWindow else {
            result(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Folder to Share"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else {
            result(nil)
            return
        }

        // Create security-scoped bookmark
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Store for later resolution
            accessedBookmarks[bookmarkData] = url

            // Return the path as a string
            result(url.path)
        } catch {
            print("Failed to create bookmark: \(error)")
            result(nil)
        }
    }

    /// Resolves a bookmark data to a path.
    private func resolveBookmark(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let bookmarkData = args["bookmark"] as? FlutterStandardTypedData else {
            result(nil)
            return
        }

        let data = bookmarkData.data

        // Check if we already have this bookmark accessed
        if let url = accessedBookmarks[data] {
            // Start accessing if not already
            if url.startAccessingSecurityScopedResource() {
                result(url.path)
            } else {
                result(url.path) // Still return path even if access fails
            }
            return
        }

        // Resolve the bookmark
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                accessedBookmarks[data] = url
                result(url.path)
            } else {
                print("Failed to start accessing security-scoped resource: \(url)")
                result(url.path) // Still return path
            }
        } catch {
            print("Failed to resolve bookmark: \(error)")
            result(nil)
        }
    }

    deinit {
        // Stop accessing all bookmarks
        for (_, url) in accessedBookmarks {
            url.stopAccessingSecurityScopedResource()
        }
        accessedBookmarks.removeAll()
    }
}
