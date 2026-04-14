import AppKit
import Darwin
import Foundation
import IOKit.ps
import SwiftUI

@main
struct MacCoffeeApp: App {
    @StateObject private var controller = PowerStateController()

    var body: some Scene {
        MenuBarExtra {
            NativeMenuContent(controller: controller)
        } label: {
            MenuBarLabel(mode: controller.mode, isBusy: controller.isBusy)
        }
    }
}

@MainActor
final class PowerStateController: ObservableObject {
    enum Mode: String {
        case keepAwake
        case normalSleep
        case unknown

        var title: String {
            switch self {
            case .keepAwake:
                return "保持唤醒"
            case .normalSleep:
                return "正常休眠"
            case .unknown:
                return "状态未知"
            }
        }

        var subtitle: String {
            switch self {
            case .keepAwake:
                return "合盖后继续运行"
            case .normalSleep:
                return "恢复系统默认行为"
            case .unknown:
                return "等待读取系统配置"
            }
        }

        var accent: Color {
            switch self {
            case .keepAwake:
                return Color(red: 0.86, green: 0.63, blue: 0.28)
            case .normalSleep:
                return Color(red: 0.48, green: 0.62, blue: 0.92)
            case .unknown:
                return Color.white.opacity(0.78)
            }
        }

        var symbol: String {
            switch self {
            case .keepAwake:
                return "cup.and.saucer.fill"
            case .normalSleep:
                return "moon.zzz.fill"
            case .unknown:
                return "questionmark.circle.fill"
            }
        }

        var menuText: String {
            switch self {
            case .keepAwake:
                return "唤醒"
            case .normalSleep:
                return "休眠"
            case .unknown:
                return "咖啡"
            }
        }

        var toggleTitle: String {
            switch self {
            case .keepAwake:
                return "恢复休眠"
            case .normalSleep, .unknown:
                return "开启防休眠"
            }
        }
    }

    enum PowerError: LocalizedError {
        case invalidStatus
        case processFailed(String)
        case scriptFailed(String)
        case verificationFailed
        case helperMissing
        case helperInstallFailed

        var errorDescription: String? {
            switch self {
            case .invalidStatus:
                return "无法读取当前休眠状态。"
            case let .processFailed(message):
                return message
            case let .scriptFailed(message):
                return message
            case .verificationFailed:
                return "命令已执行，但系统状态没有按预期切换。"
            case .helperMissing:
                return "未找到已安装的提权 helper。"
            case .helperInstallFailed:
                return "一次授权 helper 安装失败。"
            }
        }
    }

    @Published private(set) var mode: Mode = .unknown
    @Published private(set) var isBusy = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var helperReady = false
    @Published private(set) var scheduledSleepDeadline: Date?
    @Published var batteryAutoSleepEnabled: Bool
    @Published var lastError: String?

    private var scheduledSleepTask: Task<Void, Never>?
    private var batteryMonitorTask: Task<Void, Never>?
    private static let batteryAutoSleepDefaultsKey = "batteryAutoSleepEnabled"

    init() {
        batteryAutoSleepEnabled = UserDefaults.standard.bool(forKey: Self.batteryAutoSleepDefaultsKey)

        Task {
            await refreshAll()
        }

        updateBatteryMonitor()
    }

    func refreshAll() async {
        async let power: Void = refreshState()
        async let login: Void = refreshLaunchAtLoginStatus()
        async let helper: Void = refreshHelperReadyStatus()
        _ = await (power, login, helper)
    }

