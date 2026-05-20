import Foundation

enum CLITool: String, Codable, CaseIterable {
    case codex
    case claude
}

struct AppSettings: Codable, Equatable {
    var promptTemplate: String
    var defaultCLI: CLITool

    static let `default` = AppSettings(
        promptTemplate: "Explain this sentence in simpler, more concise terms: \"<TEXT>\"",
        defaultCLI: .codex
    )
}

final class SettingsStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("settings.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("ka-soru")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.init(directory: appSupport)
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
