import Foundation
import Network

protocol NetworkSavingChecking: Sendable {
    func permitsAutomaticDownloads(wifiOnly: Bool) async -> Bool
}

final class NetworkSavingPolicy: NetworkSavingChecking, @unchecked Sendable {
    static let shared = NetworkSavingPolicy()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var wifi = false
    private var connected = false
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock {
                self.connected = path.status == .satisfied
                self.wifi = self.connected && path.usesInterfaceType(.wifi) && !path.isExpensive && !path.isConstrained
            }
            NotificationCenter.default.post(name: .mannaSavingNetworkChanged, object: nil)
        }
        monitor.start(queue: DispatchQueue(label: "manna.network-saving"))
    }
    func permitsAutomaticDownloads(wifiOnly: Bool) async -> Bool {
        lock.withLock { wifiOnly ? wifi : connected }
    }
    deinit { monitor.cancel() }
}

extension Notification.Name {
    static let mannaSavingNetworkChanged = Notification.Name("mannaSavingNetworkChanged")
}
