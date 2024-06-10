//
//  WiFiCheck.swift
//  WiFiTest
//
//  Created by Tadashi Ogino on 2024/02/15.
//

import Foundation
import Network

class WiFicheck: ObservableObject {
    
    private let monitor = NWPathMonitor()
    //private let queue = DispatchQueue.global(qos: .background)
    
    //private let queue = DispatchQueue.global(qos:.userInitiated)
    private let queue = DispatchQueue.global(qos:.default)
    // Warningが出るので、QoSクラスを変えてみた。あっているかどうか不明 2024/5/30

    @Published var isConnected = false

    init() {
        monitor.start(queue: queue)

        monitor.pathUpdateHandler = { path in
            print("network changed")
            print(path)
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.printAddresses()
                }
            } else {
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }
    
    // https://forums.developer.apple.com/forums/thread/109355
    func printAddresses() -> String {
        var addrList : UnsafeMutablePointer<ifaddrs>?
        guard
            getifaddrs(&addrList) == 0,
            let firstAddr = addrList
        else { return "0.0.0.0"}
        defer { freeifaddrs(addrList) }
        for cursor in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interfaceName = String(cString: cursor.pointee.ifa_name)
            let addrStr: String
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if
                let addr = cursor.pointee.ifa_addr,
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0,
                hostname[0] != 0
            {
                addrStr = String(cString: hostname)
                //print(addr.pointee.sa_family)
            } else {
                addrStr = "?"
            }
            if cursor.pointee.ifa_addr.pointee.sa_family == 2 {
                if interfaceName == "en0" {
                    print(interfaceName, addrStr)
                    return addrStr
                }
            }
        }
        return "0.0.0.0"
    }
}
