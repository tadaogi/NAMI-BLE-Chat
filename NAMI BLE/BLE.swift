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
}

struct BLEcommService {
    static let UUID_Service = CBUUID(string: "73C98F4C-F74F-4918-9B0A-5EF4C6C021C6")
    static let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
    static let UUID_Write = CBUUID(string: "0C136FCC-3381-4F1E-9602-E2A3F8B70CEB")
}
// Centralとして動く時の処理はこちら

public class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    
    var centralManager: CBCentralManager!
    var peripheralInfoArray = [PeripheralInfo]()
    fileprivate var serviceArray = [CBService]()

    let UUID_Service = BLEcommService.UUID_Service
    let UUID_Read = BLEcommService.UUID_Read
    let UUID_Write = BLEcommService.UUID_Write

    //@EnvironmentObject var log : Log
    var log : Log!
    
    var userMessage: UserMessage!
    var connectedPeripheral: CBPeripheral! = nil
    var foundCharacteristicR: CBCharacteristic! = nil

    override init() {
        //self.centralManager = CBCentralManager()
        //self.peripheralManager = CBPeripheralManager()
        print("BLECentral init is called")
    }
    
    public func myinit(userMessage: UserMessage) {
        print("BLECentral myinit is called")
        self.userMessage = userMessage
        self.userMessage.addItem(userMessageText: "myinit is called") // shoud be log
    }
    
    func startCentralManager(log: Log) {
        self.log = log
        self.log.addItem(logText:"startCentralManager")
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
    }
    
    // stop ボタンを押した時に、Centralがオンだったら呼ばれる
    func stopCentralManager() {
        stopScan()
    }
    
    // 電源がオンになるのを待たないといけない
    func startScan() {
        print("startScan")
        // 本当は、サービスのUUIDを指定するのが正しいはずだがうまく動かない
        self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        //let UUID = CBUUID(string: "73C98F4C-F74F-4918-9B0A-5EF4C6C021C6")
        //let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
        //self.centralManager.scanForPeripherals(withServices: [UUID,UUID_Read], options: nil)
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
        
        //print("didDiscover peripheral. NOT implemented yet.")
        //print("didDiscoverPeripheral\n")
        //print("name: \(String(describing: peripheral.name))\n")
        //print("UUID: \(peripheral.identifier.uuidString)")
        //print("advertisementData: \(advertisementData)")
        //print("kCBAdvDataLocalName:",advertisementData["kCBAdvDataLocalName"] ?? "unknown")
        //print("RSSI: \(RSSI)")
        //self.message.addItem(messageText: "didDiscover peripheral is called")
        
        if peripheral.state != CBPeripheralState.disconnected {
            // disconnected でなくても、didDiscover は呼ばれる。もしかしたら、設定で変えられるかもしれない。
            // すでに connect されているデバイスなので、何もしない。
            print("this peripheral is not disconnected")
            return
        } else {
            //print("this peripheral is disconnected")
        }

        
        let LocalName = advertisementData["kCBAdvDataLocalName"] ?? "unknown"
        if LocalName as! String  == "BLEcommTest0" {
            print("I got BLEcommTest0")
        
        
            // BLEtest2のロジックを、コメントも含めてそのままコピペ
            /*
            let index = self.peripheralArray.indexOf { (p: CBPeripheral) -> Bool in
                p.identifier.UUIDString == peripheral.identifier.UUIDString
            }
            */
            let index = self.peripheralInfoArray.firstIndex { (p: PeripheralInfo) -> Bool in
                p.peripheral.identifier.uuidString == peripheral.identifier.uuidString
            }
            // UUIDは同じだけど、peripheralは違うという事はないのか？
            if index != nil {
                peripheralInfoArray[index!].peripheral = peripheral
            }
            print("index: \(index ?? -1)")
            /*
            if index == nil {
                self.peripheralArray.append(peripheral as CBPeripheral)
                self.tableView.reloadData()
            }
            */
            if index == nil {
                print("index is nil ???")
                let currentDate = Date()
                let peripheralInfo = PeripheralInfo(peripheral: peripheral, rssi: RSSI,     username: "unknown", firstDate: currentDate, lastDate: currentDate)
                self.peripheralInfoArray.append(peripheralInfo as PeripheralInfo)
                //self.tableView.reloadData()
                print("new peripheralInfo.firstDate    \(peripheralInfo.firstDate)")
                print("new peripheralInfo.lastDate    \(peripheralInfo.lastDate)")

            }
        
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
            if         connectedPeripheral == nil {
                self.centralManager.connect(peripheral, options: nil)
            } else {
                print("some one else is already connected. Don't connect")
                print(connectedPeripheral)
                switch connectedPeripheral.state {
                case CBPeripheralState.disconnected:
                    print("disconnected")
                    // とりあえず、この場合は connect に行ってみる
                    self.centralManager.connect(peripheral, options: nil)

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
        }
    }
    
   
    // 3-2. Peripheralへの接続結果の受信(成功時)
    public func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral)
    {
        // 複数台の時に lock 処理が必要
        print("C: connection success!")
        // デリゲートの設定
        peripheral.delegate = self
        
        // 覚えておく 2021/2/6 T.Ogino
        // 上位の関数が、peripheralを使えるように（writeが呼べるように）
        connectedPeripheral = peripheral
        // 4-1. 利用可能Serviceの探索開始
        let UUID_Service = BLEcommService.UUID_Service
        peripheral.discoverServices([UUID_Service])
    }
    // 3-2. Peripheralへの接続結果の受信(失敗時)
    public func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                                                   error: Error?)
    {
        print("connection failed")
    }
    
    // disconnectの検出（できるのか？）
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("didDisconnectPeripheral is called") // ペリフェラルが切れると呼ばれる。確認済。
        
        // 処理全体をリセットしたいが、転送中のTransferCとかはどうするのか？
        connectedPeripheral = nil
        
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
    }
    
    
    // 4-2. Service探索結果の受信
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("didDiscoverServices")
        if (error != nil) {
            print("error: \(String(describing: error))")
            return
        }
        
        print("C: search service")
        print("Found \(peripheral.services!.count) services! : \(String(describing: peripheral.services))")

        for service in peripheral.services!
        {
            print("C: find service")
            print("C: \(service)")
            
            self.serviceArray.append(service as CBService)
            
            // 5-1. 利用可能Characteristicの探索開始
            //#define kCharacteristicUUIDEncounterRead    @"1BE31CB9-9E07-4892-AA26-30E87ABE9F70"
            //#define kCharacteristicUUIDEncounterWrite   @"0C136FCC-3381-4F1E-9602-E2A3F8B70CEB"
            //let UUID_Read = CBUUID(string: "1BE31CB9-9E07-4892-AA26-30E87ABE9F70")
            //let UUID_Write = CBUUID(string: "0C136FCC-3381-4F1E-9602-E2A3F8B70CEB")


            peripheral.discoverCharacteristics([UUID_Read,UUID_Write], for:service as CBService)
            // peripheral.discoverCharacteristics(nil, forService:service as CBService)
            /* ↑の第1引数はnilは非推奨。*/
        }
    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("didDiscoverCharacteristeicsForService error: \(error)")
            return
        }
        
        let characteristics = service.characteristics!
        print("Found \(characteristics.count) characteristics! : \(characteristics)")
        
        for characteristic in characteristics
        {
            if characteristic.uuid == UUID_Read {
                print("find UUID_Read and read value")
                // 値を読む
                print("don't read for debug")
                //peripheral.readValue(for: characteristic)
                foundCharacteristicR = characteristic // save
            }
            
            if characteristic.uuid == UUID_Write {
                print("find UUID_Write and write value")
                //let data = "BLEcommTest0".data(using: String.Encoding.utf8, allowLossyConversion:true)
                //peripheral.writeValue(data!, for: characteristic, type: CBCharacteristicWriteType.withResponse)
                
                print("don't write for debug")
                //writeData("debugWrite", peripheral: peripheral)
                
                // とりあえずUUID_Writeが見つかったら、メッセージのTransferを開始する。
                if self.userMessage != nil {
                    self.userMessage.startTransfer(connectedPeripheral: self.connectedPeripheral)
                }
            }
             

        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDisconnectedPeripheral service: CBService, error: Error?) {
        // とりあえず呼ばれるかどうか確認する -> 呼ばれない -> 終了処理は、Message.swift 側でやる
        // これ以外の処理が必要だけど、まだやっていない。落ちるかもしれない。
        print("didDisconnectedPeripheral is called")
    }

    
    public func readfromP(peripheral: CBPeripheral){
        print("enter readfromP")
        peripheral.readValue(for: foundCharacteristicR)

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
        let characteristicvalue: Data = characteristic.value!
        print("Succeeded! service uuid: \(characteristic.service.uuid), characteristic uuid: \(characteristic.uuid), value: \(characteristicvalue)")
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
            
            print(transferMessage)
            //print("length \(username.length)")
            self.log.addItem(logText:"didUpdateValueFor \(transferMessage)")
            self.log.addItem(logText:"length \(transferMessage.length)")

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
    }
    
    public func writecurrent () {
        print("write current is called")
        if self.connectedPeripheral != nil {
            writeData("DEBUG\nwrite current", peripheral: self.connectedPeripheral)
        } else {
            print("debug connectedPeripheral is nil")
        }
    }
    
    func writeData(_ data: String, peripheral: CBPeripheral) {
        print("enter writeData")
        print("data \(data)")
        print(peripheral.services)
        for service in peripheral.services! {
            if service.uuid == UUID_Service {
                print("find UUID_Service")
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
            print("didUpdaateValue fail...error: \(error)")
            return
        }
        print("didUpdateValue is called")
    }
    
    // 相手が切れたとき（？）に呼ばれる
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("didModifyServices called")
    
    }
}

