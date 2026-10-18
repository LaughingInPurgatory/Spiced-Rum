import CryptoKit
import Foundation

public enum SteamWebHelperCompatibility {
    public enum State: Equatable {
        case inactive
        case active
        case helperChanged
        case needsRecovery
    }

    private struct Receipt: Codable {
        let version: Int
        let wrapperSHA256: String
        let originalConfig: Data?
        let installedConfig: Data
    }

    private static let helperName = "steamwebhelper.exe"
    private static let originalName = "steamwebhelper_real.exe"
    private static let configName = "steam.cfg"
    private static let receiptName = ".spicedrum-steam-ui-fix.json"
    private static let configKey = "BootStrapperInhibitAll"
    private static let fileManager = FileManager.default

    public static func state(in steamDirectory: URL, wrapper: URL) -> State {
        let directory = steamDirectory.appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        let helper = directory.appendingPathComponent(helperName)
        let original = directory.appendingPathComponent(originalName)
        let receiptURL = directory.appendingPathComponent(receiptName)

        guard fileManager.fileExists(atPath: receiptURL.path) else {
            return fileManager.fileExists(atPath: original.path) ? .needsRecovery : .inactive
        }
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL)),
              receipt.version == 1,
              fileManager.fileExists(atPath: original.path) else { return .needsRecovery }
        guard let current = try? Data(contentsOf: helper), let bundled = try? Data(contentsOf: wrapper),
              current == bundled, hash(current) == receipt.wrapperSHA256 else { return .helperChanged }
        return .active
    }

    public static func enable(in steamDirectory: URL, wrapper: URL) throws {
        let directory = steamDirectory.appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        let helper = directory.appendingPathComponent(helperName)
        let original = directory.appendingPathComponent(originalName)
        let config = steamDirectory.appendingPathComponent(configName)
        let receiptURL = directory.appendingPathComponent(receiptName)

        guard fileManager.fileExists(atPath: directory.path) else {
            throw RumError.message("This Steam installation has no 64-bit CEF helper folder. Install or launch Windows Steam once, then retry.")
        }
        guard !fileManager.fileExists(atPath: receiptURL.path), !fileManager.fileExists(atPath: original.path) else {
            throw RumError.message("A Steam UI fix backup already exists. Remove the existing fix or review the saved helper before enabling it again.")
        }

        let originalHelper = try readRegularFile(helper, description: "Steam's original web helper")
        let wrapperData = try readRegularFile(wrapper, description: "Spiced-Rum's Steam UI helper")
        guard originalHelper.starts(with: [0x4d, 0x5a]), wrapperData.starts(with: [0x4d, 0x5a]) else {
            throw RumError.message("A Steam helper is not a valid Windows executable. The original files have not been changed.")
        }
        let originalConfig = try optionalRegularFile(config, description: "Steam configuration")
        let installedConfig = try updateBootstrapperSetting(in: originalConfig, value: "enable")
        let receipt = Receipt(version: 1, wrapperSHA256: hash(wrapperData), originalConfig: originalConfig, installedConfig: installedConfig)
        let staging = directory.appendingPathComponent(".spicedrum-steam-helper-\(UUID().uuidString).tmp")

        try wrapperData.write(to: staging, options: .atomic)
        var movedOriginal = false
        var movedWrapper = false
        do {
            try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
            try fileManager.moveItem(at: helper, to: original)
            movedOriginal = true
            try fileManager.moveItem(at: staging, to: helper)
            movedWrapper = true
            try installedConfig.write(to: config, options: .atomic)
        } catch {
            let failure = error
            var recoveryError: Error?
            do {
                if movedWrapper { try fileManager.removeItem(at: helper) }
                if movedOriginal { try fileManager.moveItem(at: original, to: helper) }
                try? fileManager.removeItem(at: receiptURL)
            } catch { recoveryError = error }
            try? fileManager.removeItem(at: staging)
            if let recoveryError {
                throw RumError.message("Steam's UI fix did not finish, and automatic recovery needs attention. The saved original helper is at \(original.path).\n\(failure.localizedDescription)\nRecovery: \(recoveryError.localizedDescription)")
            }
            throw failure
        }
    }

    /// Returns a preserved replacement Steam helper when Steam updated it while the fix was active.
    @discardableResult
    public static func disable(in steamDirectory: URL) throws -> URL? {
        let directory = steamDirectory.appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        let helper = directory.appendingPathComponent(helperName)
        let original = directory.appendingPathComponent(originalName)
        let receiptURL = directory.appendingPathComponent(receiptName)
        let config = steamDirectory.appendingPathComponent(configName)
        let receipt: Receipt
        do { receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL)) }
        catch { throw RumError.message("The Steam UI fix has no readable recovery receipt. Its files were left untouched at \(directory.path).") }
        guard receipt.version == 1, fileManager.fileExists(atPath: original.path) else {
            throw RumError.message("The Steam UI fix backup is incomplete. Its files were left untouched at \(directory.path).")
        }

        let currentHelper = try optionalRegularFile(helper, description: "Steam web helper")
        let currentConfig = try optionalRegularFile(config, description: "Steam configuration")
        let restoredConfig = try restoredConfig(currentConfig, receipt: receipt)
        let keepCurrent = currentHelper.map { hash($0) != receipt.wrapperSHA256 } ?? false
        let savedCurrent = currentHelper == nil ? nil : directory.appendingPathComponent(keepCurrent ? "steamwebhelper-spicedrum-preserved-\(UUID().uuidString).exe" : ".spicedrum-disable-\(UUID().uuidString).tmp")
        var movedCurrent = false
        var restoredOriginal = false

        do {
            if let savedCurrent {
                try fileManager.moveItem(at: helper, to: savedCurrent)
                movedCurrent = true
            }
            try fileManager.moveItem(at: original, to: helper)
            restoredOriginal = true
            try restoreConfig(restoredConfig, at: config)
            try fileManager.removeItem(at: receiptURL)
            if !keepCurrent, let savedCurrent { try? fileManager.removeItem(at: savedCurrent) }
            return keepCurrent ? savedCurrent : nil
        } catch {
            let failure = error
            var recoveryError: Error?
            do {
                try? restoreConfig(currentConfig, at: config)
                if restoredOriginal { try fileManager.moveItem(at: helper, to: original) }
                if movedCurrent, let savedCurrent { try fileManager.moveItem(at: savedCurrent, to: helper) }
            } catch { recoveryError = error }
            if let recoveryError {
                throw RumError.message("Steam's original helper could not be fully restored. The recovery receipt remains at \(receiptURL.path).\n\(failure.localizedDescription)\nRecovery: \(recoveryError.localizedDescription)")
            }
            throw failure
        }
    }

    private static func readRegularFile(_ url: URL, description: String) throws -> Data {
        guard let data = try optionalRegularFile(url, description: description) else {
            throw RumError.message("Cannot find \(description) at \(url.path).")
        }
        return data
    }

    private static func optionalRegularFile(_ url: URL, description: String) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RumError.message("\(description) is not a regular file. Nothing was changed at \(url.path).")
        }
        return try Data(contentsOf: url)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func updateBootstrapperSetting(in original: Data?, value: String) throws -> Data {
        let text: String
        if let original {
            guard let decoded = String(data: original, encoding: .utf8) else {
                throw RumError.message("Steam's steam.cfg is not UTF-8 text. It has been preserved without changes.")
            }
            text = decoded
        } else { text = "" }
        let (lines, newline, trailing) = splitLines(text)
        let filtered = lines.filter { !isBootstrapperSetting($0) }
        let updated = filtered + ["\(configKey)=\(value)"]
        return Data((updated.joined(separator: newline) + (trailing || text.isEmpty ? newline : "")).utf8)
    }

    private static func restoredConfig(_ current: Data?, receipt: Receipt) throws -> Data? {
        if current == receipt.installedConfig { return receipt.originalConfig }
        guard let current, let currentText = String(data: current, encoding: .utf8) else {
            if current == nil { return receipt.originalConfig }
            throw RumError.message("Steam's steam.cfg changed and is no longer UTF-8 text. The current file and helper were left untouched.")
        }
        let originalText = receipt.originalConfig.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let (currentLines, newline, currentTrailing) = splitLines(currentText)
        let (originalLines, _, _) = splitLines(originalText)
        let restoredSettings = originalLines.filter(isBootstrapperSetting)
        let lines = currentLines.filter { !isBootstrapperSetting($0) } + restoredSettings
        if lines.isEmpty, receipt.originalConfig == nil { return nil }
        return Data((lines.joined(separator: newline) + (currentTrailing || currentText.isEmpty ? newline : "")).utf8)
    }

    private static func splitLines(_ text: String) -> ([String], String, Bool) {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        let trailing = normalized.hasSuffix("\n")
        if trailing { lines.removeLast() }
        return (lines, newline, trailing)
    }

    private static func isBootstrapperSetting(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(configKey.lowercased() + "=")
    }

    private static func restoreConfig(_ data: Data?, at url: URL) throws {
        if let data { try data.write(to: url, options: .atomic) }
        else if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }
}
