import SwiftUI
import AppKit

@main
struct KaSoruApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        DebugLog.write("KaSoruApp.init")
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    override init() {
        super.init()
        DebugLog.write("AppDelegate.init")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }
}

enum DebugLog {
    private static let path = "/tmp/kasoru.log"
    static func write(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