    func refreshState() async {
        do {
            let nextMode = try await Task.detached(priority: .utility) {
                try Self.detectMode()
            }.value

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                mode = nextMode
                lastError = nil
            }

            if nextMode != .keepAwake, scheduledSleepDeadline != nil {
                cancelScheduledSleep()
            }

            updateBatteryMonitor()
            await evaluateBatteryAutoSleepIfNeeded()
        } catch {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = .unknown
                lastError = error.localizedDescription
            }
        }
    }

    func toggleSleepMode() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let target: Mode = mode == .keepAwake ? .normalSleep : .keepAwake

        do {
            try await applyMode(target)
            if target == .normalSleep {
                cancelScheduledSleep()
            }
            await refreshState()
        } catch {
            withAnimation(.easeInOut(duration: 0.18)) {
                lastError = error.localizedDescription
            }
            await refreshState()
        }
    }

    func startTimedKeepAwake(for duration: TimeInterval) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await applyMode(.keepAwake)
            scheduleReturnToSleep(after: duration)
            lastError = nil
            await refreshState()
        } catch {
            withAnimation(.easeInOut(duration: 0.18)) {
                lastError = error.localizedDescription
            }
            await refreshState()
        }
    }

    func promptAndScheduleDateTime() async {
        guard let targetDate = Self.promptForScheduleDate() else {
            return
        }

        let now = Date()
        guard targetDate > now else {
            lastError = "请选择当前之后的日期时间。"
            return
        }

        await startTimedKeepAwake(for: targetDate.timeIntervalSince(now))
    }

    func cancelScheduledSleep() {
        scheduledSleepTask?.cancel()
        scheduledSleepTask = nil
        scheduledSleepDeadline = nil
        updateBatteryMonitor()
    }

    func setBatteryAutoSleepEnabled(_ enabled: Bool) {
        batteryAutoSleepEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.batteryAutoSleepDefaultsKey)
        updateBatteryMonitor()

        Task {
            await evaluateBatteryAutoSleepIfNeeded()
        }
    }

    func refreshLaunchAtLoginStatus() async {
        let enabled = await Task.detached(priority: .utility) {
            Self.isLaunchAtLoginEnabled()
        }.value
        withAnimation(.easeInOut(duration: 0.18)) {
            launchAtLoginEnabled = enabled
        }
    }

    func toggleLaunchAtLogin() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            if launchAtLoginEnabled {
                try await Task.detached(priority: .userInitiated) {
                    try Self.disableLaunchAtLogin()
                }.value
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try Self.enableLaunchAtLogin()
                }.value
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        await refreshLaunchAtLoginStatus()
    }

    func refreshHelperReadyStatus() async {
        let ready = await Task.detached(priority: .utility) {
            Self.isHelperReachable()
        }.value
        withAnimation(.easeInOut(duration: 0.18)) {
            helperReady = ready
        }
    }

    private func applyMode(_ target: Mode) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.apply(mode: target)
        }.value
    }

    private func scheduleReturnToSleep(after duration: TimeInterval) {
        cancelScheduledSleep()

        let deadline = Date().addingTimeInterval(duration)
        scheduledSleepDeadline = deadline
        scheduledSleepTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.runScheduledReturnToSleep()
        }
        updateBatteryMonitor()
    }

    private func runScheduledReturnToSleep() async {
        do {
            try await applyMode(.normalSleep)
            cancelScheduledSleep()
            lastError = nil
            await refreshState()
        } catch {
            cancelScheduledSleep()
            lastError = "定时恢复休眠失败：\(error.localizedDescription)"
            await refreshState()
        }
    }

    private func updateBatteryMonitor() {
        let shouldMonitor = batteryAutoSleepEnabled && (mode == .keepAwake || scheduledSleepDeadline != nil)

        if shouldMonitor {
            guard batteryMonitorTask == nil else { return }
            batteryMonitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.evaluateBatteryAutoSleepIfNeeded()
                    do {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                    } catch {
                        return
                    }
                }
            }
        } else {
            batteryMonitorTask?.cancel()
            batteryMonitorTask = nil
        }
    }

    private func evaluateBatteryAutoSleepIfNeeded() async {
        guard batteryAutoSleepEnabled, mode == .keepAwake else { return }
        guard Self.isRunningOnBattery() else { return }

        do {
            try await applyMode(.normalSleep)
            cancelScheduledSleep()
            lastError = nil
            await refreshState()
        } catch {
            lastError = "检测到电池供电，但恢复休眠失败：\(error.localizedDescription)"
        }
    }

    private static func promptForScheduleDate() -> Date? {
        let initialDate = Date().addingTimeInterval(30 * 60)
        let controller = ScheduleDatePromptController(initialDate: initialDate)
        return controller.runModal()
    }

    private static func isRunningOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return false
        }
        return source == kIOPSBatteryPowerValue
    }

    nonisolated private static func detectMode() throws -> Mode {
        let pmsetOutput = try runProcess("/usr/bin/pmset", arguments: ["-g", "custom"])
        let ioRegistryOutput = try runProcess("/usr/sbin/ioreg", arguments: ["-r", "-c", "IOPMrootDomain", "-d", "1"])

        let sleepDisabled = parseBoolean(named: "SleepDisabled", from: ioRegistryOutput)

        if sleepDisabled == true {
            return .keepAwake
        }

        guard let sleepValue = parseBatterySleepValue(from: pmsetOutput) else {
            throw PowerError.invalidStatus
        }
        return sleepValue == 0 && sleepDisabled != false ? .keepAwake : .normalSleep
    }

    nonisolated private static func parseBatterySleepValue(from output: String) -> Int? {
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

    nonisolated private static func parseBoolean(named key: String, from output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("\"\(key)\"") else { continue }
            if trimmed.hasSuffix("= Yes") { return true }
            if trimmed.hasSuffix("= No") { return false }
        }
        return nil
    }

    nonisolated private static func apply(mode: Mode) throws {
        if !isHelperReachable() {
            try installHelperIfNeeded()
        }

        let request: String
        switch mode {
        case .keepAwake:
            request = "APPLY keepAwake"
        case .normalSleep, .unknown:
            request = "APPLY normalSleep"
        }

        _ = try sendHelperRequest(request)
        Thread.sleep(forTimeInterval: 0.2)

        let verifiedMode = try detectMode()
        switch (mode, verifiedMode) {
        case (.keepAwake, .keepAwake), (.normalSleep, .normalSleep):
            return
        default:
            throw PowerError.verificationFailed
        }
    }

    nonisolated private static var launchAgentLabel: String {
        "com.elliotwu.maccoffee"
    }

    nonisolated private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    nonisolated private static var currentExecutablePath: String? {
        Bundle.main.executableURL?.path
    }

    nonisolated private static var currentGUIService: String {
        "gui/\(getuid())"
    }

    nonisolated private static var helperSocketPath: String {
        "/var/run/com.elliotwu.maccoffee.helper.sock"
    }

    nonisolated private static func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    nonisolated private static func enableLaunchAtLogin() throws {
        guard let executablePath = currentExecutablePath else {
            throw PowerError.processFailed("无法定位当前应用。")
        }

        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": ["Aqua"]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
        // Keep the agent file only. Bootstrapping immediately would launch a second
        // instance right away, while launchd will pick it up on the next login.
        _ = runProcessAllowFailure("/bin/launchctl", arguments: ["bootout", currentGUIService, launchAgentURL.path])
    }

    nonisolated private static func disableLaunchAtLogin() throws {
        _ = runProcessAllowFailure("/bin/launchctl", arguments: ["bootout", currentGUIService, launchAgentURL.path])
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    nonisolated private static func runProcess(_ launchPath: String, arguments: [String]) throws -> String {
        let result = runProcessAllowFailure(launchPath, arguments: arguments)
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PowerError.processFailed(message.isEmpty ? "命令执行失败。" : message)
        }
        return result.stdout
    }

    nonisolated private static func runProcessAllowFailure(_ launchPath: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, errorOutput)
    }

    nonisolated private static func isHelperReachable() -> Bool {
        (try? sendHelperRequest("PING")) == "PONG"
    }

    nonisolated private static func installHelperIfNeeded() throws {
        guard let installerURL = Bundle.main.url(forResource: "install_helper", withExtension: "sh") else {
            throw PowerError.helperMissing
        }

        let installerPath = installerURL.path
        let command = "chmod 755 \(shellQuote(installerPath)); \(shellQuote(installerPath))"
        try runPrivilegedAppleScript(command)

        for _ in 0..<20 {
            if isHelperReachable() {
                return
            }
            usleep(200_000)
        }

        throw PowerError.helperInstallFailed
    }

    nonisolated private static func sendHelperRequest(_ request: String) throws -> String {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw PowerError.helperMissing
        }
        defer { close(socketFD) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard helperSocketPath.utf8.count < maxLength else {
            throw PowerError.processFailed("helper socket path too long")
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            helperSocketPath.withCString { src in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), src, maxLength - 1)
            }
        }

        let connectResult = withUnsafePointer(to: &address) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                connect(socketFD, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw PowerError.helperMissing
        }

        let payload = request + "\n"
        let writeResult = payload.withCString { ptr in
            write(socketFD, ptr, strlen(ptr))
        }
        guard writeResult > 0 else {
            throw PowerError.processFailed("helper request write failed")
        }

        shutdown(socketFD, SHUT_WR)

        var buffer = [UInt8](repeating: 0, count: 512)
        let readCount = read(socketFD, &buffer, buffer.count)
        guard readCount > 0 else {
            throw PowerError.processFailed("helper response read failed")
        }

        let response = String(decoding: buffer.prefix(Int(readCount)), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if response.hasPrefix("OK ") {
            return String(response.dropFirst(3))
        }

        if response.hasPrefix("ERR ") {
            throw PowerError.processFailed(String(response.dropFirst(4)))
        }

        throw PowerError.processFailed("invalid helper response")
    }

    nonisolated private static func shellQuote(_ string: String) -> String {
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    nonisolated private static func runPrivilegedAppleScript(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        do shell script "\(escaped)" with administrator privileges
        """

        var scriptError: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        let result = script?.executeAndReturnError(&scriptError)
        if result == nil, let scriptError {
            let message = (scriptError[NSAppleScript.errorMessage] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "管理员命令执行失败。"
            throw PowerError.scriptFailed(message)
        }
    }
}

struct MenuBarLabel: View {
    let mode: PowerStateController.Mode
    let isBusy: Bool

    var body: some View {
        Image(systemName: statusSymbol)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .opacity(isBusy ? 0.65 : 0.96)
        .animation(.easeInOut(duration: 0.18), value: mode.rawValue)
        .animation(.easeInOut(duration: 0.18), value: isBusy)
    }

    private var statusSymbol: String {
        if isBusy {
            return "arrow.triangle.2.circlepath"
        }

        switch mode {
        case .keepAwake:
            return "cup.and.saucer"
        case .normalSleep:
            return "moon.zzz"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private final class ScheduleDatePromptController: NSObject {
    private let panel: NSPanel
    private let datePicker: NSDatePicker
    private let timePicker: NSDatePicker

    init(initialDate: Date) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 118),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "恢复休眠时间"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true

        datePicker = NSDatePicker(frame: .zero)
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.dateValue = initialDate
        datePicker.minDate = Date()
        datePicker.controlSize = .small

        timePicker = NSDatePicker(frame: .zero)
        timePicker.datePickerElements = [.hourMinute]
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.dateValue = initialDate
        timePicker.controlSize = .small

        super.init()
        buildInterface()
    }

    func runModal() -> Date? {
        guard let app = NSApplication.shared as NSApplication? else {
            return nil
        }

        panel.center()
        app.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        let response = app.runModal(for: panel)
        panel.orderOut(nil)
        guard response == .OK else {
            return nil
        }

        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timePicker.dateValue)

        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        return calendar.date(from: combined)
    }

    private func buildInterface() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 118))
        panel.contentView = contentView

        let label = NSTextField(labelWithString: "恢复时间")
        label.font = .systemFont(ofSize: 13, weight: .medium)

        datePicker.translatesAutoresizingMaskIntoConstraints = false
        timePicker.translatesAutoresizingMaskIntoConstraints = false
        let pickerStack = NSStackView(views: [datePicker, timePicker])
        pickerStack.orientation = .horizontal
        pickerStack.alignment = .centerY
        pickerStack.spacing = 8

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        let confirmButton = NSButton(title: "确定", target: self, action: #selector(confirm))
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .gravityAreas
        buttonStack.spacing = 10

        [label, pickerStack, buttonStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            datePicker.widthAnchor.constraint(equalToConstant: 126),
            timePicker.widthAnchor.constraint(equalToConstant: 82),

            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),

            pickerStack.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            pickerStack.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            pickerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @objc private func cancel() {
        NSApplication.shared.stopModal(withCode: .cancel)
    }

    @objc private func confirm() {
        NSApplication.shared.stopModal(withCode: .OK)
    }
}

struct NativeMenuContent: View {
    @ObservedObject var controller: PowerStateController

    var body: some View {
        Text(statusLine)
            .disabled(true)

        Divider()

        Button {
            Task {
                await controller.toggleSleepMode()
            }
        } label: {
            Label(
                controller.isBusy ? "正在写入设置..." : controller.mode.toggleTitle,
                systemImage: controller.mode == .keepAwake ? "moon.zzz.fill" : "cup.and.saucer.fill"
            )
        }
        .disabled(controller.isBusy)

        Menu {
            Button("15 分钟") {
                Task {
                    await controller.startTimedKeepAwake(for: 15 * 60)
                }
            }

            Button("30 分钟") {
                Task {
                    await controller.startTimedKeepAwake(for: 30 * 60)
                }
            }

            Button("1 小时") {
                Task {
                    await controller.startTimedKeepAwake(for: 60 * 60)
                }
            }

            Button("2 小时") {
                Task {
                    await controller.startTimedKeepAwake(for: 2 * 60 * 60)
                }
            }

            Button("选择日期时间...") {
                Task {
                    await controller.promptAndScheduleDateTime()
                }
            }

            if controller.scheduledSleepDeadline != nil {
                Divider()

                Button("取消定时") {
                    controller.cancelScheduledSleep()
                }
            }
        } label: {
            Label("定时恢复休眠", systemImage: "timer")
        }
        .disabled(controller.isBusy)

        Button {
            Task {
                await controller.refreshAll()
            }
        } label: {
            Label("刷新状态", systemImage: "arrow.clockwise")
        }
        .disabled(controller.isBusy)

        Toggle(isOn: launchAtLoginBinding) {
            Label("登录时启动", systemImage: "power.circle")
        }
        .disabled(controller.isBusy)

        Toggle(isOn: batteryAutoSleepBinding) {
            Label("电池供电时立即恢复休眠", systemImage: "battery.25")
        }
        .disabled(controller.isBusy)

        Divider()

        if let lastError = controller.lastError {
            Text(lastError)
                .disabled(true)

            Divider()
        }

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("退出 Mac Coffee", systemImage: "xmark.circle")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { controller.launchAtLoginEnabled },
            set: { _ in
                Task {
                    await controller.toggleLaunchAtLogin()
                }
            }
        )
    }

    private var batteryAutoSleepBinding: Binding<Bool> {
        Binding(
            get: { controller.batteryAutoSleepEnabled },
            set: { enabled in
                controller.setBatteryAutoSleepEnabled(enabled)
            }
        )
    }

    private var statusLine: String {
        if let deadline = controller.scheduledSleepDeadline {
            return "\(controller.mode.title) · \(Self.dateTimeFormatter.string(from: deadline)) 恢复"
        }

        let helperText: String
        if controller.batteryAutoSleepEnabled {
            helperText = "电池即恢复"
        } else {
            helperText = controller.helperReady ? "已授权" : "首次切换需授权"
        }
        return "\(controller.mode.title) · \(helperText)"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
