import Foundation
import MCP
import MacCoffeeCore

public enum MCPResourceAdapter {
  static func register(
    on server: Server,
    runtime: MCPHelperRuntime
  ) async {
    await server.withMethodHandler(ListResources.self) { _ in
      .init(resources: resources)
    }
    await server.withMethodHandler(ReadResource.self) { parameters in
      let data: Data
      switch MCPResourceURI(rawValue: parameters.uri) {
      case .status:
        data = await resourceData {
          try await runtime.perform(
            action: MCPXPCAction.readStatus.rawValue,
            payloadJSON: Data("{}".utf8)
          )
        }
      case .capabilities:
        data = await capabilitiesData(runtime: runtime)
      case .activity:
        data = await resourceData {
          try await runtime.perform(
            action: MCPXPCAction.readActivity.rawValue,
            payloadJSON: Data("{}".utf8)
          )
        }
      case nil:
        throw MCPError.invalidParams("Unknown Mac Coffee resource URI.")
      }
      return .init(contents: [
        .text(
          String(decoding: data, as: UTF8.self),
          uri: parameters.uri,
          mimeType: "application/json"
        )
      ])
    }
    await server.withMethodHandler(ResourceSubscribe.self) { parameters in
      guard parameters.uri == MCPResourceURI.status.rawValue else {
        throw MCPError.invalidParams("Only maccoffee://status supports subscriptions.")
      }
      do {
        try await runtime.subscribeStatus { _ in
          Task {
            try? await server.notify(
              ResourceUpdatedNotification.message(.init(uri: parameters.uri))
            )
          }
        }
        return .init()
      } catch {
        throw subscriptionError(error)
      }
    }
    await server.withMethodHandler(ResourceUnsubscribe.self) { parameters in
      guard parameters.uri == MCPResourceURI.status.rawValue else {
        throw MCPError.invalidParams("Only maccoffee://status supports subscriptions.")
      }
      await runtime.unsubscribeStatus()
      return .init()
    }
  }

  private static let resources = [
    Resource(
      name: "Mac Coffee status",
      uri: MCPResourceURI.status.rawValue,
      description: "Current session, battery, language, and Launch at Login state.",
      mimeType: "application/json"
    ),
    Resource(
      name: "Mac Coffee capabilities",
      uri: MCPResourceURI.capabilities.rawValue,
      description: "Stable protocol capabilities and current app availability.",
      mimeType: "application/json"
    ),
    Resource(
      name: "Mac Coffee activity",
      uri: MCPResourceURI.activity.rawValue,
      description: "Bounded in-memory activity for the current app run.",
      mimeType: "application/json"
    ),
  ]

  private static func resourceData(
    _ operation: () async throws -> Data
  ) async -> Data {
    do {
      return try await operation()
    } catch {
      let error = MCPAdapterError(error)
      MCPDiagnostics.report("\(error.code.rawValue): \(error.message)")
      return (try? JSONEncoder().encode(error.structuredContent))
        ?? Data(
          "{\"schemaVersion\":1,\"error\":{\"code\":\"INTERNAL_ERROR\",\"retryable\":false}}".utf8)
    }
  }

  private static func capabilitiesData(runtime: MCPHelperRuntime) async -> Data {
    let value = Value.object([
      "schemaVersion": .int(MCPContract.schemaVersion),
      "protocolVersion": .string(Version.latest),
      "appAvailable": .bool(await runtime.appAvailable()),
      "statusSubscriptions": true,
      "tools": .array(MCPToolName.allCases.map { .string($0.rawValue) }),
      "resources": .array(MCPResourceURI.allCases.map { .string($0.rawValue) }),
    ])
    return (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
  }

  private static func subscriptionError(_ source: Error) -> MCPError {
    let error = MCPAdapterError(source)
    MCPDiagnostics.report("\(error.code.rawValue): \(error.message)")
    return MCPError.internalError("\(error.code.rawValue): \(error.message)")
  }
}
