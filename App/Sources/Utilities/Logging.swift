import Foundation
import os.log

/// ログカテゴリ
public enum LogCategory: String {
    case app = "App"
    case audio = "Audio"
    case dsp = "DSP"
    case device = "Device"
    case ui = "UI"
    case error = "Error"
}

/// ログレベル
public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

/// 構造化ログエントリ
public struct LogEntry: Codable {
    public let timestamp: Date
    public let level: String
    public let category: String
    public let message: String
    public let metadata: [String: String]?

    public init(level: LogLevel, category: LogCategory, message: String, metadata: [String: String]? = nil) {
        self.timestamp = Date()
        self.level = String(describing: level)
        self.category = category.rawValue
        self.message = message
        self.metadata = metadata
    }
}

/// ロガー
public final class Logger {

    public static let shared = Logger()

    private let subsystem = Constants.App.bundleId
    private var osLoggers: [LogCategory: os.Logger] = [:]
    private var logHistory: [LogEntry] = []
    private let historyLimit = 1000
    private let queue = DispatchQueue(label: "com.voicechanger.logger", qos: .utility)

    public var minimumLevel: LogLevel = .debug

    private init() {
        // カテゴリごとのOSLoggerを初期化
        for category in [LogCategory.app, .audio, .dsp, .device, .ui, .error] {
            osLoggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
    }

    // MARK: - Public Methods

    public func log(_ level: LogLevel, category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        guard level >= minimumLevel else { return }

        // OSLogへ出力
        let osLogger = osLoggers[category] ?? os.Logger(subsystem: subsystem, category: category.rawValue)

        switch level {
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        case .critical:
            osLogger.critical("\(message, privacy: .public)")
        }

        // 履歴に追加
        queue.async { [weak self] in
            guard let self = self else { return }
            let entry = LogEntry(level: level, category: category, message: message, metadata: metadata)
            self.logHistory.append(entry)

            // 履歴サイズを制限
            if self.logHistory.count > self.historyLimit {
                self.logHistory.removeFirst(self.logHistory.count - self.historyLimit)
            }
        }
    }

    // MARK: - Convenience Methods

    public func debug(_ message: String, category: LogCategory = .app) {
        log(.debug, category: category, message)
    }

    public func info(_ message: String, category: LogCategory = .app) {
        log(.info, category: category, message)
    }

    public func warning(_ message: String, category: LogCategory = .app) {
        log(.warning, category: category, message)
    }

    public func error(_ message: String, category: LogCategory = .error) {
        log(.error, category: category, message)
    }

    public func critical(_ message: String, category: LogCategory = .error) {
        log(.critical, category: category, message)
    }

    // MARK: - Export

    /// ログをJSONとしてエクスポート
    public func exportJSON() -> Data? {
        queue.sync {
            try? JSONEncoder().encode(logHistory)
        }
    }

    /// ログをファイルに保存
    public func saveToFile(url: URL) throws {
        guard let data = exportJSON() else {
            throw LoggerError.exportFailed
        }
        try data.write(to: url)
    }

    /// ログをクリア
    public func clear() {
        queue.async { [weak self] in
            self?.logHistory.removeAll()
        }
    }
}

public enum LoggerError: LocalizedError {
    case exportFailed

    public var errorDescription: String? {
        switch self {
        case .exportFailed:
            return "Failed to export logs"
        }
    }
}

// MARK: - Global Convenience Functions

public func logDebug(_ message: String, category: LogCategory = .app) {
    Logger.shared.debug(message, category: category)
}

public func logInfo(_ message: String, category: LogCategory = .app) {
    Logger.shared.info(message, category: category)
}

public func logWarning(_ message: String, category: LogCategory = .app) {
    Logger.shared.warning(message, category: category)
}

public func logError(_ message: String, category: LogCategory = .error) {
    Logger.shared.error(message, category: category)
}
