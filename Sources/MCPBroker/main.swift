import Foundation

let peerValidator = MCPBrokerPeerValidator()
let delegate = MCPBrokerListenerDelegate { connection in
  peerValidator.role(for: connection)
}
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
dispatchMain()
