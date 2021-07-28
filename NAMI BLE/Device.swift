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
    var peripheral: CBPeripheral // これだけ save してあれば、他のメンバーはいらないかも？
    var deviceName: String
    var uuidString: String
    var rssi: NSNumber?
    var firstDate: Date
    var lastDate: Date
    var state: CBPeripheralState

}

class Devices : ObservableObject {
    @Published var devicelist : [DeviceItem] = []
    
    var devicecount = 0
    
    //public func addDevice(deviceName: String, uuidString: String, rssi: NSNumber, state: CBPeripheralState) {
    public func addDevice(peripheral: CBPeripheral, rssi: NSNumber?=nil) { // rssi は分からなければ nil
        let deviceName = peripheral.name ?? "unknown"
        let uuidString = peripheral.identifier.uuidString
        let state = peripheral.state

        // for debug
        /*
        for index in 0..<devicelist.count {
            let device = devicelist[index]
            if device.peripheral == peripheral {
                print("I found the same peripheral")
                if device.uuidString != uuidString {
                    print("I found the different uuid")
                    print("device.uuidString: \(device.uuidString), uuidString: \(uuidString)")
                }
            }
        } */
        // これは発生しないみたい（短時間では、、、）
        
        for index in 0..<devicelist.count {
            let device = devicelist[index]
            if device.uuidString == uuidString {
                print("This device is in the devicelist \(uuidString)")
                if device.deviceName == "unknow" {
                    devicelist[index].deviceName = deviceName
                }
                devicelist[index].lastDate = Date()
                
                devicelist[index].rssi = rssi ?? device.rssi // rssiがnilなら、前の値のまま
                
                devicelist[index].state = state
                print("lastDate for \(uuidString) is updated to \(devicelist[index].lastDate)")

                
                return
            }
        }
        
        devicecount = devicecount + 1
        devicelist.append(DeviceItem(peripheral: peripheral, deviceName: deviceName, uuidString: uuidString, rssi: rssi, firstDate: Date(), lastDate: Date(), state: state))
    }
    
    public func updateDevice(peripheral: CBPeripheral) {
        print("updateDevice \(peripheral.name ?? "unknown") \(peripheral.identifier.uuidString)")
        addDevice(peripheral: peripheral, rssi: nil)
    }

    public func updateDevicewithRSSI(peripheral: CBPeripheral, rssi: NSNumber) {
        print("updateDevicewithRSSI \(peripheral.name ?? "unknown") \(peripheral.identifier.uuidString)")
        addDevice(peripheral: peripheral, rssi: rssi)
    }

    public func clearObsoleteDevice(period: NSNumber) {
        print("clearObsoleteDevice(\(period))")
        let now = Date()
        for index in (0..<devicelist.count).reversed() {
            if now.timeIntervalSince1970 - devicelist[index].lastDate.timeIntervalSince1970 > Double(truncating: period) {
                devicelist.remove(at: index)
                devicecount = devicecount - 1
            }
        }
    }
    
}
