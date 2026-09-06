import Foundation
import XCTest

@testable import MacCoffeeCore

final class MCPStdioProtocolTests: XCTestCase {
  func testHelperNegotiatesProtocolAndListsStableContract() throws {
    let result = try runHelper(
      inputPhases: [
        HelperInputPhase(
          lines: [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"MacCoffeeIntegrationTests","version":"1.0"}}}"#
          ],
          expectedTotalResponseCount: 1
        ),
        HelperInputPhase(
          lines: [
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}"#,
          ],
          expectedTotalResponseCount: 3
        ),
      ]
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    XCTAssertFalse(messages.isEmpty)

    let initialize = try message(withID: 1, in: messages)
    let initializeResult = try dictionary(initialize["result"])
    XCTAssertEqual(initializeResult["protocolVersion"] as? String, "2025-11-25")
    let serverInfo = try dictionary(initializeResult["serverInfo"])
    XCTAssertEqual(serverInfo["name"] as? String, "MacCoffeeMCP")
    XCTAssertEqual(
      serverInfo["version"] as? String,
      try productVersion()
    )

    let toolsMessage = try message(withID: 2, in: messages)
    let toolsResult = try dictionary(toolsMessage["result"])
    let tools = try array(toolsResult["tools"]).map(dictionary)
    XCTAssertEqual(
      Set(tools.compactMap { $0["name"] as? String }),
      [
        "maccoffee_get_status",
        "maccoffee_set_session",
        "maccoffee_stop_session",
        "maccoffee_set_battery_threshold",
        "maccoffee_set_launch_at_login",
        "maccoffee_set_language",
      ]
    )

    let resourcesMessage = try message(withID: 3, in: messages)
    let resourcesResult = try dictionary(resourcesMessage["result"])
    let resources = try array(resourcesResult["resources"]).map(dictionary)
    XCTAssertEqual(
      Set(resources.compactMap { $0["uri"] as? String }),
      [
        "maccoffee://status",
        "maccoffee://capabilities",
        "maccoffee://activity",
      ]
    )
  }

  func testToolsExposeStrictValidatedInputSchemas() throws {
    let result = try runHelper(
      inputPhases: initializedPhases(
        requests: [
          #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
        ],
        totalResponseCount: 2
      )
    )
    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    let toolsResult = try dictionary(try message(withID: 2, in: messages)["result"])
    let tools = try array(toolsResult["tools"]).map(dictionary)
    let schemas = Dictionary(
      uniqueKeysWithValues: try tools.map { tool in
        (
          try XCTUnwrap(tool["name"] as? String),
          try dictionary(tool["inputSchema"])
        )
      }
    )

    for schema in schemas.values {
      XCTAssertEqual(schema["type"] as? String, "object")
      XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    try assertRequired([], in: XCTUnwrap(schemas["maccoffee_get_status"]))
    try assertRequired(["mode", "duration"], in: XCTUnwrap(schemas["maccoffee_set_session"]))
    try assertRequired([], in: XCTUnwrap(schemas["maccoffee_stop_session"]))
    try assertRequired(["percent"], in: XCTUnwrap(schemas["maccoffee_set_battery_threshold"]))
    try assertRequired(["enabled"], in: XCTUnwrap(schemas["maccoffee_set_launch_at_login"]))
    try assertRequired(["language"], in: XCTUnwrap(schemas["maccoffee_set_language"]))

    let sessionProperties = try properties(in: XCTUnwrap(schemas["maccoffee_set_session"]))
    XCTAssertEqual(
      Set(
        try array(try dictionary(sessionProperties["mode"])["enum"]).compactMap { $0 as? String }),
      ["system", "display"]
    )
    XCTAssertEqual(
      Set(
        try array(try dictionary(sessionProperties["duration"])["enum"]).compactMap {
          $0 as? String
        }),
      ["minutes30", "hours1", "hours2", "hours4", "hours8", "indefinite"]
    )

    let thresholdProperties = try properties(
      in: XCTUnwrap(schemas["maccoffee_set_battery_threshold"])
    )
    let percent = try dictionary(thresholdProperties["percent"])
    XCTAssertEqual((percent["minimum"] as? NSNumber)?.intValue, 10)
    XCTAssertEqual((percent["maximum"] as? NSNumber)?.intValue, 30)

    let languageProperties = try properties(in: XCTUnwrap(schemas["maccoffee_set_language"]))
    XCTAssertEqual(
      Set(
        try array(try dictionary(languageProperties["language"])["enum"]).compactMap {
          $0 as? String
        }),
      ["system", "ru", "en", "de", "fr", "zh-Hans", "ja", "ko", "es"]
    )
  }

  func testUnavailableAppReturnsStructuredToolErrorWithoutStdoutNoise() throws {
    let result = try runHelper(
      inputPhases: initializedPhases(
        requests: [
          #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"maccoffee_get_status","arguments":{}}}"#
        ],
        totalResponseCount: 2
      )
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    XCTAssertEqual(messages.count, 2, "stdout must contain JSON-RPC frames only")
    let callResult = try dictionary(try message(withID: 2, in: messages)["result"])
    XCTAssertEqual(callResult["isError"] as? Bool, true)
    let structured = try dictionary(callResult["structuredContent"])
    XCTAssertEqual((structured["schemaVersion"] as? NSNumber)?.intValue, 1)
    let error = try dictionary(structured["error"])
    XCTAssertEqual(error["code"] as? String, "APP_NOT_RUNNING")
    XCTAssertEqual(error["retryable"] as? Bool, true)
    let content = try array(callResult["content"]).map(dictionary)
    XCTAssertEqual(content.first?["type"] as? String, "text")
    XCTAssertTrue((content.first?["text"] as? String)?.contains("Mac Coffee") == true)
    XCTAssertTrue(result.stderr.contains("APP_NOT_RUNNING"))
  }

  func testResourcesExposeCapabilitiesAndVersionedUnavailableStatus() throws {
    let result = try runHelper(
      inputPhases: initializedPhases(
        requests: [
          #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"maccoffee://capabilities"}}"#,
          #"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"maccoffee://status"}}"#,
        ],
        totalResponseCount: 3
      )
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    let capabilities = try parseJSONObject(resourceText(withID: 2, in: messages))
    XCTAssertEqual((capabilities["schemaVersion"] as? NSNumber)?.intValue, 1)
    XCTAssertEqual(capabilities["protocolVersion"] as? String, "2025-11-25")
    XCTAssertEqual(capabilities["appAvailable"] as? Bool, false)
    XCTAssertEqual(capabilities["statusSubscriptions"] as? Bool, true)
    XCTAssertEqual(
      Set(try array(capabilities["tools"]).compactMap { $0 as? String }),
      [
        "maccoffee_get_status",
        "maccoffee_set_session",
        "maccoffee_stop_session",
        "maccoffee_set_battery_threshold",
        "maccoffee_set_launch_at_login",
        "maccoffee_set_language",
      ]
    )

    let status = try parseJSONObject(resourceText(withID: 3, in: messages))
    XCTAssertEqual((status["schemaVersion"] as? NSNumber)?.intValue, 1)
    let error = try dictionary(status["error"])
    XCTAssertEqual(error["code"] as? String, "APP_NOT_RUNNING")
    XCTAssertEqual(error["retryable"] as? Bool, true)
  }

  func testStatusSubscriptionReportsUnavailableAppWithStableCode() throws {
    let result = try runHelper(
      inputPhases: initializedPhases(
        requests: [
          #"{"jsonrpc":"2.0","id":2,"method":"resources/subscribe","params":{"uri":"maccoffee://status"}}"#
        ],
        totalResponseCount: 2
      )
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    let response = try message(withID: 2, in: messages)
    let error = try dictionary(response["error"])
    XCTAssertTrue((error["message"] as? String)?.contains("APP_NOT_RUNNING") == true)
    XCTAssertTrue(result.stderr.contains("APP_NOT_RUNNING"))
  }

  func testMalformedJSONProducesProtocolErrorAndServerRecovers() throws {
    let result = try runHelper(
      inputPhases: [
        HelperInputPhase(
          lines: ["{not-json"],
          expectedTotalResponseCount: 1
        ),
        HelperInputPhase(
          lines: [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"MacCoffeeIntegrationTests","version":"1.0"}}}"#
          ],
          expectedTotalResponseCount: 2
        ),
        HelperInputPhase(
          lines: [
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}"#,
          ],
          expectedTotalResponseCount: 3
        ),
      ]
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    XCTAssertEqual(messages.count, 3)
    let parseError = try XCTUnwrap(messages.first { $0["error"] != nil })
    XCTAssertEqual(
      (try dictionary(parseError["error"])["code"] as? NSNumber)?.intValue,
      -32_700
    )
    XCTAssertNotNil(try message(withID: 1, in: messages)["result"])
    XCTAssertNotNil(try message(withID: 2, in: messages)["result"])
  }

  func testCancellationStopsToolCallAndServerRemainsResponsive() throws {
    let result = try runHelper(
      inputPhases: initializedPhases(
        requests: [
          #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"maccoffee_get_status","arguments":{}}}"#,
          #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":2,"reason":"integration test"}}"#,
          #"{"jsonrpc":"2.0","id":3,"method":"ping","params":{}}"#,
        ],
        totalResponseCount: 2
      )
    )

    XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    let messages = try result.stdoutLines.map(parseJSONObject)
    XCTAssertNotNil(try message(withID: 3, in: messages)["result"])
    XCTAssertNil(messages.first { ($0["id"] as? NSNumber)?.intValue == 2 })
  }

  private func runHelper(
    inputPhases: [HelperInputPhase]
  ) throws -> HelperProcessResult {
    let executableURL = Bundle(for: Self.self).bundleURL
      .deletingLastPathComponent()
      .appendingPathComponent("MacCoffeeMCP")
    XCTAssertTrue(
      FileManager.default.isExecutableFile(atPath: executableURL.path),
      "Missing built helper at \(executableURL.path)"
    )

    let process = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = executableURL
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    let output = LockedOutputBuffer()
    stdout.fileHandleForReading.readabilityHandler = { handle in
      output.append(handle.availableData)
    }
    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }
    try process.run()

    for phase in inputPhases {
      let received = expectation(
        description: "MacCoffeeMCP writes \(phase.expectedTotalResponseCount) protocol responses"
      )
      output.fulfillWhenLineCountReaches(
        phase.expectedTotalResponseCount,
        expectation: received
      )
      let input = Data((phase.lines.joined(separator: "\n") + "\n").utf8)
      try stdin.fileHandleForWriting.write(contentsOf: input)
      guard XCTWaiter.wait(for: [received], timeout: phase.responseTimeout) == .completed else {
        process.terminate()
        _ = terminated.wait(timeout: .now() + 1)
        throw TestFailure(
          "MacCoffeeMCP did not produce \(phase.expectedTotalResponseCount) responses"
        )
      }
    }
    try stdin.fileHandleForWriting.close()

    guard terminated.wait(timeout: .now() + 5) == .success else {
      process.terminate()
      throw TestFailure("MacCoffeeMCP did not exit after stdin EOF")
    }
    stdout.fileHandleForReading.readabilityHandler = nil
    output.append(stdout.fileHandleForReading.readDataToEndOfFile())

    return HelperProcessResult(
      terminationStatus: process.terminationStatus,
      stdout: String(decoding: output.data, as: UTF8.self),
      stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
  }

  private func productVersion() throws -> String {
    let configurationURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Config/Shared.xcconfig")
    let contents = try String(contentsOf: configurationURL, encoding: .utf8)
    guard let line = contents.components(separatedBy: .newlines).first(where: {
      $0.hasPrefix("MARKETING_VERSION = ")
    }) else {
      throw TestFailure("Missing MARKETING_VERSION in Shared.xcconfig")
    }
    return String(line.dropFirst("MARKETING_VERSION = ".count))
  }

  private func initializedPhases(
    requests: [String],
    totalResponseCount: Int
  ) -> [HelperInputPhase] {
    [
      HelperInputPhase(
        lines: [
          #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"MacCoffeeIntegrationTests","version":"1.0"}}}"#
        ],
        expectedTotalResponseCount: 1
      ),
      HelperInputPhase(
        lines: [
          #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        ] + requests,
        expectedTotalResponseCount: totalResponseCount
      ),
    ]
  }

  private func parseJSONObject(_ line: String) throws -> [String: Any] {
    try dictionary(
      JSONSerialization.jsonObject(with: Data(line.utf8), options: [])
    )
  }

  private func message(
    withID id: Int,
    in messages: [[String: Any]]
  ) throws -> [String: Any] {
    guard let message = messages.first(where: { ($0["id"] as? NSNumber)?.intValue == id }) else {
      throw TestFailure("Missing JSON-RPC response for id \(id)")
    }
    return message
  }

  private func resourceText(
    withID id: Int,
    in messages: [[String: Any]]
  ) throws -> String {
    let result = try dictionary(try message(withID: id, in: messages)["result"])
    let contents = try array(result["contents"]).map(dictionary)
    return try XCTUnwrap(contents.first?["text"] as? String)
  }

  private func dictionary(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
      throw TestFailure("Expected JSON object")
    }
    return value
  }

  private func array(_ value: Any?) throws -> [Any] {
    guard let value = value as? [Any] else {
      throw TestFailure("Expected JSON array")
    }
    return value
  }

  private func assertRequired(
    _ expected: Set<String>,
    in schema: [String: Any]
  ) throws {
    let required = try array(schema["required"]).compactMap { $0 as? String }
    XCTAssertEqual(Set(required), expected)
  }

  private func properties(in schema: [String: Any]) throws -> [String: Any] {
    try dictionary(schema["properties"])
  }
}

