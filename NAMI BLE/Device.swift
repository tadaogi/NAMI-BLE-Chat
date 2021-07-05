//
//  Device.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/06/29.
//

import Foundation
import CoreBluetooth

struct DeviceItem {
    var code = UUID()
    var deviceName: String
    var uuidString: String
    var rssi: NSNumber
    var firstDate: Date
    var lastDate: Date
    var state: CBPeripheralState

}

class Devices : ObservableObject {
    @Published var devicelist : [DeviceItem] = []
    
    var devicecount = 0
    
    public func addDevice(deviceName: String, uuidString: String, rssi: NSNumber, state: CBPeripheralState) {

        for index in 0..<devicelist.count {
            var device = devicelist[index]
            if device.uuidString == uuidString {
                print("This device is in the devicelist \(uuidString)")
                if device.deviceName == "unknow" {
                    device.deviceName = deviceName
                }
                device.lastDate = Date()
                device.rssi = rssi
                device.state = state
                return
            }
        }
        
        devicecount = devicecount + 1
        devicelist.append(DeviceItem(deviceName: deviceName, uuidString: uuidString, rssi: rssi, firstDate: Date(), lastDate: Date(), state: state))
    }
    
}
