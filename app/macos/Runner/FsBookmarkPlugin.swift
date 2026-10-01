import Cocoa
import FlutterMacOS

/// Flutter plugin for managing macOS security-scoped bookmarks.
///
/// This plugin provides methods to:
/// - Pick a folder and create a security-scoped bookmark
/// - Resolve a bookmark to get access to the folder
/// - Validate if a bookmark is still valid
/// - Stop accessing a bookmark (release security-scoped access)
class FsBookmarkPlugin: NSObject, FlutterPlugin {
  /// Currently accessed bookmarks (bookmark data -> URL)
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
    case "isBookmarkValid":
      isBookmarkValid(call: call, result: result)
    case "stopAccessing":
      stopAccessing(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Opens a folder picker dialog and returns the bookmark data.
  private func pickFolder(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }

    do {
      // Create security-scoped bookmark
      let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      // Start accessing the security-scoped resource
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(
          code: "ACCESS_DENIED",
          message: "Failed to start accessing security-scoped resource",
          details: nil
        ))
        return
      }

      // Store the URL for later
      accessedBookmarks[bookmarkData] = url

      result(FlutterStandardTypedData(bytes: bookmarkData))
    } catch {
      result(FlutterError(
        code: "BOOKMARK_FAILED",
        message: "Failed to create bookmark: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  /// Resolves a bookmark data to a path.
  private func resolveBookmark(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let bookmarkData = args["bookmark"] as? FlutterStandardTypedData else {
      result(FlutterError(
        code: "INVALID_ARGS",
        message: "Missing or invalid bookmark data",
        details: nil
      ))
      return
    }

    let data = bookmarkData.data

    // Check if we already have this bookmark accessed
    if let url = accessedBookmarks[data] {
      result(url.path)
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
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(
          code: "ACCESS_DENIED",
          message: "Failed to start accessing security-scoped resource",
          details: nil
        ))
        return
      }

      // Store for later
      accessedBookmarks[data] = url

      result(url.path)
    } catch {
      result(FlutterError(
        code: "RESOLVE_FAILED",
        message: "Failed to resolve bookmark: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  /// Checks if a bookmark is still valid.
  private func isBookmarkValid(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let bookmarkData = args["bookmark"] as? FlutterStandardTypedData else {
      result(false)
      return
    }

    do {
      var isStale = false
      _ = try URL(
        resolvingBookmarkData: bookmarkData.data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      result(!isStale)
    } catch {
      result(false)
    }
  }

  /// Stops accessing a security-scoped bookmark.
  private func stopAccessing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let bookmarkData = args["bookmark"] as? FlutterStandardTypedData else {
      result(nil)
      return
    }

    let data = bookmarkData.data

    if let url = accessedBookmarks[data] {
      url.stopAccessingSecurityScopedResource()
      accessedBookmarks.removeValue(forKey: data)
    }

    result(nil)
  }

  deinit {
    // Stop accessing all bookmarks
    for (_, url) in accessedBookmarks {
      url.stopAccessingSecurityScopedResource()
    }
    accessedBookmarks.removeAll()
  }
}
