import Foundation
import XCTest
@testable import MacCoffeeCore

final class MCPContractTests: XCTestCase {
    func testToolNamesMatchTheStablePublicContract() {
        XCTAssertEqual(
            MCPToolName.allCases.map(\.rawValue),
            [
                "maccoffee_get_status",
                "maccoffee_set_session",
                "maccoffee_stop_session",
                "maccoffee_set_battery_threshold",
                "maccoffee_set_launch_at_login",
                "maccoffee_set_language"
            ]
        )
    }

    func testResourceURIsMatchTheStablePublicContract() {
        XCTAssertEqual(
            MCPResourceURI.allCases.map(\.rawValue),
            [
                "maccoffee://status",
                "maccoffee://capabilities",
                "maccoffee://activity"
            ]
        )
    }

    func testErrorCodesMatchTheStablePublicContract() {
        XCTAssertEqual(
            MCPErrorCode.allCases.map(\.rawValue),
            [
                "APP_NOT_RUNNING",
                "CLIENT_UNPAIRED",
                "CLIENT_REVOKED",
                "MCP_DISABLED",
                "BATTERY_BLOCKED",
                "INVALID_ARGUMENT",
                "APP_BUSY",
                "ASSERTION_FAILED",
                "VERSION_MISMATCH",
                "INTERNAL_ERROR"
            ]
        )
    }

    func testSchemaVersionStartsAtOne() {
        XCTAssertEqual(MCPContract.schemaVersion, 1)
    }

    func testParsesEverySupportedCommandIntoExistingDomainTypes() throws {
        XCTAssertEqual(
            try parse("maccoffee_get_status", #"{}"#),
            .getStatus
        )
        XCTAssertEqual(
            try parse(
                "maccoffee_set_session",
                #"{"mode":"display","duration":"hours4","requestId":"session-1"}"#
            ),
            .setSession(mode: .display, duration: .hours4, requestID: "session-1")
        )
        XCTAssertEqual(
            try parse("maccoffee_stop_session", #"{"requestId":"stop-1"}"#),
            .stopSession(requestID: "stop-1")
        )
        XCTAssertEqual(
            try parse(
                "maccoffee_set_battery_threshold",
                #"{"percent":15,"requestId":"battery-1"}"#
            ),
            .setBatteryThreshold(percent: 15, requestID: "battery-1")
        )
        XCTAssertEqual(
            try parse(
                "maccoffee_set_launch_at_login",
                #"{"enabled":true,"requestId":"login-1"}"#
            ),
            .setLaunchAtLogin(enabled: true, requestID: "login-1")
        )
        XCTAssertEqual(
            try parse(
                "maccoffee_set_language",
                #"{"language":"zh-Hans","requestId":"language-1"}"#
            ),
            .setLanguage(language: .simplifiedChinese, requestID: "language-1")
        )
    }

    func testEverySupportedSessionModeAndDurationParses() throws {
        for mode in [WakeMode.system, .display] {
            for duration in SessionDuration.allCases {
                let json = #"{"mode":"\#(mode.rawValue)","duration":"\#(duration.rawValue)"}"#
                XCTAssertEqual(
                    try parse("maccoffee_set_session", json),
                    .setSession(mode: mode, duration: duration, requestID: nil)
                )
            }
        }
    }

    func testEverySupportedLanguageParses() throws {
        for language in SupportedLanguage.allCases {
            let json = #"{"language":"\#(language.rawValue)"}"#
            XCTAssertEqual(
                try parse("maccoffee_set_language", json),
                .setLanguage(language: language, requestID: nil)
            )
        }
    }

    func testBatteryThresholdAcceptsInclusivePolicyBounds() throws {
        XCTAssertEqual(
            try parse("maccoffee_set_battery_threshold", #"{"percent":10}"#),
            .setBatteryThreshold(percent: 10, requestID: nil)
        )
        XCTAssertEqual(
            try parse("maccoffee_set_battery_threshold", #"{"percent":30}"#),
            .setBatteryThreshold(percent: 30, requestID: nil)
        )
    }

    func testBatteryThresholdRejectsInsteadOfClamping() {
        assertInvalidArgument("maccoffee_set_battery_threshold", #"{"percent":9}"#)
        assertInvalidArgument("maccoffee_set_battery_threshold", #"{"percent":31}"#)
    }

    func testRejectsOffAsASetSessionMode() {
        assertInvalidArgument(
            "maccoffee_set_session",
            #"{"mode":"off","duration":"indefinite"}"#
        )
    }

    func testRejectsUnknownEnumValues() {
        assertInvalidArgument(
            "maccoffee_set_session",
            #"{"mode":"system","duration":"forever"}"#
        )
        assertInvalidArgument("maccoffee_set_language", #"{"language":"it"}"#)
    }

    func testRejectsMissingWronglyTypedAndUnknownArguments() {
        assertInvalidArgument("maccoffee_set_session", #"{"mode":"system"}"#)
        assertInvalidArgument("maccoffee_set_battery_threshold", #"{"percent":"15"}"#)
        assertInvalidArgument("maccoffee_set_launch_at_login", #"{"enabled":1}"#)
        assertInvalidArgument("maccoffee_get_status", #"{"extra":true}"#)
        assertInvalidArgument("maccoffee_stop_session", #"{"extra":true}"#)
    }

    func testRejectsUnknownToolsAndNonObjectArguments() {
        assertInvalidArgument("maccoffee_unknown", #"{}"#)
        assertInvalidArgument("maccoffee_get_status", #"[]"#)
        assertInvalidArgument("maccoffee_get_status", #"not-json"#)
    }

    func testRejectsEmptyOrUnreasonablyLargeRequestIdentifiers() {
        assertInvalidArgument("maccoffee_stop_session", #"{"requestId":""}"#)
        let oversized = String(repeating: "x", count: 129)
        assertInvalidArgument(
            "maccoffee_stop_session",
            #"{"requestId":"\#(oversized)"}"#
        )
    }

    private func parse(_ tool: String, _ arguments: String) throws -> MCPCommand {
        try MCPCommandParser.parse(
            toolName: tool,
            argumentsJSON: Data(arguments.utf8)
        )
    }

    private func assertInvalidArgument(
        _ tool: String,
        _ arguments: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(tool, arguments), file: file, line: line) { error in
            XCTAssertEqual(
                (error as? MCPServiceError)?.code,
                .invalidArgument,
                file: file,
                line: line
            )
        }
    }
}
