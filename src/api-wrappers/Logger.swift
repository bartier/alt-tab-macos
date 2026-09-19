import SwiftyBeaver
import Foundation

class Logger {
    private static let logger = SwiftyBeaver.self
    static let flag = "--logs="
    static let longDateTimeFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static let shortDateTimeFormat = "HH:mm:ss"
    static let logFileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Logs/AltTab/AltTab.log", isDirectory: false)

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        console.levelString.verbose = "VERB"
        console.levelString.debug = "DEBG"
        console.levelString.info = "INFO"
        console.levelString.warning = "WARN"
        console.levelString.error = "ERRO"
        console.format = "$C$D\(longDateTimeFormat)$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)
        let file = RotatingFileDestination(logFileURL: logFileURL)
        file.format = "$D\(longDateTimeFormat)$d $L $N.swift:$l $F $M"
        file.minLevel = .debug
        logger.addDestination(file)
    }

    static func decideLevel() -> SwiftyBeaver.Level {
        if let level = (CommandLine.arguments.first { $0.starts(with: flag) })?.dropFirst(flag.count) {
            switch level {
                case "verbose": return .verbose
                case "debug": return .debug
                case "info": return .info
                case "warning": return .warning
                case "error": return .error
                default: break
            }
        }
        return .error
    }

    static func debug(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.debug, items, file: file, function: function, line: line, context: context)
    }

    static func info(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.info, items, file: file, function: function, line: line, context: context)
    }

    static func warning(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.warning, items, file: file, function: function, line: line, context: context)
    }

    static func error(_ items: Any?..., file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(.error, items, file: file, function: function, line: line, context: context)
    }

    private static func custom(_ level: SwiftyBeaver.Level, _ items: [Any?], file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        let message = items.map { "\($0 ?? "nil")" }.joined(separator: " ")
        logger.custom(level: level, message: message, file: file, function: function, line: line, context: context)
    }
}

class RotatingFileDestination: BaseDestination {
    static let maxFileSize = UInt64(25 * 1_000_000)
    static let rotatedFilesToKeep = 3
    static let writesBetweenSizeChecks = 100
    // start at the threshold so the size check runs on the first write after launch
    private var writesSinceSizeCheck = RotatingFileDestination.writesBetweenSizeChecks
    private let logFileURL: URL
    private let fileManager = FileManager.default

    init(logFileURL: URL) {
        self.logFileURL = logFileURL
        super.init()
    }

    override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                       file: String, function: String, line: Int, context: Any? = nil) -> String? {
        let formattedString = super.send(level, msg: msg, thread: thread, file: file, function: function, line: line, context: context)
        if let formattedString {
            // send() is serialized on this destination's queue, so rotation can't race with writes
            rotateIfNeeded()
            appendToFile(formattedString + "\n")
        }
        return formattedString
    }

    private func appendToFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if !fileManager.fileExists(atPath: logFileURL.path) {
            try? fileManager.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }
        if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
    }

    private func rotateIfNeeded() {
        writesSinceSizeCheck += 1
        guard writesSinceSizeCheck >= RotatingFileDestination.writesBetweenSizeChecks else { return }
        writesSinceSizeCheck = 0
        let path = logFileURL.path
        guard let size = (try? fileManager.attributesOfItem(atPath: path) as NSDictionary)?.fileSize(),
              size >= RotatingFileDestination.maxFileSize else { return }
        try? fileManager.removeItem(atPath: "\(path).\(RotatingFileDestination.rotatedFilesToKeep)")
        for i in stride(from: RotatingFileDestination.rotatedFilesToKeep - 1, through: 1, by: -1) {
            if fileManager.fileExists(atPath: "\(path).\(i)") {
                try? fileManager.moveItem(atPath: "\(path).\(i)", toPath: "\(path).\(i + 1)")
            }
        }
        try? fileManager.moveItem(atPath: path, toPath: "\(path).1")
    }
}
