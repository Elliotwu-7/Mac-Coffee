import Foundation

@MainActor
public protocol UpdaterProviding: AnyObject {
    var state: UpdateStateController { get }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
    func showAvailableUpdate()
    func dismissAvailableUpdate()
}
