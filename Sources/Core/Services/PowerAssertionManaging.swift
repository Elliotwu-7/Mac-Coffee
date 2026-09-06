import Foundation

public protocol PowerAssertionManaging: AnyObject {
    var activeMode: WakeMode { get }
    func transition(to mode: WakeMode) throws
    func releaseAll()
}
