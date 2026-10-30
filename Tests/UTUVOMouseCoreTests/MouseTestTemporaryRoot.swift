import Foundation

/// macOS Foundation may ignore TMPDIR under a custom sandbox. All filesystem
/// fixtures explicitly use the companion's per-run root when supplied. Ordinary
/// swift test still uses a unique child of the system temporary directory.
enum MouseTestTemporaryRoot {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["UTUVO_MOUSE_TEST_TEMP_ROOT"],
           path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }
}
