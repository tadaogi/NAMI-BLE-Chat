//
//  BLE.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

// どういう構成にすれば良いかまだ良くわからないので
// とりあえず、BLEというファイルにした

import Foundation
import CoreBluetooth
import SwiftUI

struct PeripheralInfo {
    var peripheral: CBPeripheral
    var rssi: NSNumber
    var username: String
    var firstDate: Date
    var lastDate: Date
    var logicalId: String      // ★ 追加
}

var UUID_Service_str = "73C98F4C-F74F-4918-9B0A-5EF4C6C021C6"
struct BLEcommService {
    static let UUID_Service = CBUUID(string: UUID_Service_str)
    static let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
    static let UUID_Write = CBUUID(string: "0C136FCC-3381-4F1E-9602-E2A3F8B70CEB")
    
    // ★ Android Device ID 用
    static let UUID_DeviceId = CBUUID(string: "D0A9F6B5-1234-4D8E-9E10-ABCDEF123456")

}
// Centralとして動く時の処理はこちら
var ConnectMode : Bool = true
var iPhoneMode : Bool = true
var debugLogMode : Bool = true


enum BLECentralState {
    case running
    case stop
}

public class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    //@EnvironmentObject var user: User
    
    var centralManager: CBCentralManager!
    var peripheralInfoArray = [PeripheralInfo]()
    fileprivate var serviceArray = [CBService]()

    let UUID_Service = BLEcommService.UUID_Service
    let UUID_Read = BLEcommService.UUID_Read
    let UUID_Write = BLEcommService.UUID_Write

    //@EnvironmentObject var log : Log
    var log : Log!
    var devices : Devices!
    var user : User!
    
    
    
    var userMessage: UserMessage!
    let connect_semaphore = DispatchSemaphore(value: 7) // connect は複数でも平気なはず/k
    
    var state: BLECentralState
    // 修正 2021/12/15
    //var connectedPeripheral: CBPeripheral! = nil
    //var foundCharacteristicR: CBCharacteristic! = nil
    //var obsoleteInterval: String = "600" // これはなくても大丈なのではないか？

    override init() {
        //self.centralManager = CBCentralManager()
        //self.peripheralManager = CBPeripheralManager()
        self.state = BLECentralState.stop
        iPhoneMode = UserDefaults.standard.bool(forKey: "iPhoneMode")
        print("BLECentral init is called")
        
        super.init()
        
        // スリープして再起動した時に見つける
        // 本当は Peripheral 側にも入れるべき
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
    }
    
    @objc func appDidBecomeActive() {
        print("Central App became active")
        reconnectBLE()
    }

    @objc func appWillEnterForeground() {
        print("Central App will enter foreground")
    }

    func reconnectBLE() {
        print("Central reconnect BLE is not implemented yet")
        // 再接続処理
        // どういう状態化か分からないので、とりあえず scan を停めて、再度起動しておく
        // できない
        // どうも起動直後も呼ばれるらしい
        if self.centralManager != nil {
            print("centralManager is not nil")
            // start した後は not nil
            stopScan()
            startScan()
        } else {
            // 起動直後は nil
            print("centralManager is nil")
        }

    }
    
    public func myinit(userMessage: UserMessage) {
        print("BLECentral myinit is called")
        self.userMessage = userMessage
        if self.userMessage.debugMessageFlag {
            self.userMessage.addItem(userMessageText: "BLECentral.myinit is called") // shoud be log
        }
    }
    
    func startCentralManager(log: Log, devices: Devices, user: User) {
        startCentral(log: log, devices: devices, user: user)
    }
            
    func startCentral(log: Log, devices: Devices, user: User) {
        self.log = log
        Task { @MainActor in
            self.log.addItem(logText:"startCentralManager,")
        }
        self.devices = devices
        self.user = user
        
        // この処理が正しいのかどうか不明
        if self.centralManager == nil {
            print("centralManger is nil")
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            //self.centralManager.scanForPeripherals(withServices: nil, options: nil)
            // ボタンで止めてから、再開する時はすでにcentralManagerは登録されているはずなので、ここでstartScanを呼ぶ
            startScan()
        }
        print("Central Manager State: \(self.centralManager.state)")
        
        // should wait until power on
        //startScan()
        
        // ContentViewからコピーしてきて修正
        Task { @MainActor in
            log.timerStart(bleCentral: self, timerIntervalString: self.user.timerInterval)
        }
        
        self.state = BLECentralState.running

    }
    
    // stop ボタンを押した時に、Centralがオンだったら呼ばれる
    func stopCentralManager() {
        //stopScan()
        stopCentral()
    }
    
    func stopCentral() {
        stopScan()
        self.state = BLECentralState.stop
        
        Task { @MainActor in
            self.log.timerStop() // この中で、transferCList を変更するので、とりあえず止めておく。
        }
        
        for transfer in transferCList {
            if transfer.valid {
                if (transfer.loopLock.lock(before:Date().addingTimeInterval(30)) == false) {
                    Task { @MainActor in
                        self.log.addItem(logText: "lock in stop Central failed")
                    }
                }
                transfer.valid = false
                self.centralManager.cancelPeripheralConnection(transfer.connectedPeripheral)
            }
        }
        
    }
    
    // 電源がオンになるのを待たないといけない
    func startScan() {
        print("startScan")
        
        // only NAMI test
        let UUID_str = CBUUID(string: UUID_Service_str)

//        self.centralManager.scanForPeripherals(withServices: [BLEcommService.UUID_Service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        //self.centralManager.scanForPeripherals(withServices: [UUID_str], options: nil)

        // 本当は、サービスのUUIDを指定するのが正しいはずだがうまく動かない
        // advertisement data の方が間違えていたので、これで動くはず
        if user.onlyNAMIMode {
            self.centralManager.scanForPeripherals(withServices: [UUID_Service], options: nil)
        } else {
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
        // 以下の方法ならうまくいく。ただし、FD6Fが入るとNG
        
        //let UUID0 = CBUUID(string: "180D") // heart rate
        //let UUID1 = CBUUID(string: "2A19") // battery level
        //let UUID2 = CBUUID(string: "1809") // health thermo
        
        //let UUID3 = CBUUID(string: "FD60") // covid FD6F FD6Fがあると全体的にうまくいかない
         
        //let UUID3 = CBUUID(string: "0000FD6F-0000-1000-8000-00805f9b34fb")
        
        //let UUID4 = CBUUID(string: "416DFC7B-D6E2-4373-9299-D81ACD3CC728")
        //let UUID5 = CBUUID(string: "0E2FD244-2114-466C-9F18-2D493CD70407")
        //let UUID6 = CBUUID(string: "90FA7ABE-FAB6-485E-B700-1A17804CAA13")
        //let UUID_180A = CBUUID(string: "180A")
        //let UUID_180F = CBUUID(string: "180F")
        
        //let UUID_str = CBUUID(string: UUID_Service_str)
        
        //self.centralManager.scanForPeripherals(withServices: [UUID_180F], options: nil)
        
    }
    
    func stopScan() {
        print("stopScan")
        self.centralManager.stopScan()
    }
    
    // startScanからコピーしたので、上を修正したらここもなおす（か、関数にする）
    // 使われていないので、コメントアウト
    /*
    func restartScan() {
        print("restartScan")
        // 本当は、サービスのUUIDを指定するのが正しいはずだがうまく動かない
        self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        //let UUID = CBUUID(string: "73C98F4C-F74F-4918-9B0A-5EF4C6C021C6")
        //let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
        //self.centralManager.scanForPeripherals(withServices: [UUID,UUID_Read], options: nil)
    }
    */

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("centralManagerDidUpdateState is called. NOT implemented yet.")
        switch (central.state) {
        case .poweredOff:
            print("powered off")
        case .poweredOn:
            print("powered on")
            startScan()
        case .resetting:
            print("reset")
        case .unauthorized:
            print("unauthorized")
        case .unknown:
            print("unknown")
        case .unsupported:
            print("unsupported")
        default:
            print("other")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        print("=== didDiscover ===")
        print("peripheral: \(peripheral)")
        print("name: \(peripheral.name ?? "nil")")
        print("identifier: \(peripheral.identifier.uuidString)")
        print("advertisementData keys: \(advertisementData.keys)")

        if let serviceData =
            advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            print("ServiceData dict:")
            for (uuid, data) in serviceData {
                let hex = data.map { String(format: "%02X", $0) }.joined()
                print("  \(uuid.uuidString): \(hex)")
            }
        } else {
            print("ServiceData: nil")
        }
        let shortServiceUUID = CBUUID(string: "8F4C")  // 73C98F4C... の下位16bit

        if let serviceData =
            advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let devIdData = serviceData[shortServiceUUID] {

            print("devIdData bytes = \(devIdData as NSData)")
            // ここで Android 側で入れた devIdBytes を復元する
        } else {
            print("ServiceData for 8F4C not found")
        }
        let shortServiceUUID2 = CBUUID(string: "73C98F4C")  // 73C98F4C... の下位32bit

        if let serviceData =
            advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let devIdData = serviceData[shortServiceUUID2] {

            print("devIdData bytes = \(devIdData as NSData)")
            // ここで Android 側で入れた devIdBytes を復元する
        } else {
            print("ServiceData for 73C98F4C not found")
        }

        // stop後の処理は無視する
        if self.state == BLECentralState.stop {
            Task { @MainActor in
                self.log.addItem(logText: "Central didDiscover while stop state")
            }
            return
        }
        
        //print("didDiscover peripheral. NOT implemented yet.")
        print("didDiscoverPeripheral\n")
        print("name: \(String(describing: peripheral.name))\n")
        print("UUID: \(peripheral.identifier.uuidString)")
        print("advertisementData: \(advertisementData)")
        print("kCBAdvDataLocalName:",advertisementData["kCBAdvDataLocalName"] ?? "unknown")
        print("CBAdvertisementDataTxPowerLevelKey:",advertisementData["CBAdvertisementDataTxPowerLevelKey"] ?? "unknown")
        let TxLevel = advertisementData["CBAdvertisementDataTxPowerLevelKey"] ?? "unknown"
        //let TxLevel2 = advertisementData["kCBAdvDataTxPowerLevelKey"] // これは駄目
        let isConnectable = advertisementData["kCBAdvDataIsConnectable"] // Documentと違うがこれでうまくいく
        print("peripheral.services:",peripheral.services ?? "unknown")
        //print("RSSI: \(RSSI)")
        //self.message.addItem(messageText: "didDiscover peripheral is called")
        Task { @MainActor in
            self.log.addItem(logText: "didDiscoverPeripheral, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(RSSI), \(TxLevel), \(isConnectable)")
        }
        
        // devices に追加。uuidがあるかどうかは、addDeviceの中でチェック
        self.devices.addDevice(peripheral: peripheral,tmprssi: RSSI)

        // 以下のロジックが本当に必要なのか確認要
        // stateの確認
        switch (peripheral.state) {
        case CBPeripheralState.connected:
            Task { @MainActor in
                
                self.log.addItem(logText: "CBPeripheral.state(connected),\(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
            }
        case CBPeripheralState.connecting:
            Task { @MainActor in
                
                self.log.addItem(logText: "CBPeripheral.state(connecting),\(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
            }
        case CBPeripheralState.disconnected:
            Task { @MainActor in
                
                self.log.addItem(logText: "CBPeripheral.state(disconnected),\(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
            }
        case CBPeripheralState.disconnecting:
            Task { @MainActor in
                
                self.log.addItem(logText: "CBPeripheral.state(disconnecting),\(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
            }
        @unknown default:
            Task { @MainActor in
                
                self.log.addItem(logText: "CBPeripheral.state(unknown),\(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
            }
        }
        if peripheral.state != CBPeripheralState.disconnected {
            // disconnected でなくても、didDiscover は呼ばれる。もしかしたら、設定で変えられるかもしれない。
            // すでに connect されているデバイスなので、何もしない。
            print("this peripheral is not disconnected")
            return
        } else {
            //print("this peripheral is disconnected")
        }
        
        let LocalName = advertisementData["kCBAdvDataLocalName"] ?? "unknown"
        Task { @MainActor in
            
            self.log.addItem(logText: "kCBAdvDataLocalName, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(LocalName),")
        }
        
        // すべてのデバイスをコネクトに行く
        // debug のために、一旦 BLECommTest0 に制限する。 2021/12/14
        // 戻す 2021/12/15
        
        if LocalName as! String  == "BLEcommTest0" {
            print("I got BLEcommTest0 (** for debug ***)")
            Task { @MainActor in
                
                self.log.addItem(logText: "Found BLEcommTest0, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)" )
            }
        }
        
        if true {
            print("LocalName:",LocalName)
        
            // BLEtest2のロジックを、コメントも含めてそのままコピペ
            /*
            let index = self.peripheralArray.indexOf { (p: CBPeripheral) -> Bool in
                p.identifier.UUIDString == peripheral.identifier.UUIDString
            }
            */
            /*
            let index = self.peripheralInfoArray.firstIndex { (p: PeripheralInfo) -> Bool in
                p.peripheral.identifier.uuidString == peripheral.identifier.uuidString
            }
             */
            let logicalId = makeLogicalId(peripheral: peripheral,
                                          advertisementData: advertisementData)

            let index = self.peripheralInfoArray.firstIndex { (p: PeripheralInfo) -> Bool in
                p.logicalId == logicalId      // ★ uuidString ではなく logicalId で比較。iPhoneはUUIDのまま
            }
            // UUIDは同じだけど、peripheralは違うという事はないのか？
            if index != nil {
                peripheralInfoArray[index!].peripheral = peripheral
            }
            print("index: \(index ?? -1)")

            // uuid が見つからなかった場合
            if index == nil {
                print("index is nil ???")
                let currentDate = Date()
                let peripheralInfo = PeripheralInfo(peripheral: peripheral, rssi: RSSI,     username: peripheral.name ?? "unknown", firstDate: currentDate, lastDate: currentDate, logicalId: logicalId)
                self.peripheralInfoArray.append(peripheralInfo)
                self.peripheralInfoArray.append(peripheralInfo as PeripheralInfo)
                //self.tableView.reloadData()
                print("new peripheralInfo.firstDate    \(peripheralInfo.firstDate)")
                print("new peripheralInfo.lastDate    \(peripheralInfo.lastDate)")
            }
            // uuidが見つかった場合
            if index != nil {
                let currentDate = Date()
                peripheralInfoArray[index!].lastDate = currentDate
                print("peripheral \(peripheral)")
                print("peripheralInfoArray[index].peripheral    \(peripheralInfoArray[index!].peripheral)")
                print("these values must be the same")
               
                print("peripheralInfoArray[index].firstDate    \(peripheralInfoArray[index!].firstDate)")
                print("peripheralInfoArray[index].lastDate    \(peripheralInfoArray[index!].lastDate)")
            }

            
            
            // 3-1. 指定したPeripheralへ接続開始
            // 本当は、コネクションが貼られていない時だけ接続処理に行くべき。後で要修正
            
            
            // 本当は複数のペリフェラルから、最適なペリフェラルを選択すべきだが、
            // とりあえず最初に見つかったペリフェラルから接続しに行く
            // 複数台の時に動きがおかしくなる（はず）なので、１台のみにする
            // 複数台接続の記事
            // https://qiita.com/hirotakan/items/569b4d63c95a3491b677
            // 厳密には lock が要る（connect request して、戻ってくる前に次のデバイスへのconnectが出るかも）
            
            // ロジック見直し 2021/12/15
            /*
            if         connectedPeripheral == nil {
                // 設定でオンにしないと、コネクトに行かない
                if (ConnectMode==true) {
                    self.centralManager.connect(peripheral, options: nil)
                }
            } else {
                // このロジックだと、コネクトして良いのは１台だけになる。本当は複数可能
                // でも、情報は得られているのでとりあえずいじらない。
                print("some one else is already connected. Don't connect")
                print(connectedPeripheral as Any)
                switch connectedPeripheral.state {
                case CBPeripheralState.disconnected:
                    print("disconnected")
                    // とりあえず、この場合は connect に行ってみる
                    // 設定でオンにしないと、コネクトに行かない
                    if (ConnectMode==true) {
                        self.centralManager.connect(peripheral, options: nil)
                    }

                case CBPeripheralState.connecting:
                    print("connecting")
                case CBPeripheralState.connected:
                    print("connected")
                case CBPeripheralState.disconnecting:
                    print("disconnecting")
                default:
                    print("unknown")
                }
            }
            */
            var doconnect = false
            switch peripheral.state {
            case CBPeripheralState.disconnected:
                Task { @MainActor in
                    
                    self.log.addItem(logText: "CBPeripheralState.disconnected, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
                }
                print("disconnected")
                doconnect = true
            case CBPeripheralState.connecting:
                Task { @MainActor in
                    
                    self.log.addItem(logText: "CBPeripheralState.connecting, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
                }
                print("connecting")
            case CBPeripheralState.connected:
                Task { @MainActor in
                    
                    self.log.addItem(logText: "CBPeripheralState.connected, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
                }
                print("connected")
                doconnect = true // connectされていてもservicesが読めない時があるらしいので、そのときのために connect する。2025/5/2
            case CBPeripheralState.disconnecting:
                Task { @MainActor in
                    
                    self.log.addItem(logText: "CBPeripheralState.disconnecting, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
                }
                print("disconnecting")
                doconnect = true
            default:
                Task { @MainActor in
                    
                    self.log.addItem(logText: "CBPeripheralState is unknown, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
                }
                print("unknown")
                doconnect = true // OK?
            }
            if doconnect {
                // 設定でオンにしないと、コネクトに行かない
                if (ConnectMode==true) {
                    // connect に行く条件
                    // chat の相手
                    // または
                    // （name が unknown <- BLECommTest0が分からない時があるのでこの条件を外す
                    // かつ、connectable）
                    
                    var rssi = Int(truncating: RSSI)
                    if rssi == 128 {
                        rssi = -127
                    }
                    
                    if (LocalName as! String  == "BLEcommTest0") ||
                       (/* peripheral.name == nil && */ rssi > RSSI3mth && isConnectable as! Int == 1)
                    || (index != nil){ // index != nil なら過去に接続したデバイスなので続ける
                        switch connect_semaphore.wait(timeout: .now()) {
                        case .success:
                            // 時間内に結果が帰ってきた時
                            print(peripheral.name)
                            self.centralManager.connect(peripheral, options: nil)
                            // logに残す 2021/12/18
                            Task { @MainActor in
                                
                                self.log.addItem(logText: "requestConnect, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(LocalName),")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // connect 失敗がわからないので、タイムアウトにした。
                                self.connect_semaphore.signal()
                                self.log.addItem(logText: "signalSemaphore, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(LocalName),")

                            }
                        case .timedOut:
                            // 時間切れの時
                            Task { @MainActor in
                                
                                self.log.addItem(logText: "FailConnectSemaphore, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(LocalName),")
                            }
                        }
                    }
                }
            }
        }
    }
    
   
    // 3-2. Peripheralへの接続結果の受信(成功時)
    public func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral)
    {
        // 複数台の時に lock 処理が必要
        let pname = peripheral.name ?? "unknown"
        print("C: connection success for \(pname)")
        print("UUID: \(peripheral.identifier.uuidString)")
        Task { @MainActor in
            
            self.log.addItem(logText: "didConnect, \(pname), \(peripheral.identifier.uuidString),")
        }
        
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)
        // stop後の処理は無視する
        if self.state == BLECentralState.stop {
            Task { @MainActor in
                
                self.log.addItem(logText: "Central didConnect while stop state") // これはエラーではなくて、タイミングの話
            }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        // デリゲートの設定
        peripheral.delegate = self
        
        // 覚えておく 2021/2/6 T.Ogino
        // 上位の関数が、peripheralを使えるように（writeが呼べるように）
        // 複数台とコネクトすると、上書きになってしまう。要確認。
        // peripheral 毎なので大丈夫な気がする
        //connectedPeripheral = peripheral
        // 4-1. 利用可能Serviceの探索開始
        //let UUID_Service = BLEcommService.UUID_Service
        print("call discoverServices with nil")
        
        //let UUID_180A = CBUUID(string: "180A")
        let UUID_str = CBUUID(string: UUID_Service_str)
        peripheral.discoverServices([UUID_str])
        //peripheral.discoverServices([UUID_180A,UUID_str])
        //peripheral.discoverServices(nil)
        
        // RSSI が読めるか確認
        peripheral.readRSSI()

    }
    // 3-2. Peripheralへの接続結果の受信(失敗時)
    public func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                                                   error: Error?)
    {
        print("connection failed")
        let pname = peripheral.name ?? "unknown"
        Task { @MainActor in
            
            self.log.addItem(logText: "didFailToConnect, \(pname), \(peripheral.identifier.uuidString),")
        }
        //connect_semaphore.signal()
        // 呼ばれないような感じ
        
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)

    }
    
    // disconnectの検出（できるのか？）
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("didDisconnectPeripheral is called") // ペリフェラルが切れると呼ばれる。確認済。
        let uuid = peripheral.identifier.uuidString
        let name = peripheral.name ?? "unknown"
        Task { @MainActor in
            
            self.log.addItem(logText: "didDisconnectPeripheral,\(name), \(uuid),")
        }
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)
        //connect_semaphore.signal()
        // connect のところで、遅延実行にした。

        // 処理全体をリセットしたいが、転送中のTransferCとかはどうするのか？
        // connectedPeripheral = nil
        
        print("transferList \(transferCList)")
        print("disconnected peripheral \(peripheral)")
        for transfer in transferCList {
            if transfer.connectedPeripheral.identifier.uuidString == peripheral.identifier.uuidString {
                print("I found the disconnected transfer")
                transfer.valid = false // リストを消したほうが良いか？
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        print("connectionEventDidOccur")
        
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)

    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        print("didReadRSSI")
        if (error != nil) {
            print("error: \(String(describing: error))")
            return
        }
        print("RSSI=\(RSSI)")
        let devicename = peripheral.name ?? "unknown"
        let deviceUUID = peripheral.identifier.uuidString
        Task { @MainActor in
            
            self.log.addItem(logText:"didReadRSSI, \(devicename), \(deviceUUID), \(RSSI)")
        }
        
        // devices の更新。
        self.devices.updateDevicewithRSSI(peripheral: peripheral, rssi: RSSI)

    }
    
    // 4-2. Service探索結果の受信
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("didDiscoverServices")
        Task { @MainActor in
            
            self.log.addItem(logText: "didDiscoverServices, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString)")
        }
        if (error != nil) {
            print("error in didDiscoverServices: \(String(describing: error))")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // stop後の処理は無視する
        if self.state == BLECentralState.stop {
            Task { @MainActor in
                
                self.log.addItem(logText: "Central didDiscoverServices while stop state")
            }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        print("C: search service for ",peripheral.name ?? "unknown")
        
        if (peripheral.services == nil) {
            print("error: periphera.services is nil")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        print("Found \(peripheral.services!.count) services! : \(String(describing: peripheral.services))")

        
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)

        var cancancel = true // このあとの処理が不要なデバイスならキャンセルできるようにする
        for service in peripheral.services!
        {
            print("C: find service")
            print("C: \(service)")
            
            let devicename = peripheral.name ?? "unknown"
            let deviceUUID = peripheral.identifier.uuidString
            let serviceUUID0 = service.uuid
            let serviceUUID1 = service.uuid.uuidString
            
            Task { @MainActor in
                
                self.log.addItem(logText:"didDiscoverServices, \(devicename), \(deviceUUID), \(serviceUUID0), \(serviceUUID1)")
            }

            
            self.serviceArray.append(service as CBService)
            
            // 5-1. 利用可能Characteristicの探索開始
            //#define kCharacteristicUUIDEncounterRead    @"1BE31CB9-9E07-4892-AA26-30E87ABE9F70"
            //#define kCharacteristicUUIDEncounterWrite   @"0C136FCC-3381-4F1E-9602-E2A3F8B70CEB"
            //let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
            //let UUID_Write = CBUUID(string: "0C136FCC-3381-4F1E-9602-E2A3F8B70CEB")

            if (serviceUUID1=="180A") { // こっちにはこないみたい
                print("C: call discoverCharacteristics for 180A")
                peripheral.discoverCharacteristics(nil, for:service as CBService)
                cancancel = false
            } else if (serviceUUID1 == UUID_Service_str) { // chat 用
                print("C: call discoverCharacteristics for UUID_Service")
                peripheral.discoverCharacteristics(nil, for:service as CBService)
                cancancel = false
            } else {
                print("Not call discover characteristics") // 呼んでも良いような気はする
            
                //peripheral.discoverCharacteristics([UUID_Read,UUID_Write], for:service as CBService)
                // peripheral.discoverCharacteristics(nil, forService:service as CBService)
                /* ↑の第1引数はnilは非推奨。*/
            }
        }
        
        // 一応ここでもRSSI確認
        peripheral.readRSSI()
        
        // NAMIの場合は、ここでdisconnectを出す
        // 上のreadRSSIが返ってこないかもしれない
        if cancancel {
            centralManager.cancelPeripheralConnection(peripheral)
        }

    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        let devicename = peripheral.name ?? "unknown"
        let deviceUUID = peripheral.identifier.uuidString
        let serviceUUID0 = service.uuid
        let serviceUUID1 = service.uuid.uuidString
        
        Task { @MainActor in
            
            self.log.addItem(logText:"didDiscoverCharacteristicsFor, \(devicename), \(deviceUUID), \(serviceUUID0), \(serviceUUID1)")
        }

        if let error = error {
            print("didDiscoverCharacteristeicsForService error: \(error)")
            Task { @MainActor in
                
                self.log.addItem(logText:"didDiscoverCharacteristicsForError, \(devicename), \(deviceUUID)")
            }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        if (service.characteristics == nil) {
            print("error: characteristics is nil")
            Task { @MainActor in
                
                self.log.addItem(logText:"didDiscoverCharacteristicsFor nil, \(devicename), \(deviceUUID)")
            }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // stop後の処理は無視する
        if self.state == BLECentralState.stop {
            Task { @MainActor in
                
                self.log.addItem(logText: "Central didDiscoverCharacteristicsFor while stop state")
            }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        


        let characteristics = service.characteristics!
        
        print("Found \(characteristics.count) characteristics! : \(characteristics)")
        /* 180Aの時
         Found 2 characteristics! : [<CBCharacteristic: 0x280054420, UUID = Manufacturer Name String, properties = 0x2, value = (null), notifying = NO>, <CBCharacteristic: 0x280054600, UUID = Model Number String, properties = 0x2, value = (null), notifying = NO>]
        */
        
        // devices の更新。
        self.devices.updateDevice(peripheral: peripheral)

        var cancancel = true // このあとの処理が不要なデバイスならキャンセルできるようにする
        for characteristic in characteristics
        {
            print("found characteristics.uuid = \(characteristic.uuid)")
            if characteristic.uuid == UUID_Read {
                print("find UUID_Read and read value")
                Task { @MainActor in
                    
                    self.log.addItem(logText:"find UUID_Read and read value, \(devicename), \(deviceUUID)")
                }
                // 値を読む
                print("don't read for debug")
                //peripheral.readValue(for: characteristic)
                //foundCharacteristicR = characteristic // save
            }
            
            if characteristic.uuid == UUID_Write {
                print("find UUID_Write and write value")
                Task { @MainActor in
                    
                    self.log.addItem(logText:"find UUID_Write and write value, \(devicename), \(deviceUUID)")
                }

                //let data = "BLEcommTest0".data(using: String.Encoding.utf8, allowLossyConversion:true)
                //peripheral.writeValue(data!, for: characteristic, type: CBCharacteristicWriteType.withResponse)
                
                print("don't write for debug")
                //writeData("debugWrite", peripheral: peripheral)
                
                // とりあえずUUID_Writeが見つかったら、メッセージのTransferを開始する。
                print(peripheral.name!)
                //print(connectedPeripheral)
                
                // MTUの確認
                let MTU = peripheral.maximumWriteValueLength(for: .withoutResponse)
                print(MTU)
                
                if self.userMessage != nil {
                    // connectedPeripheralではなく、peripheralを渡す。2021/12/15
                    //self.userMessage.startTransfer(connectedPeripheral: self.connectedPeripheral)
                    Task { @MainActor in
                        
                        self.log.addItem(logText:"before call startTransfer, \(devicename), \(deviceUUID)")
                    }
                        self.userMessage.startTransfer(connectedPeripheral: peripheral)
                    Task { @MainActor in

                        self.log.addItem(logText:"after call startTransfer, \(devicename), \(deviceUUID)")
                    }

                    cancancel = false
                } else {
                    Task { @MainActor in
                        
                        self.log.addItem(logText:"userMessage is nil, \(devicename), \(deviceUUID)")
                    }

                }
            }
            
            // ★ DEVICE_ID を読む
            if characteristic.uuid == BLEcommService.UUID_DeviceId {
                print("find UUID_DeviceId → read value")

                peripheral.readValue(for: characteristic)
            }
            
            let UUID_Manu = CBUUID(string: "0x2a29") // Manufacturer Name String
            if characteristic.uuid == UUID_Manu {
                print("UUID_Manu")
                peripheral.readValue(for: characteristic)
                //foundCharacteristicR = characteristic // save

            }
            
            let UUID_Model = CBUUID(string: "0x2a24") //Model Number String
            if characteristic.uuid == UUID_Model {
                print("UUID_Model")
                peripheral.readValue(for: characteristic)
                //foundCharacteristicR = characteristic // save
            }

        }
        
        // 一応ここでもRSSI確認
        peripheral.readRSSI()
        
        // 上のreadRSSIが返ってこないかもしれない
        // startTransfer していなければキャンセルしても良いはず
        if cancancel {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // 同じ処理が 321行目付近にあるので、こちらはコメントアウトする 2021/12/13
    /*
    public func peripheral(_ peripheral: CBPeripheral, didDisconnectedPeripheral service: CBService, error: Error?) {
        // とりあえず呼ばれるかどうか確認する -> 呼ばれない -> 終了処理は、Message.swift 側でやる
        // これ以外の処理が必要だけど、まだやっていない。落ちるかもしれない。
        print("didDisconnectedPeripheral is called")
        let devname = peripheral.name
        let devUUID = peripheral.identifier.uuidString
        self.log.addItem(logText: "didDisconnectedPeripheral,\(devname ?? "unknown"), \(devUUID)")
    }
    */

    // writeDataのロジックを参考に書き換える 2021/12/15
    public func readfromP(peripheral: CBPeripheral)->Bool {
        print("enter readfromP")
        //peripheral.readValue(for: foundCharacteristicR)
        
        // ここからが書き換えた後
        if (peripheral.services == nil) {
            print("error: peripheral.services is nil (reeadfromP)")
            return false
        }
        // 他にもエラーがあると思うが、それは発見してから修正する。

        print(peripheral.services ?? "no service")
        
        for service in peripheral.services! {
            if service.uuid == UUID_Service {
                print("find UUID_Service (reeadfromP)")
                if (service.characteristics == nil) {
                    print("error: service.characteristics is nil (reeadfromP)")
                    return false
                }

                for characteristic in service.characteristics! {
                     if characteristic.uuid == UUID_Read {
                        print("find UUID_Read  (reeadfromP)")
                        peripheral.readValue(for: characteristic)
                        return true
                     }
                }
                print("error: characteristic UUID_Read is not found (reeadfromP)")

            }
        }
        print("error: service UUID_Service is not found (reeadfromP)")
        
        return false
    }
    
    // 値を読みに行った結果の到着
    public func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                                                    error: Error?)
    {
        if let error = error {
            print("Failed... error: \(error)")
            return
        }
        
        if (characteristic.value == nil) {
            print("error: characteristic.value is nil")
            return
        }
        let characteristicvalue: Data = characteristic.value!
        print("Succeeded! service uuid: \(String(describing: characteristic.service?.uuid)), characteristic uuid: \(characteristic.uuid), value: \(characteristicvalue)")
        let newStr = String(describing: characteristic.value!)
        print("newStr \(newStr)")

        
        if characteristic.uuid == UUID_Read {
            print("UUID_Read value \(newStr)")
        
            var transferMessage: NSString
        
            if let tmpMessage = NSString(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue) as String? {
                
                transferMessage = tmpMessage as NSString
            } else {
                //print("not a valid UTF-8 sequence")
                transferMessage = "MESSAGEERROR\n"
            }
            
            //print(transferMessage)
            //print("length \(username.length)")
            Task { @MainActor in
                
                self.log.addItem(logText:"didUpdateValueFor \(transferMessage)")
                self.log.addItem(logText:"length \(transferMessage.length)")
            }

            // message に追加
            //self.message.addItem(messageText: transferMessage as String)

            // transfer の message に追加して、読めるようにする
            print("transferList \(transferCList)")
            for transfer in transferCList {
                if transfer.connectedPeripheral.identifier.uuidString == peripheral.identifier.uuidString {
                    print("I found the transfer")
                    transfer.appendMessage(protocolMessage: transferMessage as String)
                    print("after append \(transfer.protocolMessageQueue)")
                }
            }

            
            //http://harumi.sakura.ne.jp/wordpress/2018/11/08/corebluetooth-received-notification/
            // notifyを受けるようにする。どこかで戻すのか？
            //peripheral.setNotifyValue(true, for: characteristic) // characteritic が違う
            //print("setNotify")
            
            // データを書き込む
            //1byteずつの配列に分割して指定する(任意のバイト文字列)
            //let byteArray: [UInt8] = [ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
            //let data = Data(_: byteArray)
            //書き込み
            //peripheral.writeValue(data , for: characteristic, type: .withResponse)
            //writeData("abcdefg", peripheral: peripheral)
        }
        
        // ★ DeviceId の読み取り
        if characteristic.uuid == BLEcommService.UUID_DeviceId {
            // 1. Data? を安全に unwrap
            guard let devData = characteristic.value else {
                print("DEVICE_ID: value is nil")
                return
            }

            // 2. Data → String(UTF-8) へ変換
            if let devIdStr = String(data: devData, encoding: .utf8) {
                print("DEVICE_ID from peripheral = \(devIdStr)")
                // ここで devIdStr を logicalId として使う処理を書く
            } else {
                print("DEVICE_ID decode error (not UTF-8)")
            }
            return    // 他の if には行かないようにするなら return してもよい
        }
        
        let UUID_Manu = CBUUID(string: "0x2a29") //
        if characteristic.uuid == UUID_Manu {
            var readMessage: String
        
            if let tmpMessage = NSString(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue) as String? {
                
                readMessage = tmpMessage as String
            } else {
                //print("not a valid UTF-8 sequence")
                readMessage = "MESSAGEERROR\n"
            }
            
            //print(readMessage)
            readMessage = readMessage.replacingOccurrences(of: "\0", with: "")
            readMessage = readMessage.replacingOccurrences(of: ",", with: ".")
            //print(readMessage)
            Task { @MainActor in
                
                self.log.addItem(logText: "didUpdateValueFor, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(characteristic.uuid), \(readMessage)")
            }
        }
        
        let UUID_Model = CBUUID(string: "0x2a24") //Model Number String
        if characteristic.uuid == UUID_Model {
            var readMessage: String
        
            if let tmpMessage = NSString(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue) as String? {
                
                readMessage = tmpMessage as String
            } else {
                //print("not a valid UTF-8 sequence")
                readMessage = "MESSAGEERROR\n"
            }
            
            //print(readMessage)
            readMessage = readMessage.replacingOccurrences(of: "\0", with: "")
            readMessage = readMessage.replacingOccurrences(of: ",", with: ".")
            //print(readMessage)
            Task { @MainActor in
                
                self.log.addItem(logText: "didUpdateValueFor, \(peripheral.name ?? "unknown"), \(peripheral.identifier.uuidString), \(characteristic.uuid), \(readMessage)")
            }
        }

        
    }
    /*
    public func writecurrent () {
        print("write current is called")
        if self.connectedPeripheral != nil {
            writeData("DEBUG\nwrite current", peripheral: self.connectedPeripheral)
        } else {
            print("debug connectedPeripheral is nil")
        }
    }
    */
    
    func writeData(_ data: String, peripheral: CBPeripheral) {
        print("enter writeData")
        print("data \(data)")
        
        if (peripheral.services == nil) {
            print("error: peripheral.services is nil")
            return
        }

        print(peripheral.services ?? "no service")
        
        for service in peripheral.services! {
            if service.uuid == UUID_Service {
                print("find UUID_Service")
                if (service.characteristics == nil) {
                    print("error: service.characteristics is nil")
                    return
                }

                for characteristic in service.characteristics! {
                     if characteristic.uuid == UUID_Write {
                        print("find UUID_Write and write value")
                        // notifyを受けるようにする。どこかで戻すのか？
                        peripheral.setNotifyValue(true, for: characteristic)
                        print("setNotify")
                        
                        //let udata = "hello".data(using: String.Encoding.utf8.rawValue, allowLossyConversion:true)
                        //1byteずつの配列に分割して指定する(任意のバイト文字列)
                        //let byteArray: [UInt8] = [ 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
                        //let udata = Data(_: byteArray)
                        //print(udata)
                        let udata = data.data(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue), allowLossyConversion:true)
                         if (udata == nil) {
                             print("error: udata is nil")
                             return
                         }
                        peripheral.writeValue(udata!, for: characteristic, type: CBCharacteristicWriteType.withResponse)
                     }
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("Write失敗...error: \(error)")
            return
        }
        
        if characteristic.uuid == UUID_Write {
            //valueの中にData型で値が入っています。->入っていない。why?
            //peripheral.readValue(for: characteristic)
            print(characteristic)
            print(characteristic.value ?? "some error")
            print("更新通知を取得しました！")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        if let error = error {
            print("didUpdateValue fail...error: \(error)")
            return
        }
        print("didUpdateValue is called")
    }
    
    // 相手が切れたとき（？）に呼ばれる
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("didModifyServices called")
    
    }
    
    // 性能標柱に見つかった不具合対応でまず動作確認
    func peripheralManager(_ peripheral: CBPeripheral,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        print("didSubscribeTo called")
        Task { @MainActor in
            self.log.addItem(logText: "didSubscribeTo called")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheral,
                           central: CBCentral,
                           didUnSubscribeTo characteristic: CBCharacteristic) {
        print("didUnSubscribeTo called")
        Task { @MainActor in
            self.log.addItem(logText: "didUnSubscribeTo called")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheral,
                           central: CBCentral,
                           didDisconnectPeripheral error: Error?) {
        print("didDisconnecPeripheral called")
        Task { @MainActor in
            self.log.addItem(logText: "didDisconnected called")
        }
    }

    
    // この処理はいらないのではないか？
    // 同じデバイスもscanで見つかっているように見える
    // peripheralとcentralを切り替える時はいるかもしれない
    
    public func timerFunc() {
        print("BLECentral.timerFunc is called")
        Task { @MainActor in
            
            self.log.addItem(logText: "BLECentral.timerFunc,")
        }
        
        // 以下は、BLE Chat と同じに修正
        // 使っていない -> 下で使っている
        let obsoleteInterval = Int(UserDefaults.standard.object(forKey: "obsoleteInterval") as? String ?? "600")
/*
        print("do nothing in BLECentral.timerFunc for **debug**")
        Task { @MainActor in
            
            self.log.addItem(logText: "do nothing in BLECentral.timerFunc for **debug**")
        }
*/
        // scanでPが見つからないので、一旦ここで再起動してみる。
        print("stop and start Scan in BLECentral.timerFunc")
        self.stopScan()
        self.startScan()
        
        /*
        
        self.stopScan()
        
        for peripheral in peripheralInfoArray {
            centralManager.cancelPeripheralConnection(peripheral.peripheral)
            // connect されていない peripheral も呼ばれる。status を見れば避けれるかもしれない
        }
        peripheralInfoArray = [PeripheralInfo]()
        */
        // これをしないと、カウントがアップデートされない 2021/12/15
        // ハングするので、一旦コメントアウト
        self.devices.clearObsoleteDevice(period: obsoleteInterval! as NSNumber)
        
        /*
        self.centralManager = CBCentralManager.init(delegate: self, queue: nil)
        
        // 他で central manager を使っていると、値が変わってしまうのでおかしくなる可能性がある。
        self.startScan()
        */
    }
    
    // android の UUID が同じにならないための改修 2025/12/14
    // BLE.swift 内のどこか（BLECentral のメソッドとしてでOK）

    func makeLogicalId(peripheral: CBPeripheral,
                       advertisementData: [String: Any]) -> String {
        // 1. Service Data に Android の deviceId が入っていればそれを logicalId とする
        if let serviceDataDict =
            advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceDataDict[BLEcommService.UUID_Service],
           !data.isEmpty {

            // 8バイトでも16バイトでも、全部 hex 文字列にする
            let hex = data.map { String(format: "%02X", $0) }.joined()
            print("hex is \(hex)")
            return hex
        }

        // 2. それ以外（iPhoneなど）は従来通り identifier.uuidString を使う
        print("uuidString=\(peripheral.identifier.uuidString)d")
        return peripheral.identifier.uuidString
    }

}

public class BLEPeripheral: NSObject, CBPeripheralManagerDelegate, ObservableObject {
    var peripheralManager: CBPeripheralManager!
    var peripheralMode: Bool = false
    var log : Log!
    var userMessage: UserMessage!
    
    override init() {
        super.init()
        
        
        // スリープして再起動した時に見つける
        // 本当は Peripheral 側にも入れるべき
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(PeripheralappDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(PeripheralappWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        
    }
    
    @objc func PeripheralappDidBecomeActive() {
        print("Peripheral App became active")
        PeripheralreconnectBLE()
    }

    @objc func PeripheralappWillEnterForeground() {
        print("Peripheral App will enter foreground")
    }

    func PeripheralreconnectBLE() {
        print("Peripheral reconnect BLE is not implemented yet")
        // 再接続処理

    }
    
    
    public func myinit(userMessage: UserMessage) {
        print("BLEPeripheral myinit is called")
        self.userMessage = userMessage
        //self.userMessage.addItem(userMessageText: "BLEPeripheral myinit is called")
        //self.log.addItem(logText: "BLEPeripheral myinit is called")
        // まだ log を知らないので書けない
    }
    
    func startPeripheralManager(log: Log, userMessage: UserMessage) {
        startPeripheral(log: log, userMessage: userMessage)
    }
        
    func startPeripheral(log: Log, userMessage: UserMessage) {

        self.log = log
        Task { @MainActor in
            
            self.log.addItem(logText:"startPeripheralManager")
        }
        self.userMessage = userMessage
        
        self.userMessage.PmessageLoopLock.unlock()
        
        if self.peripheralManager == nil {
            print("peripheralManger is nil")
            self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            // 取り敢えずアドバタイズ開始
            if (peripheralMode) {
                startAdvertise()
            }
        }
        
        // 取り敢えずアドバタイズ開始 2021/12/28 stop が出ているのに、 start が１回しか出ないので、試しに出してみる。
        //if (peripheralMode) {
        if (true) { // for debug 2025/5/15 // 戻しても良いような気もするが、２回読んでも大丈夫みたいなのでそのままにしておく。
            publishservice() // add serviceが成功するとその中で startAdvertise() が呼ばれる
            //startAdvertise()
        }
        
        print("Peripheral Manager State: \(self.peripheralManager.state)")

    }
    // stop ボタンを押した時に、Peripheralがオンだったら呼ばれる
    func stopPeripheralManager(log: Log) {
        Task { @MainActor in
            
            self.log.addItem(logText:"stopPeripheralManager")
        }
        //print("stopPeripheralManager called. Not implemented yet.")
        // stop advertise
        //stopAdvertise()
        stopPeripheral(log: log)
        
       
    }
    
    func stopPeripheral(log: Log) {
        self.log = log
        Task { @MainActor in
            
            self.log.addItem(logText:"stopPeripheral")
        }

        // stop advertise
        stopAdvertise()
        
        //self.userMessage.PmessageLoopLock.lock() // lockが取れたなら、transferP は nil になっている
        if self.userMessage.PmessageLoopLock.lock(before: Date().addingTimeInterval(3))==false { // 60->3 に減らす 2026/4/6
            Task { @MainActor in
                
                self.log.addItem(logText: "lock in stop Peripheral failed.")
            }
        }
    }

    // この辺は、BLETest2 からコピー
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("peripheralManagerDidUpdateState is called")
        Task { @MainActor in
            
            self.log.addItem(logText:"peripheralManagerDidUpdateState")
        }
        
        switch peripheral.state {
            
            case .poweredOn:
                print("peripheral powerOn")
                // サービス登録開始
                publishservice()
                break
            
        default:
            break
        }
    }
    
    // BLETest2と同じ値（で良いのか？どうやって作ったか忘れた）
    //let UUID = CBUUID(string: "73C98F4C-F74F-4918-9B0A-5EF4C6C021C6")
    //let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
    let UUID_Service = BLEcommService.UUID_Service
    let UUID_Read = BLEcommService.UUID_Read
    let UUID_Write = BLEcommService.UUID_Write
    // ★ 追加
    let UUID_DeviceId = BLEcommService.UUID_DeviceId
    
    func publishservice() {
        
        // サービスを作成
        let service = CBMutableService(type: UUID_Service, primary: true)
        
        // キャラクタリスティックを作成
        let propertiesR: CBCharacteristicProperties = [.notify, .read]
        let propertiesW: CBCharacteristicProperties = [.notify, .write]
        let permissionsR: CBAttributePermissions = [.readable]
        let permissionsW: CBAttributePermissions = [.writeable]
        let characteristicR = CBMutableCharacteristic(type: UUID_Read, properties: propertiesR,
                                                      value: nil, permissions: permissionsR)
        let characteristicW = CBMutableCharacteristic(type: UUID_Write, properties: propertiesW,
                                                      value: nil, permissions: permissionsW)

        // ★ 追加: DeviceId を返すための Read-only characteristic
        let characteristicDeviceId = CBMutableCharacteristic(
            type: UUID_DeviceId,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        
        // sample code
//        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
//                                                         properties: [.notify, .writeWithoutResponse],
//                                                         value: nil,
//                                                         permissions: [.readable, .writeable])
        // キャラクタリスティックをサービスにセット
        //service.characteristics = [characteristicR,characteristicW]
        // キャラクタリスティックをサービスにセット
        service.characteristics = [characteristicR, characteristicW, characteristicDeviceId]
        
        // サービスを Peripheral Manager にセット
        self.peripheralManager.add(service)

    }
    
        // ★ 追加: iPhone 用の deviceId を永続化
    private func getDeviceId() -> String {
            let key = "BLE_DeviceId"
            if let existing = UserDefaults.standard.string(forKey: key) {
                return existing
            }
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            return newId
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        print("enter periperalManager:didAddService")
        
        if let error = error {
            print("サービス追加失敗！ error: \(error)")
            return
        }
        
        print("サービス追加成功！")
        print(peripheralMode)
        // 取り敢えずアドバタイズ開始
        if (peripheralMode) {
            startAdvertise()
        }
        
    }
    
    func startAdvertise() {
        print("enter startAdvertising")
        Task { @MainActor in
            
            self.log.addItem(logText:"startAdvertise")
        }


        //let advertisementData = [CBAdvertisementDataLocalNameKey: "BLEcommTest0"]
        // only NAMI test
        // 2025/5/1 ZenSample との差異を探した時に、アドバタイズの方法が違っている
        // これまではNAMIは上のやり方だったけど、下で確認してみる。（戻さないといけないかも）
        // NGだったので戻す. ロジックを見ると、どこでも使っていないので、使わない方にする
        //let advertisementData = [CBAdvertisementDataLocalNameKey: "BLEcommTest0",
        //                      CBAdvertisementDataServiceUUIDsKey: BLEcommService.UUID_Service] as [String : Any]
//        let advertisementData = [CBAdvertisementDataServiceUUIDsKey: BLEcommService.UUID_Service]
        let advertisementData = [CBAdvertisementDataServiceUUIDsKey: [BLEcommService.UUID_Service]] // ZenSampleの書き方 これが正しい方法らしい
        if (peripheralMode) {
            Task { @MainActor in
                
                self.log.addItem(logText:"startAdvertising")
            }
            // publishservice() // 2026/3/31 追加 // ここで呼ぶとループになる
            peripheralManager.startAdvertising(advertisementData);
        }
    }
    
    func stopAdvertise() {
        print("enter stopAdvertising")
        Task { @MainActor in
            
            self.log.addItem(logText:"stopAdvertise")
        }


        if (peripheralMode) {
            peripheralManager.stopAdvertising();
            peripheralManager.removeAllServices() // 2026.3.31 追加
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("enter didReceiveReadRequest \(request.characteristic.uuid)")
        Task { @MainActor in
            
            self.log.addItem(logText:"didReceiveReadRequest")
        }

        // Peripheral側のCBCentralオブジェクトでMTUを確認する
        
        print("Received read request: MTU=\(request.central.maximumUpdateValueLength)");
        
        //let myname = UserDefaults.standard.string(forKey: "myID")
        // ★ 1) まず DEVICE_ID 用の read を処理
        if request.characteristic.uuid.isEqual(UUID_DeviceId) {
                let devId = getDeviceId()
                print("DEVICE_ID read requested, devId = \(devId)")
                Task { @MainActor in
                
                    self.log.addItem(logText: "didReceiveReadRequest DEVICE_ID \(devId)")
                }

                request.value = devId.data(using: .utf8, allowLossyConversion: true)

                // 同期でそのまま返して問題ありません
                self.peripheralManager.respond(to: request, withResult: .success)
                return
        }
        
        if request.characteristic.uuid.isEqual(UUID_Read) {
            //let queue = DispatchQueue.global(qos:.default)
            let queue = DispatchQueue.global(qos:.userInitiated)
            // Warningが出るので、QoSクラスを変えてみた。あっているかどうか不明 2024/5/30
            queue.async {
                //let wmsg: String = "\(myname)" as String
                var wmsg: String
                if transferP != nil {
                    wmsg = (transferP?.getProtocolMessageP())! // ここでブロックしてしまう
                } else {
                    wmsg = "transferP nil error"
                    print("transferP nil error")
                    
                    //self.log.addItem(logText:"transferP nil error")
                    // error の時に response を返すのが正しいのか不明
                    // C 側は、エラーになったら reset の処理に行くようになっている
                }
                print("wmsg = \(wmsg)")
                request.value = wmsg.data(using: String.Encoding.utf8, allowLossyConversion:true)!
            
                // リクエストに応答
                self.peripheralManager.respond(to: request, withResult: .success)
                Task { @MainActor in
                    self.log.addItem(logText:"peripheralManager.respond")
                }
                
                if transferP != nil {
                    // https://qiita.com/MTattin/items/3f7842ef2695bbbbca3e
                    let userInitiatedQueue = DispatchQueue(label: "userInitiated_queue", qos: .userInitiated)
                    userInitiatedQueue.async {
                        // wait側で実行時のwarningが出るので、デバッグする 2024/5/31
                        print("QoS debug (signal) ", Thread.isMainThread, Thread.current, Thread.current.qualityOfService.rawValue)
                        let debugtxt = "QoS debug (signal) : QoS is " +  String(Thread.current.qualityOfService.rawValue)
                        Task { @MainActor in
                            self.log.addItem(logText:debugtxt)
                        }
                        if Thread.current.qualityOfService.rawValue != 25 {
                            print("QoS is NOT user initiated at signal")
                        }
                        transferP?.protocolMessageSyncSemaphore.signal()
                    }
                }
                
            }
        } else {
            print("unknown UUID")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("enter didReceiveWriteRequest \(requests[0].characteristic.uuid)")
        
        Task { @MainActor in
            
            self.log.addItem(logText:"didReceiveWriteRequest")
        }


        for request in requests {
            
            if request.characteristic.uuid.isEqual(UUID_Write) {
                let queue = DispatchQueue.global(qos:.default)
                
                //let queue = DispatchQueue.global(qos:.userInitiated)
                // Warningが出るので、QoSクラスを変えてみた。あっているかどうか不明 2024/5/30
                queue.async {
                    let requestvalue:Data = request.value!
                    print("write value \(requestvalue)")
                    //  文字列ではないと思われる
                    //var username: NSString
                
                    if let writedata = NSString(data: request.value!, encoding: String.Encoding.utf8.rawValue) as String? {
                        //print(writedata)
                        print("skip didReceiveWriterequest \(writedata)")
                        //self.log.addItem(logText:"didReceiveWriterequest \(writedata)")
                        // message に追加
                        //self.userMessage.addItem(userMessageText: writedata as String)
                    
                        //analyze messageText
                        self.userMessage.analyzeText(protocolMessageText: writedata)
                    }
                }
            }
        }
        // リクエストに応答
        peripheralManager.respond(to: requests[0], withResult: .success)
        
    }
    
    // 性能標柱に見つかった不具合対応でまず動作確認
    // これは notify の時しか呼ばれないのでは？
    public func peripheralManager(_ central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        print("didSubscribeTo called (BLEPeripheral)")
        Task { @MainActor in
            self.log.addItem(logText: "didSubscribeTo called (BLEPeripheral)")
        }
    }

    public func peripheralManager(_ central: CBCentral,
                           didUnSubscribeTo characteristic: CBCharacteristic) {
        print("didUnSubscribeTo called (BLEPeripheral)")
        Task { @MainActor in
            self.log.addItem(logText: "didUnSubscribeTo called (BLEPeripheral)")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheral,
                           central: CBCentral,
                           didDisconnectPeripheral error: Error?) {
        print("didDisconnecPeripheral called")
        Task { @MainActor in
            self.log.addItem(logText: "didDisconnected called")
        }
    }

    // これは呼ばれないのではないか？
    /*
    func analyzeText(messageText: String) {
        let command:[String] = messageText.components(separatedBy:"\n")
        self.log.addItem(logText:"command \(command[0])")
        switch command[0] {
        case "BEGIN0":
            print("BEGIN0")
        case "DEBUG":
            self.log.addItem(logText:messageText)
        default:
            print("OTHER COMMAND")
        }
    }
    */
}
