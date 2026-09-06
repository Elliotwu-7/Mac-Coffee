import Foundation
import MCP

public enum MCPServerAdapter {
  public static func makeServer() async -> Server {
    let runtime = MCPHelperRuntime()
    let server = Server(
      name: "MacCoffeeMCP",
      version: helperVersion,
      title: "Mac Coffee",
      instructions:
        "Control the running Mac Coffee app. Mac Coffee is never launched automatically.",
      capabilities: .init(
        resources: .init(subscribe: true, listChanged: false),
        tools: .init(listChanged: false)
      ),
      configuration: .strict
    )
    await MCPToolAdapter.register(on: server, runtime: runtime)
    await MCPResourceAdapter.register(on: server, runtime: runtime)
    return server
  }

  private static var helperVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0.0.0"
  }
}
