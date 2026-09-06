import Foundation
import MCP
import MacCoffeeCore

public enum MCPToolAdapter {
  static func register(
    on server: Server,
    runtime: MCPHelperRuntime
  ) async {
    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: tools)
    }
    await server.withMethodHandler(CallTool.self) { parameters in
      try await call(parameters, runtime: runtime)
    }
  }

  private static let tools = MCPToolName.allCases.map { name in
    Tool(
      name: name.rawValue,
      description: description(for: name),
      inputSchema: schema(for: name)
    )
  }

  private static func description(for name: MCPToolName) -> String {
    switch name {
    case .getStatus:
      "Read the current Mac Coffee status."
    case .setSession:
      "Start or update a Mac Coffee wake session."
    case .stopSession:
      "Stop the current Mac Coffee wake session."
    case .setBatteryThreshold:
      "Set the low-battery safety threshold."
    case .setLaunchAtLogin:
      "Enable or disable Launch at Login."
    case .setLanguage:
      "Change the Mac Coffee interface language."
    }
  }

  private static func schema(for name: MCPToolName) -> Value {
    switch name {
    case .getStatus:
      objectSchema(properties: [:], required: [])
    case .setSession:
      objectSchema(
        properties: [
          "mode": .object([
            "type": "string",
            "enum": ["system", "display"],
          ]),
          "duration": .object([
            "type": "string",
            "enum": ["minutes30", "hours1", "hours2", "hours4", "hours8", "indefinite"],
          ]),
          "requestId": requestIDSchema,
        ],
        required: ["mode", "duration"]
      )
    case .stopSession:
      objectSchema(
        properties: ["requestId": requestIDSchema],
        required: []
      )
    case .setBatteryThreshold:
      objectSchema(
        properties: [
          "percent": .object([
            "type": "integer",
            "minimum": 10,
            "maximum": 30,
          ]),
          "requestId": requestIDSchema,
        ],
        required: ["percent"]
      )
    case .setLaunchAtLogin:
      objectSchema(
        properties: [
          "enabled": .object(["type": "boolean"]),
          "requestId": requestIDSchema,
        ],
        required: ["enabled"]
      )
    case .setLanguage:
      objectSchema(
        properties: [
          "language": .object([
            "type": "string",
            "enum": ["system", "ru", "en", "de", "fr", "zh-Hans", "ja", "ko", "es"],
          ]),
          "requestId": requestIDSchema,
        ],
        required: ["language"]
      )
    }
  }

  private static let requestIDSchema = Value.object([
    "type": "string",
    "minLength": 1,
    "maxLength": .int(MCPContract.maximumRequestIDLength),
  ])

  private static func objectSchema(
    properties: [String: Value],
    required: [Value]
  ) -> Value {
    .object([
      "type": "object",
      "properties": .object(properties),
      "required": .array(required),
      "additionalProperties": false,
    ])
  }

  private static func call(
    _ parameters: CallTool.Parameters,
    runtime: MCPHelperRuntime
  ) async throws -> CallTool.Result {
    do {
      await Task.yield()
      try Task.checkCancellation()
      guard MCPToolName(rawValue: parameters.name) != nil else {
        throw MCPAdapterError.invalidTool
      }
      let arguments = parameters.arguments ?? [:]
      let payload = try JSONEncoder().encode(arguments)
      let response = try await runtime.perform(
        action: parameters.name,
        payloadJSON: payload
      )
      try Task.checkCancellation()
      let structured = try JSONDecoder().decode(Value.self, from: response)
      return CallTool.Result(
        content: [.text(text: displayText(in: response), annotations: nil, _meta: nil)],
        structuredContent: Optional.some(structured),
        isError: false
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let error = MCPAdapterError(error)
      MCPDiagnostics.report("\(error.code.rawValue): \(error.message)")
      return CallTool.Result(
        content: [.text(text: error.message, annotations: nil, _meta: nil)],
        structuredContent: Optional.some(error.structuredContent),
        isError: true
      )
    }
  }

  private static func displayText(in data: Data) -> String {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let displayText = object["displayText"] as? String,
      !displayText.isEmpty
    else {
      return "Mac Coffee updated."
    }
    return displayText
  }
}

struct MCPAdapterError: Error {
  static let invalidTool = MCPAdapterError(
    code: .invalidArgument,
    message: "Unknown Mac Coffee tool.",
    retryable: false
  )

  let code: MCPErrorCode
  let message: String
  let retryable: Bool

  init(code: MCPErrorCode, message: String, retryable: Bool) {
    self.code = code
    self.message = message
    self.retryable = retryable
  }

  init(_ error: Error) {
    switch error {
    case MCPXPCClientError.appNotRunning:
      self.init(
        code: .appNotRunning,
        message: "Mac Coffee is not running or its MCP integration is unavailable.",
        retryable: true
      )
    case MCPXPCClientError.clientUnpaired:
      self.init(
        code: .clientUnpaired,
        message: "Approve this client in Mac Coffee Settings before trying again.",
        retryable: false
      )
    case MCPXPCClientError.clientRevoked:
      self.init(
        code: .clientRevoked,
        message: "This client was revoked in Mac Coffee Settings.",
        retryable: false
      )
    case MCPXPCClientError.mcpDisabled:
      self.init(
        code: .mcpDisabled,
        message: "Enable MCP integration in Mac Coffee Settings.",
        retryable: false
      )
    case MCPXPCClientError.timedOut:
      self.init(
        code: .appBusy,
        message: "Mac Coffee did not respond before the local timeout.",
        retryable: true
      )
    case MCPXPCClientError.cancelled, is CancellationError:
      self.init(
        code: .internalError,
        message: "The Mac Coffee request was cancelled.",
        retryable: false
      )
    case MCPXPCClientError.protocolViolation:
      self.init(
        code: .internalError,
        message: "Mac Coffee rejected an invalid local protocol response.",
        retryable: false
      )
    case MCPXPCClientError.remote(let code, let message, let retryable):
      self.init(
        code: MCPErrorCode(rawValue: code) ?? .internalError,
        message: message,
        retryable: retryable
      )
    case let error as MCPAdapterError:
      self = error
    default:
      self.init(
        code: .internalError,
        message: "Mac Coffee could not complete the local request.",
        retryable: false
      )
    }
  }

  var structuredContent: Value {
    .object([
      "schemaVersion": .int(MCPContract.schemaVersion),
      "error": .object([
        "code": .string(code.rawValue),
        "message": .string(message),
        "retryable": .bool(retryable),
      ]),
    ])
  }
}