public class BLEPeripheral: NSObject, CBPeripheralManagerDelegate, ObservableObject {
    var peripheralManager: CBPeripheralManager!
    var peripheralMode: Bool = false
    var log : Log!
    var userMessage: UserMessage!
    
    public func myinit(userMessage: UserMessage) {
        print("BLEPeripheral myinit is called")
        self.userMessage = userMessage
        //self.userMessage.addItem(userMessageText: "BLEPeripheral myinit is called")
        //self.log.addItem(logText: "BLEPeripheral myinit is called")
        // まだ log を知らないので書けない
    }
    
    func startPeripheralManager(log: Log) {
        self.log = log
        self.log.addItem(logText:"startPeripheralManager")
        if self.peripheralManager == nil {
            print("peripheralManger is nil")
            self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            // 取り敢えずアドバタイズ開始
            if (peripheralMode) {
                startAdvertise()
            }
        }
        print("Peripheral Manager State: \(self.peripheralManager.state)")

    }
    // stop ボタンを押した時に、Peripheralがオンだったら呼ばれる
    public func stopPeripheralManager() {
        print("stopPeripheralManager called. Not implemented yet.")
        // stop advertise
        stopAdvertise()
    }

    // この辺は、BLETest2 からコピー
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("peripheralManagerDidUpdateState is not implemented yet.")
        self.log.addItem(logText:"peripheralManagerDidUpdateState")
        
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

