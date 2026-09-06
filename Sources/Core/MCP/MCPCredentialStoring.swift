import Foundation

public protocol MCPCredentialStoring: AnyObject {
  func data(for key: String) throws -> Data?
  func setData(_ data: Data, for key: String) throws
  func removeData(for key: String) throws
}
