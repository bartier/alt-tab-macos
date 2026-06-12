class CliEvents {
    static let portName = "com.lwouis.alt-tab-macos.cli"

    static func observe() {
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if let messagePort = CFMessagePortCreateLocal(nil, portName as CFString, handleEvent, &context, nil),
           let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0) {
            CFRunLoopAddSource(BackgroundWork.cliEventsThread.runLoop, source, .commonModes)
        } else {
            Logger.error("Can't listen on message port. Is another AltTab already running?")
            // TODO: should we quit or restart here?
            // It's complex since AltTab can be restarted sometimes,
            // and the new instance may coexit with the old for some duration
            // There is also the case of multiple instances at login
        }
    }
}

fileprivate func handleEvent(_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
    Logger.debug()
    if let data,
       let message = String(data: data as Data, encoding: .utf8) {
        Logger.info(message)
        let output = CliServer.executeCommandAndSendReponse(message)
        if let responseData = try? CliServer.jsonEncoder.encode(output) as CFData {
            return Unmanaged.passRetained(responseData)
        }
    }
    Logger.error("Failed to decode message")
    return nil
}

class CliServer {
    static let jsonEncoder = JSONEncoder()
    static let error = "error"
    static let noOutput = "noOutput"

    static func executeCommandAndSendReponse(_ rawValue: String) -> Codable {
        var output: Codable = ""
        DispatchQueue.main.sync {
            if rawValue == "--list" {
                output = JsonOutput(windows: Windows.list
                    .filter { !$0.isWindowlessApp }
                    .map { JsonWindow(id: $0.cgWindowId, title: $0.title) }
                )
                return
            }
            if rawValue.hasPrefix("--list=") {
                if let shortcutNumber = Int(rawValue.dropFirst("--list=".count)),
                   (1...4).contains(shortcutNumber),
                   Preferences.raycastIntegration[shortcutNumber - 1] {
                    let index = shortcutNumber - 1
                    Windows.updateSpacesAndTabsState()
                    let activePid = Preferences.appsToShow[index] == .active ? Windows.resolveActivePid() : nil
                    let windows = Windows.list
                        .filter { !$0.isWindowlessApp && Windows.isWindowShownToTheUser($0, activePid, index) }
                        .sorted { Windows.isSortedBefore($0, $1, index) }
                    output = JsonOutput(windows: windows.map {
                        JsonWindow(
                            id: $0.cgWindowId,
                            title: $0.displayTitle(),
                            appName: $0.application.displayName,
                            bundleId: $0.application.bundleIdentifier,
                            appPath: $0.application.bundleURL?.path,
                            spaceIndex: $0.spaceIndexes.first,
                            isMinimized: $0.isMinimized,
                            isHidden: $0.isHidden,
                            lastFocusOrder: $0.lastFocusOrder
                        )
                    })
                    return
                }
                output = error
                return
            }
            if rawValue.hasPrefix("--focus=") {
                if let id = CGWindowID(rawValue.dropFirst("--focus=".count)),
                   let window = (Windows.list.first { $0.cgWindowId == id }) {
                    window.focus()
                    output = noOutput
                    return
                }
            }
            output = error
        }
        return output
    }
}

struct JsonOutput: Codable {
    var windows: [JsonWindow]
}

struct JsonWindow: Codable {
    var id: CGWindowID?
    var title: String
    // extra fields returned by --list=<shortcut>; nil (thus absent) for plain --list to keep its output unchanged
    var appName: String? = nil
    var bundleId: String? = nil
    var appPath: String? = nil
    var spaceIndex: Int? = nil
    var isMinimized: Bool? = nil
    var isHidden: Bool? = nil
    var lastFocusOrder: Int? = nil

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encodeIfPresent(appPath, forKey: .appPath)
        try container.encodeIfPresent(spaceIndex, forKey: .spaceIndex)
        try container.encodeIfPresent(isMinimized, forKey: .isMinimized)
        try container.encodeIfPresent(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(lastFocusOrder, forKey: .lastFocusOrder)
    }
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1].hasPrefix("--list=") || args[1].hasPrefix("--focus=") {
                return args[1]
            }
        }
        return nil
    }

    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let _ = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            let responseData = try returnData.unwrapOrThrow().takeRetainedValue()
            if let response = String(data: responseData as Data, encoding: .utf8) {
                if response != "\"\(CliServer.error)\"" {
                    if response != "\"\(CliServer.noOutput)\"" {
                        print(response)
                    }
                    exit(0)
                }
            }
            print("Couldn't execute command. Is it correct?")
            exit(1)
        } catch {
            print("AltTab.app needs to be running for CLI commands to work")
            exit(1)
        }
    }
}