        // sample code
//        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
//                                                         properties: [.notify, .writeWithoutResponse],
//                                                         value: nil,
//                                                         permissions: [.readable, .writeable])
        // キャラクタリスティックをサービスにセット
        service.characteristics = [characteristicR,characteristicW]
        
        // サービスを Peripheral Manager にセット
        self.peripheralManager.add(service)
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

        let advertisementData = [CBAdvertisementDataLocalNameKey: "BLEcommTest0"]
        if (peripheralMode) {
            peripheralManager.startAdvertising(advertisementData);
        }
    }
    
    func stopAdvertise() {
        print("enter stopAdvertising")

        if (peripheralMode) {
            peripheralManager.stopAdvertising();
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("enter didReceiveReadRequest \(request.characteristic.uuid)")
        // Peripheral側のCBCentralオブジェクトでMTUを確認する
        print("Received read request: MTU=\(request.central.maximumUpdateValueLength)");
        
        //let myname = UserDefaults.standard.string(forKey: "myID")
        
        if request.characteristic.uuid.isEqual(UUID_Read) {
            let queue = DispatchQueue.global(qos:.default)
            queue.async {
                //let wmsg: String = "\(myname)" as String
                var wmsg: String
                if transferP != nil {
                    wmsg = (transferP?.getProtocolMessageP())! // ここでブロックしてしまう
                } else {
                    wmsg = "transferP nil error"
                }
                print("wmsg = \(wmsg)")
                request.value = wmsg.data(using: String.Encoding.utf8, allowLossyConversion:true)!
            
                // リクエストに応答
                self.peripheralManager.respond(to: request, withResult: .success)
            }
        } else {
            print("unknown UUID")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("enter didReceiveWriteRequest \(requests[0].characteristic.uuid)")


        for request in requests {
            
            if request.characteristic.uuid.isEqual(UUID_Write) {
                let queue = DispatchQueue.global(qos:.default)
                queue.async {
                    let requestvalue:Data = request.value!
                    print("write value \(requestvalue)")
                    //  文字列ではないと思われる
                    //var username: NSString
                
                    if let writedata = NSString(data: request.value!, encoding: String.Encoding.utf8.rawValue) as String? {
                        print(writedata)
                        self.log.addItem(logText:"didReceiveWriterequest \(writedata)")
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
}
