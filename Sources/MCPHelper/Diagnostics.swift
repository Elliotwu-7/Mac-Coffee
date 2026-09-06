import Foundation

public enum MCPDiagnostics {
  public static func report(_ message: String) {
    guard let data = "MacCoffeeMCP: \(message)\n".data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
  }
}
