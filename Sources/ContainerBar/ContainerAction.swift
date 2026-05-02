import Foundation

/// Actions that can be performed on a container.
enum ContainerAction {
    case start(String)
    case stop(String)
    case restart(String)
    case remove(String)
    case copyId(String)
    case viewLogs(String)
}