private struct HelperProcessResult {
  let terminationStatus: Int32
  let stdout: String
  let stderr: String

  var stdoutLines: [String] {
    stdout.split(whereSeparator: \.isNewline).map(String.init)
  }
}

private struct HelperInputPhase {
  let lines: [String]
  let expectedTotalResponseCount: Int
  let responseTimeout: TimeInterval

  init(
    lines: [String],
    expectedTotalResponseCount: Int,
    responseTimeout: TimeInterval = 7
  ) {
    self.lines = lines
    self.expectedTotalResponseCount = expectedTotalResponseCount
    self.responseTimeout = responseTimeout
  }
}

private struct TestFailure: Error {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

private final class LockedOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = Data()
  private var waiters: [(lineCount: Int, expectation: XCTestExpectation)] = []

  var data: Data {
    lock.withLock { storage }
  }

  func append(_ data: Data) {
    let fulfilled = lock.withLock {
      storage.append(data)
      let currentLineCount = lineCount
      let fulfilled = waiters.filter { currentLineCount >= $0.lineCount }
      waiters.removeAll { currentLineCount >= $0.lineCount }
      return fulfilled.map(\.expectation)
    }
    for expectation in fulfilled {
      expectation.fulfill()
    }
  }

  func fulfillWhenLineCountReaches(
    _ target: Int,
    expectation: XCTestExpectation
  ) {
    let alreadyReached = lock.withLock {
      if lineCount >= target {
        return true
      }
      waiters.append((target, expectation))
      return false
    }
    if alreadyReached { expectation.fulfill() }
  }

  private var lineCount: Int {
    storage.reduce(into: 0) { count, byte in
      if byte == UInt8(ascii: "\n") { count += 1 }
    }
  }
}
