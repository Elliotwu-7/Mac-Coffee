import Foundation
import XCTest
@testable import MacCoffeeCore

final class MCPXPCTests: XCTestCase {
    func testEveryDTORequiresSecureCodingAndRoundTrips() throws {
        let presentation = MCPAuthenticationPresentation(
            clientIdentifier: "codex-client",
            displayName: "Codex",
            publicKey: Data(repeating: 2, count: 65),
            parentIdentity: MCPCodeIdentity(
                executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
                bundleIdentifier: "com.openai.codex",
                teamIdentifier: "OPENAI",
                signingIdentifier: "com.openai.codex",
                codeDirectoryHash: "abcd",
                isSigned: true
            )
        )
        let hello = MCPXPCAuthenticationHello(
            schemaVersion: MCPContract.schemaVersion,
            connectionIdentifier: "connection-1",
            presentationJSON: try JSONEncoder().encode(presentation)
        )
        let challenge = MCPXPCAuthenticationChallenge(
            schemaVersion: MCPContract.schemaVersion,
            challengeIdentifier: "challenge-1",
            nonce: Data(repeating: 1, count: 32),
            transcript: Data("transcript".utf8)
        )
        let proof = MCPXPCAuthenticationProof(
            schemaVersion: MCPContract.schemaVersion,
            challengeIdentifier: "challenge-1",
            signature: Data(repeating: 3, count: 70)
        )
        let authenticationResult = MCPXPCAuthenticationResult(
            schemaVersion: MCPContract.schemaVersion,
            state: .approvalRequired,
            clientJSON: nil,
            pairingRequestJSON: Data("{}".utf8)
        )
        let error = MCPXPCError(
            code: "CLIENT_UNPAIRED",
            message: "Approval required",
            retryable: false
        )
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8),
            deadline: Date(timeIntervalSince1970: 10_000)
        )
        let response = MCPXPCResponse(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            payloadJSON: Data("{\"ok\":true}".utf8),
            error: error
        )
        let subscription = MCPXPCSubscription(
            schemaVersion: MCPContract.schemaVersion,
            subscriptionIdentifier: "subscription-1",
            resourceURI: MCPResourceURI.status.rawValue,
            deadline: Date(timeIntervalSince1970: 10_000)
        )
        let event = MCPXPCEvent(
            schemaVersion: MCPContract.schemaVersion,
            subscriptionIdentifier: "subscription-1",
            sequence: 42,
            payloadJSON: Data("{\"mode\":\"off\"}".utf8)
        )
        let cancellation = MCPXPCCancellation(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1"
        )
        let close = MCPXPCClose(
            schemaVersion: MCPContract.schemaVersion,
            reason: .clientRequest,
            message: "Done"
        )

        XCTAssertTrue(MCPXPCAuthenticationHello.supportsSecureCoding)
        XCTAssertEqual(try roundTrip(hello).connectionIdentifier, "connection-1")
        XCTAssertEqual(try roundTrip(challenge).nonce, challenge.nonce)
        XCTAssertEqual(try roundTrip(proof).signature, proof.signature)
        XCTAssertEqual(try roundTrip(authenticationResult).state, .approvalRequired)
        XCTAssertEqual(try roundTrip(error).code, "CLIENT_UNPAIRED")
        XCTAssertEqual(try roundTrip(request).deadline, request.deadline)
        XCTAssertEqual(try roundTrip(response).error?.code, "CLIENT_UNPAIRED")
        XCTAssertEqual(try roundTrip(subscription).resourceURI, MCPResourceURI.status.rawValue)
        XCTAssertEqual(try roundTrip(event).sequence, 42)
        XCTAssertEqual(try roundTrip(cancellation).requestIdentifier, "request-1")
        XCTAssertEqual(try roundTrip(close).reason, .clientRequest)
    }

    func testSecureUnarchiveRejectsUnexpectedRootClass() throws {
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: NSArray(array: ["not", "a", "request"]),
            requiringSecureCoding: true
        )

        XCTAssertNil(
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: MCPXPCRequest.self,
                from: archive
            )
        )
    }

    func testSecureDecodeRejectsOversizedPayloadBeforeObjectConstruction() throws {
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data(repeating: 0, count: MCPXPCCodec.maximumJSONPayloadBytes + 1),
            deadline: Date(timeIntervalSince1970: 10_000)
        )
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: request,
            requiringSecureCoding: true
        )

        XCTAssertNil(
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: MCPXPCRequest.self,
                from: archive
            )
        )
    }

    func testCodecRejectsOversizedPayloadBeforeParsingJSON() {
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data(repeating: 0, count: MCPXPCCodec.maximumJSONPayloadBytes + 1),
            deadline: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertThrowsError(
            try MCPXPCCodec.decodeRequest(
                request,
                authenticatedClientIdentifier: "codex-client",
                now: Date(timeIntervalSince1970: 9_000)
            )
        ) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .payloadTooLarge)
        }
    }

    func testCodecRejectsUnknownSchemaVersion() {
        let cancellation = MCPXPCCancellation(
            schemaVersion: MCPContract.schemaVersion + 1,
            requestIdentifier: "request-1"
        )

        XCTAssertThrowsError(try MCPXPCCodec.validate(cancellation)) { error in
            XCTAssertEqual(
                error as? MCPXPCCodecError,
                .unsupportedSchemaVersion(MCPContract.schemaVersion + 1)
            )
        }
    }

    func testCodecRejectsExpiredDeadline() {
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8),
            deadline: Date(timeIntervalSince1970: 100)
        )

        XCTAssertThrowsError(
            try MCPXPCCodec.decodeRequest(
                request,
                authenticatedClientIdentifier: "codex-client",
                now: Date(timeIntervalSince1970: 101)
            )
        ) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .deadlineExpired)
        }
    }

    func testCodecRejectsRequestAndSubscriptionBeforeAuthentication() {
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8),
            deadline: Date(timeIntervalSince1970: 200)
        )
        let subscription = MCPXPCSubscription(
            schemaVersion: MCPContract.schemaVersion,
            subscriptionIdentifier: "subscription-1",
            resourceURI: MCPResourceURI.status.rawValue,
            deadline: Date(timeIntervalSince1970: 200)
        )

        XCTAssertThrowsError(
            try MCPXPCCodec.decodeRequest(
                request,
                authenticatedClientIdentifier: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .authenticationRequired)
        }
        XCTAssertThrowsError(
            try MCPXPCCodec.decodeSubscription(
                subscription,
                authenticatedClientIdentifier: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .authenticationRequired)
        }
    }

    func testCodecRejectsMalformedJSONInAuthenticationAndRequests() {
        let hello = MCPXPCAuthenticationHello(
            schemaVersion: MCPContract.schemaVersion,
            connectionIdentifier: "connection-1",
            presentationJSON: Data("{".utf8)
        )
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("not-json".utf8),
            deadline: Date(timeIntervalSince1970: 200)
        )

        XCTAssertThrowsError(try MCPXPCCodec.decodeAuthenticationHello(hello)) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .malformedJSON)
        }
        XCTAssertThrowsError(
            try MCPXPCCodec.decodeRequest(
                request,
                authenticatedClientIdentifier: "codex-client",
                now: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? MCPXPCCodecError, .malformedJSON)
        }
    }

    func testCodecDecodesValidatedAuthenticationRequestAndSubscription() throws {
        let presentation = MCPAuthenticationPresentation(
            clientIdentifier: "codex-client",
            displayName: "Codex",
            publicKey: Data(repeating: 2, count: 65),
            parentIdentity: MCPCodeIdentity(
                executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
                bundleIdentifier: "com.openai.codex",
                teamIdentifier: "OPENAI",
                signingIdentifier: "com.openai.codex",
                codeDirectoryHash: "abcd",
                isSigned: true
            )
        )
        let hello = MCPXPCAuthenticationHello(
            schemaVersion: MCPContract.schemaVersion,
            connectionIdentifier: "connection-1",
            presentationJSON: try JSONEncoder().encode(presentation)
        )
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: "request-1",
            action: MCPToolName.setLanguage.rawValue,
            payloadJSON: Data("{\"language\":\"ru\"}".utf8),
            deadline: Date(timeIntervalSince1970: 200)
        )
        let subscription = MCPXPCSubscription(
            schemaVersion: MCPContract.schemaVersion,
            subscriptionIdentifier: "subscription-1",
            resourceURI: MCPResourceURI.status.rawValue,
            deadline: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(try MCPXPCCodec.decodeAuthenticationHello(hello), presentation)
        let decodedRequest = try MCPXPCCodec.decodeRequest(
            request,
            authenticatedClientIdentifier: "codex-client",
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(decodedRequest.clientIdentifier, "codex-client")
        XCTAssertEqual(decodedRequest.action, MCPToolName.setLanguage.rawValue)
        XCTAssertEqual(decodedRequest.payload["language"] as? String, "ru")
        let decodedSubscription = try MCPXPCCodec.decodeSubscription(
            subscription,
            authenticatedClientIdentifier: "codex-client",
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(decodedSubscription.resourceURI, MCPResourceURI.status.rawValue)
    }

    func testXPCInterfacesDeclareExplicitAllowedClasses() {
        let service = MCPXPCInterfaces.appService()
        let callbacks = MCPXPCInterfaces.helperCallback()

        XCTAssertTrue(
            NSSet(set: service.classes(
                for: #selector(MCPXPCAppService.beginAuthentication(_:withReply:)),
                argumentIndex: 0,
                ofReply: false
            )).contains(MCPXPCAuthenticationHello.self)
        )
        XCTAssertTrue(
            NSSet(set: service.classes(
                for: #selector(MCPXPCAppService.perform(_:withReply:)),
                argumentIndex: 0,
                ofReply: true
            )).contains(MCPXPCResponse.self)
        )
        XCTAssertTrue(
            NSSet(set: callbacks.classes(
                for: #selector(MCPXPCHelperCallback.receive(_:)),
                argumentIndex: 0,
                ofReply: false
            )).contains(MCPXPCEvent.self)
        )
        XCTAssertTrue(
            NSSet(set: callbacks.classes(
                for: #selector(MCPXPCHelperCallback.closed(_:withReply:)),
                argumentIndex: 0,
                ofReply: false
            )).contains(MCPXPCClose.self)
        )
    }

    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T) throws -> T {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: true
        )
        return try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
        )
    }
}
