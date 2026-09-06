import Foundation

public final class MCPBrokerReplyGate<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, any Error>?

  public init(_ continuation: CheckedContinuation<Value, any Error>) {
    self.continuation = continuation
  }

  public func resolve(_ result: Result<Value, any Error>) {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}
