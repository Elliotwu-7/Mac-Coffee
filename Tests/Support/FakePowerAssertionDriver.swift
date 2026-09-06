import Foundation
import IOKit.pwr_mgt
@testable import MacCoffeeCore

final class FakePowerAssertionDriver: PowerAssertionDriving {
    enum Event: Equatable {
        case create(String)
        case release(IOPMAssertionID)
    }

    enum FakeError: Error {
        case createFailed
        case releaseFailed
    }

    private(set) var events: [Event] = []
    private(set) var createdTypes: [String] = []
    var failCreateAtCall: Int?
    var failReleaseIDs: Set<IOPMAssertionID>
    private var createCount = 0
    private var nextID: IOPMAssertionID = 1

    init(failCreateAtCall: Int? = nil, failReleaseIDs: Set<IOPMAssertionID> = []) {
        self.failCreateAtCall = failCreateAtCall
        self.failReleaseIDs = failReleaseIDs
    }

    func create(type: CFString, name: CFString) throws -> IOPMAssertionID {
        createCount += 1
        let stringType = type as String
        events.append(.create(stringType))
        createdTypes.append(stringType)
        if createCount == failCreateAtCall {
            throw FakeError.createFailed
        }
        defer { nextID += 1 }
        return nextID
    }

    func release(id: IOPMAssertionID) throws {
        events.append(.release(id))
        if failReleaseIDs.contains(id) {
            throw FakeError.releaseFailed
        }
    }
}
