//
//  Device.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/06/29.
//

import Foundation
import CoreBluetooth
import AudioToolbox //追加インポート

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
//    @Published var debugnum : Int = 3
    @Published var closeDeviceCount = 0
    @Published var closeLongDeviceCount = 0
    @Published var closeDeviceScore = 1
    @Published var closeLongDeviceScore = 1
    @Published var showAlert = false
    @Published var showLongAlert = false

    var devicecount = 0
    
    //public func addDevice(deviceName: String, uuidString: String, rssi: NSNumber, state: CBPeripheralState) {
    public func addDevice(peripheral: CBPeripheral, tmprssi: NSNumber?=nil) { // rssi は分からなければ nil
        // エラーの時に rssi=127 になるので、修正
        // rssiがnilだと、表示のところでエラーになるので、とりあえず -128 にしておく 2021/9/24
        var rssi: NSNumber? = -128
        if tmprssi == nil {
            rssi = -128
        } else if tmprssi as! Int > 0 { // 実際は 127 だけのはずだけど正の時にしておく
            rssi = -128
        } else {
            rssi = tmprssi
        }
        
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
        addDevice(peripheral: peripheral, tmprssi: nil)
    }

    public func updateDevicewithRSSI(peripheral: CBPeripheral, rssi: NSNumber) {
        print("updateDevicewithRSSI \(peripheral.name ?? "unknown") \(peripheral.identifier.uuidString)")
        addDevice(peripheral: peripheral, tmprssi: rssi)
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
        // 上のループと一緒にできるけど、外出しの関数にする可能性もあるので、とりあえずもう一度計算する
        var TmpCloseDeviceCount = 0
        var TmpCloseLongDeviceCount = 0
        for device in devicelist {
            let rssi = device.rssi ?? (-100) // nil だったら -100  にしておく。
            // 濃厚接触者は、1m以内に15分以上
            if Int(truncating: rssi) > -60 { // 1m以内
                // 最初の検出から 900 秒以上たっていて、
                // 最後の検出から 90 秒以上たっていない
                if (now.timeIntervalSince1970 - device.lastDate.timeIntervalSince1970 < 90)
                    && (now.timeIntervalSince1970 - device.firstDate.timeIntervalSince1970 > 900) {
                    TmpCloseLongDeviceCount = TmpCloseLongDeviceCount + 1
                }
            }
            // 密接の範囲、3m以内に90秒以内に
            if Int(truncating: rssi) > -80 { // 3m以内
                // 最後の検出から 90 秒以上たっていない
                if (now.timeIntervalSince1970 - device.lastDate.timeIntervalSince1970 < 90) {
                    TmpCloseDeviceCount = TmpCloseDeviceCount + 1
                }

            }
        }
        closeDeviceCount = TmpCloseDeviceCount
        closeLongDeviceCount = TmpCloseLongDeviceCount
        closeDeviceScore = calcCloseDeviceScore(closeDeviceCount: closeDeviceCount)
        closeLongDeviceScore = calcCloseLongDeviceScore(closeLongDeviceCount: closeLongDeviceCount)

        if let glog = GlobalVar.shared.gLog {
            glog.addItem(logText: "DeviceCount, Alarm, 0000, \(devicecount)")
            glog.addItem(logText: "CloseDeviceCount, Alarm, 0000, \(closeDeviceCount), \(closeDeviceScore)")
            glog.addItem(logText: "CloseLongDeviceCount, Alarm, 0000, \(closeLongDeviceCount), \(closeLongDeviceScore)")
        }
    }
    
    func calcCloseDeviceScore(closeDeviceCount: Int)->Int {
        if closeDeviceCount > 30 {
            if showAlert == false {
                //アラーム音を鳴らす
                //AudioServicesPlayAlertSoundWithCompletion(1151, nil)
                
                // SystemSoundIDは0にしてurlの音源を再生する
                var soundIdRing:SystemSoundID = 0
                 
                if let soundUrl = URL(string:
                                  "/System/Library/Audio/UISounds/nano/HealthNotificationUrgent.caf"){
                    AudioServicesCreateSystemSoundID(soundUrl as CFURL, &soundIdRing)
                    AudioServicesPlaySystemSound(soundIdRing)
                    print(soundIdRing)
                }
                
                //バイブレーションを作動させる
                AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) {}
                
                showAlert = true
                
            }

            return 3
        } else if closeDeviceCount > 15 {
            return 2
        } else {
            return 1
        }
    }
    
    func calcCloseLongDeviceScore(closeLongDeviceCount: Int)->Int {
    
        if closeLongDeviceCount > 10 {
            if showLongAlert == false {
                //アラーム音を鳴らす
                //AudioServicesPlayAlertSoundWithCompletion(1151, nil)
                
                // SystemSoundIDは0にしてurlの音源を再生する
                var soundIdRing:SystemSoundID = 0
                 
                if let soundUrl = URL(string:
                                  "/System/Library/Audio/UISounds/nano/HealthNotificationUrgent.caf"){
                    AudioServicesCreateSystemSoundID(soundUrl as CFURL, &soundIdRing)
                    AudioServicesPlaySystemSound(soundIdRing)
                    print(soundIdRing)
                }
                
                //バイブレーションを作動させる
                AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) {}
                
                showLongAlert = true
                
            }
            return 3
        } else if closeLongDeviceCount > 5 {
            return 2
        } else {
            return 1
        }
    }
}
