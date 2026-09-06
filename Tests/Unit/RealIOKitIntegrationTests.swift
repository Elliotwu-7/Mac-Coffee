import Foundation
import XCTest
@testable import MacCoffeeCore

final class RealIOKitIntegrationTests: XCTestCase {
    func testSystemDisplayAndOffAppearInPMSetAssertions() throws {
        let manager = IOKitPowerAssertionManager()
        defer { manager.releaseAll() }

        try manager.transition(to: .system)
        var ownedAssertions = try assertionsOwnedByCurrentProcess()
        XCTAssertEqual(ownedAssertions.count, 1)
        XCTAssertTrue(ownedAssertions[0].contains("PreventUserIdleSystemSleep"))

        try manager.transition(to: .display)
        ownedAssertions = try assertionsOwnedByCurrentProcess()
        XCTAssertEqual(ownedAssertions.count, 1)
        XCTAssertTrue(ownedAssertions[0].contains("PreventUserIdleDisplaySleep"))

        try manager.transition(to: .off)
        XCTAssertTrue(try assertionsOwnedByCurrentProcess().isEmpty)
    }

    private func assertionsOwnedByCurrentProcess() throws -> [Substring] {
        let processPrefix = "pid \(ProcessInfo.processInfo.processIdentifier)("
        return try powerAssertionOutput()
            .split(separator: "\n")
            .filter {
                $0.contains(processPrefix)
                    && $0.contains("Mac Coffee active wake session")
            }
    }

    private func powerAssertionOutput() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
    }
}
