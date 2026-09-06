import Foundation

@objc(MCPXPCAppService)
public protocol MCPXPCAppService {
    func beginAuthentication(
        _ hello: MCPXPCAuthenticationHello,
        withReply reply: @escaping (MCPXPCAuthenticationChallenge?, MCPXPCError?) -> Void
    )

    func completeAuthentication(
        _ proof: MCPXPCAuthenticationProof,
        withReply reply: @escaping (MCPXPCAuthenticationResult?, MCPXPCError?) -> Void
    )

    func perform(
        _ request: MCPXPCRequest,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    )

    func subscribe(
        _ request: MCPXPCSubscription,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    )

    func cancel(_ request: MCPXPCCancellation)
    func close(_ request: MCPXPCClose)
}

@objc(MCPXPCHelperCallback)
public protocol MCPXPCHelperCallback {
    func receive(_ event: MCPXPCEvent)
    func closed(_ close: MCPXPCClose, withReply reply: @escaping () -> Void)
}

public enum MCPXPCInterfaces {
    public static func appService() -> NSXPCInterface {
        let interface = NSXPCInterface(with: MCPXPCAppService.self)
        set(
            [MCPXPCAuthenticationHello.self],
            on: interface,
            selector: #selector(MCPXPCAppService.beginAuthentication(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCAuthenticationChallenge.self],
            on: interface,
            selector: #selector(MCPXPCAppService.beginAuthentication(_:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )
        set(
            [MCPXPCError.self],
            on: interface,
            selector: #selector(MCPXPCAppService.beginAuthentication(_:withReply:)),
            argumentIndex: 1,
            ofReply: true
        )
        set(
            [MCPXPCAuthenticationProof.self],
            on: interface,
            selector: #selector(MCPXPCAppService.completeAuthentication(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCAuthenticationResult.self],
            on: interface,
            selector: #selector(MCPXPCAppService.completeAuthentication(_:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )
        set(
            [MCPXPCError.self],
            on: interface,
            selector: #selector(MCPXPCAppService.completeAuthentication(_:withReply:)),
            argumentIndex: 1,
            ofReply: true
        )
        set(
            [MCPXPCRequest.self],
            on: interface,
            selector: #selector(MCPXPCAppService.perform(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCResponse.self, MCPXPCError.self],
            on: interface,
            selector: #selector(MCPXPCAppService.perform(_:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )
        set(
            [MCPXPCSubscription.self],
            on: interface,
            selector: #selector(MCPXPCAppService.subscribe(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCResponse.self, MCPXPCError.self],
            on: interface,
            selector: #selector(MCPXPCAppService.subscribe(_:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )
        set(
            [MCPXPCCancellation.self],
            on: interface,
            selector: #selector(MCPXPCAppService.cancel(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCClose.self],
            on: interface,
            selector: #selector(MCPXPCAppService.close(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        return interface
    }

    public static func helperCallback() -> NSXPCInterface {
        let interface = NSXPCInterface(with: MCPXPCHelperCallback.self)
        set(
            [MCPXPCEvent.self],
            on: interface,
            selector: #selector(MCPXPCHelperCallback.receive(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        set(
            [MCPXPCClose.self],
            on: interface,
            selector: #selector(MCPXPCHelperCallback.closed(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        return interface
    }

    private static func set(
        _ classes: [AnyClass],
        on interface: NSXPCInterface,
        selector: Selector,
        argumentIndex: Int,
        ofReply: Bool
    ) {
        let allowed = NSSet(array: classes) as! Set<AnyHashable>
        interface.setClasses(
            allowed,
            for: selector,
            argumentIndex: argumentIndex,
            ofReply: ofReply
        )
    }
}
