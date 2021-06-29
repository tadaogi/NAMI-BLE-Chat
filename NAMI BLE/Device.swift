//
//  Device.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/06/29.
//

import Foundation


struct DeviceItem {
    var code = UUID()
    var deviceName: String
    var uuidString: String
}

class Devices : ObservableObject {
    @Published var devicelist : [DeviceItem] = [
        DeviceItem(deviceName: "device0",uuidString: "xxxx"),
        DeviceItem(deviceName: "device1",uuidString: "zzzz")
    ]
    
    var devicecount = 0
    
    func addDevice(deviceName: String, uuidString: String) {

        
        devicecount = devicecount + 1
        devicelist.append(DeviceItem(deviceName: "[\(self.devicecount)]: \(deviceName)", uuidString: uuidString))
    }
    
}
