import Darwin
import Foundation

enum HelperError: LocalizedError {
    case invalidCommand
    case unauthorized
    case verificationFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "invalid command"
        case .unauthorized:
            return "unauthorized client"
        case .verificationFailed:
            return "state verification failed"
        case let .processFailed(message):
            return message
        }
    }
}

enum HelperMode: String {
    case keepAwake
    case normalSleep
}

struct MacCoffeeHelper {
    static let socketPath = "/var/run/com.elliotwu.maccoffee.helper.sock"

    static func run() throws {
        signal(SIGPIPE, SIG_IGN)
        let serverFD = try makeServerSocket()
        defer {
            close(serverFD)
            unlink(socketPath)
        }

        while true {
            var storage = sockaddr()
            var length: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(serverFD, &storage, &length)
            if clientFD < 0 { continue }

            do {
                try handleClient(clientFD)
            } catch {
                writeResponse("ERR \(error.localizedDescription)\n", to: clientFD)
                close(clientFD)
            }
        }
    }

    private static func makeServerSocket() throws -> Int32 {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HelperError.processFailed("socket failed")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxLength else {
            close(fd)
            throw HelperError.processFailed("socket path too long")
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { src in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), src, maxLength - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                bind(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(fd)
            throw HelperError.processFailed("bind failed")
        }

        chmod(socketPath, 0o666)

        guard listen(fd, 8) == 0 else {
            close(fd)
            throw HelperError.processFailed("listen failed")
        }

        return fd
    }

    private static func handleClient(_ clientFD: Int32) throws {
        defer { close(clientFD) }

        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(clientFD, &uid, &gid) == 0 else {
            throw HelperError.unauthorized
        }
        guard uid == consoleUserID() else {
            throw HelperError.unauthorized
        }

        let request = readRequest(from: clientFD)
        let response = try process(request: request)
        writeResponse("OK \(response)\n", to: clientFD)
    }

    private static func readRequest(from fd: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return "" }
        let data = Data(buffer.prefix(Int(count)))
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func writeResponse(_ response: String, to fd: Int32) {
        response.withCString { ptr in
            _ = write(fd, ptr, strlen(ptr))
        }
    }

    private static func process(request: String) throws -> String {
        if request == "PING" {
            return "PONG"
        }

        if request == "STATUS" {
            return try detectMode().rawValue
        }

        if request == "APPLY keepAwake" {
            try apply(mode: .keepAwake)
            return HelperMode.keepAwake.rawValue
        }

        if request == "APPLY normalSleep" {
            try apply(mode: .normalSleep)
            return HelperMode.normalSleep.rawValue
        }

        throw HelperError.invalidCommand
    }

    private static func apply(mode: HelperMode) throws {
        switch mode {
        case .keepAwake:
            _ = try runProcess("/usr/bin/pmset", arguments: ["-b", "sleep", "0"])
            _ = try runProcess("/usr/bin/pmset", arguments: ["-b", "disablesleep", "1"])
        case .normalSleep:
            _ = try runProcess("/usr/bin/pmset", arguments: ["-b", "sleep", "5"])
            _ = try runProcess("/usr/bin/pmset", arguments: ["-b", "disablesleep", "0"])
        }

        usleep(350_000)

        guard try detectMode() == mode else {
            throw HelperError.verificationFailed
        }
    }

    private static func detectMode() throws -> HelperMode {
        let pmsetOutput = try runProcess("/usr/bin/pmset", arguments: ["-g", "custom"])
        let ioRegistryOutput = try runProcess("/usr/sbin/ioreg", arguments: ["-r", "-c", "IOPMrootDomain", "-d", "1"])

        if parseBoolean(named: "SleepDisabled", from: ioRegistryOutput) == true {
            return .keepAwake
        }

        guard let sleepValue = parseBatterySleepValue(from: pmsetOutput) else {
            throw HelperError.verificationFailed
        }
        return sleepValue == 0 ? .keepAwake : .normalSleep
    }

    private static func parseBatterySleepValue(from output: String) -> Int? {
        let sections = output.components(separatedBy: "AC Power:")
        let batterySection = sections.first ?? output
        for line in batterySection.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("sleep") else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            return Int(parts[1])
        }
        return nil
    }

    private static func parseBoolean(named key: String, from output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("\"\(key)\"") else { continue }
            if trimmed.hasSuffix("= Yes") { return true }
            if trimmed.hasSuffix("= No") { return false }
        }
        return nil
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperError.processFailed(message.isEmpty ? "command failed" : message)
        }

        return output
    }

    private static func consoleUserID() -> uid_t {
        var info = stat()
        guard stat("/dev/console", &info) == 0 else { return getuid() }
        return info.st_uid
    }
}

do {
    try MacCoffeeHelper.run()
} catch {
    fputs("MacCoffeeHelper failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
