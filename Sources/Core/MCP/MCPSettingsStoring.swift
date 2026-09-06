import CoreFoundation
import Foundation

public protocol MCPSettingsStoring: SettingsStoring {
  var mcpEnabled: Bool { get set }
}

extension UserDefaultsSettingsStore: MCPSettingsStoring {
  public var mcpEnabled: Bool {
    get {
      guard let value = defaults.object(forKey: "mcpEnabled") as? NSNumber,
        CFGetTypeID(value) == CFBooleanGetTypeID()
      else {
        return false
      }
      return value.boolValue
    }
    set { defaults.set(newValue, forKey: "mcpEnabled") }
  }
}
