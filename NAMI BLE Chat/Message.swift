//
//  Message.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import Foundation
import Combine
import CoreBluetooth
import NetworkExtension

class UserMessageItem {
    var code: UUID
    var userMessageID: String
    var userMessageText: String
    
    init (userMessageID:String = "20210101000000.000-0000-NONE", userMessageText:String) {
        self.code = UUID()
        self.userMessageID = userMessageID
        self.userMessageText = userMessageText
    }
}

public class UserDefine: ObservableObject {
    @Published var pStatus: String = "i"
//    @Published var edgeIP: String = "10.9.153.163(Message.swift)" // 多分使われていない
}

/*
var messagelist : [MessageItem] = [ // array の方が正式名称らしいがとりあえずそのまま
    MessageItem(messagetext: "--- message start ---"),
    MessageItem(messagetext: "message2")
]

var messagecount = 0
 */
// ここに書くと、変数にアクセスはできるが、MessageView の画面の更新がうまくできない

public class UserMessage: ObservableObject {
//    @Published var messagelist0 = messagelist
    var bleCentral : BLECentral!
    var blePeripheral : BLEPeripheral!
    var debugMessageFlag = false

    @Published var userMessageList : [UserMessageItem] = [ // array の方が正式名称らしいがとりあえずそのまま
        //UserMessageItem(userMessageID: "  ", userMessageText: "                                                                                        a"),
        //UserMessageItem(userMessageID: "20210101235900000-0001-NONE", userMessageText: "message2")
    ]
    @Published var pStatus: String = "i"

    var userMessageCount = 0
    var PmessageLoopLock = NSLock()
    var messageIDLock = NSLock()
    
    var wifi:WiFi!
    
    func initBLE(bleCentral:BLECentral, blePeripheral:BLEPeripheral) {
        self.bleCentral = bleCentral
        self.blePeripheral = blePeripheral
        
        print("Message.initBLE() is called")
    }
    
    func initWiFi(wifi: WiFi) {
        self.wifi = wifi
    }
    
    func addItem(userMessageText: String) {
        let now = Date() // 現在日時の取得
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
        dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
        let currenttime = dateFormatter.string(from: now) // -> 2021/01/20 19:57:17.234
        print(currenttime + " " + userMessageText)
        
        let iValue = Int.random(in: 1 ... 0xffff)
        let sValue = String(format: "%04x", iValue)
        let myID:String = (UserDefaults.standard.string(forKey: "myID") ?? "NONE") as String
        let userMessageID = currenttime + "-" + sValue + "-" + myID
        
        DispatchQueue.main.async {
            print("debugMessageFlag:",self.debugMessageFlag)
            print(userMessageText)
            self.userMessageCount = self.userMessageCount + 1
            if self.debugMessageFlag {
                self.userMessageList.append(UserMessageItem(userMessageID: userMessageID, userMessageText: "\(currenttime)[\(self.userMessageCount)]: \(userMessageText)"))
            } else {
                self.userMessageList.append(UserMessageItem(userMessageID: userMessageID, userMessageText: "\(userMessageText)"))
            }
            
            // debug
            // 相手が決まらないとかけなくなるので、コメントアウト 2021/12/15
            /*
             if bleCentral != nil {
             let connectedPeripheral = self.bleCentral.connectedPeripheral
             print("debug \(String(describing: connectedPeripheral))")
             if connectedPeripheral != nil {
             self.bleCentral.writecurrent()
             }
             }
             */
            
            // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
            if self.pStatus == "|" {
                self.pStatus="-"
            } else {
                self.pStatus="|"
            }
        }
    }
    
    // message transfer
    // message transfer は、同じデバイスに対して、１つの transfer トランザクション（？）だけが
    // 許されるようにしないと行けない
    // 相手を指定したいが、peripheral か central か分からない。
    // と思ったが、開始はCentralからしか来ないので、相手はperipheral
    public func startTransfer(connectedPeripheral: CBPeripheral) {
        
        self.blePeripheral.log.addItem(logText: "enter startTransfer, \(connectedPeripheral.name), \(connectedPeripheral.identifier.uuidString) ")
        print("startTransfer is called")
        if pStatus == "|" {
            pStatus="-"
        } else {
            pStatus="|"
        }
        // ここで、validでないTransferCをクリアする
        transferCList.removeAll(where:{$0.valid == false})
        
        if bleCentral.state == BLECentralState.running { // 終了処理に入っていたら、新しいtransferCはつくらない
            let transferC = TransferC(bleCentral: self.bleCentral, connectedPeripheral: connectedPeripheral)
            transferCList.append(transferC)
            print("transfer list \(transferCList)")

            self.blePeripheral.log.addItem(logText: "call transferC.start(), \( connectedPeripheral.name ), \( connectedPeripheral.identifier.uuidString) ")

            transferC.start()
        } else {
            self.blePeripheral.log.addItem(logText: "not runnning in transferC.start()")

        }
    }
    
    // Peripheral側のロジック
    // 本当はすべて transferP の中のほうが良い気がする
    public func analyzeText(protocolMessageText: String) {
        print("message.analyzeText is called")
        let command:[String] = protocolMessageText.components(separatedBy:"\n")
        self.blePeripheral.log.addItem(logText:"command \(command[0]),")
        switch command[0] {
        case "BEGIN0":
            print("BEGIN0")
            self.blePeripheral.log.addItem(logText:"BEGIN0 before PmessageLoopLock.lock()")
            if (PmessageLoopLock.lock(before:Date().addingTimeInterval(1))==false) {
                // P を stop した直後にBegin0がくると、ここでlockに失敗する。
                // C側をエラーにするためにエラーを返したい。この方法で返るのか怪しい。
                self.blePeripheral.log.addItem(logText:"BEGIN0 PmessageLoopLock.lock() failed")
                
                transferP = TransferP(blePeripheral: self.blePeripheral)
                transferP?.write2C(writeData: "error")
            
                return // return で良いのか？
            }
            //self.blePeripheral.log.addItem(logText:"BEGIN0 after PmessageLoopLock.lock()")
            
            self.blePeripheral.log.addItem(logText:"P: MessageLoop start")
            transferP = TransferP(blePeripheral: self.blePeripheral)
            // ここで transferPがnilということはない
            transferP?.begin0()
        
        case "IHAVE":
            // error check が必要か？
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolErro (analyzeText:IHAVE)")
                return
            }
            transferP!.ihave(userMessageID: command[1])
            
        case "MSG":
            print("receive MSG")
            // more actions are needed !!!
            addItemExternal(protocolMessageCommand: command)
            
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolErro (analyzeText:MSG)")
                return
            }
            transferP!.ack()
            self.blePeripheral.log.addItem(logText:"P send ACK for MSG,")
            print("P sent ACK for MSG")

            
        case "BEGIN1":
            print("receive BEGIN1")
            
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolErro (analyzeText:BEGIN1)")
                return
            }

            transferP!.begin1()
            // この時点で、ループは終了なので、transferPをnilにしていいはず
            self.blePeripheral.log.addItem(logText:"after BEGIN1, finish loop,")
            transferP = nil // ここで、nil にしてしまうと、まだ相手がメッセージを読んでないのでエラーになる。-> 修正した（はず）
            PmessageLoopLock.unlock()
            self.blePeripheral.log.addItem(logText:"after BEGIN1, unlock PmessageLoopLock,")

            
        case "ACK":
            print("P receive ACK")
            
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolError (analyzeText:ACK)")
                return
            }

            transferP!.appendReceiveMessage(receiveProtocolMessage: protocolMessageText)
            
        case "INEED":
            print("P receive INEED")
            
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolErro (analyzeText:INEED)")
                return
            }

            transferP!.appendReceiveMessage(receiveProtocolMessage: protocolMessageText)
            
        case "DEBUG":
            self.blePeripheral.log.addItem(logText:"DEBUG analyzeText \(protocolMessageText),")
            
        default:
            print("OTHER COMMAND (ERROR)")
            transferP = nil
            PmessageLoopLock.unlock()
            self.blePeripheral.log.addItem(logText:"protocol error, unlock PmessageLoopLock,")


        }

    }
    
    // 相手から来たメッセージには、相手の時刻、相手のメッセージ番号が入っている
    // これらをどうするかちゃんと決めないといけない
    // とりあえずそのまま表示
    func addItemExternal(protocolMessageCommand: [String]) {
        DispatchQueue.main.async {
            self.bleCentral.log.addItem(logText: "async addItemExternal")
            //self.messageIDLock.lock() // original
            
            if (self.messageIDLock.lock(before:Date().addingTimeInterval(30)) == false) {
                if self.bleCentral != nil {
                    self.bleCentral.log.addItem(logText: "messageIDLock failed in addItemExternal")
                }
                return
            }
            
            for userMessage in self.userMessageList {
                if userMessage.userMessageID == protocolMessageCommand[1] {
                    print("I already have \(userMessage.userMessageID)")
                    if self.bleCentral != nil {
                        self.bleCentral.log.addItem(logText: "I already have \(userMessage.userMessageID) in addItemExternal")
                    }
                    self.messageIDLock.unlock()
                    return
                }
            }
            
            self.userMessageCount = self.userMessageCount + 1 // これを増やす必要があるか不明

            self.userMessageList.append(UserMessageItem(userMessageID: protocolMessageCommand[1], userMessageText: protocolMessageCommand[2]))
            self.messageIDLock.unlock()
            self.bleCentral.log.addItem(logText: "addItemExternal append, \(protocolMessageCommand[1]), \(protocolMessageCommand[2]) ")
            
            // command かどうか確認 2024.2.19
            MessageCommandCheck(MessageCommand: protocolMessageCommand[2])
            
            // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
            if self.pStatus == "|" {
                self.pStatus="-"
            } else {
                self.pStatus="|"
            }
        }
        
        func MessageCommandCheck(MessageCommand: String) {
            print(MessageCommand)
            // MessageCommand = "command,wifi,<SSID>,<PASS>"
        
            let commands:[String] = MessageCommand.components(separatedBy:",")
            print(commands)
            
            if commands[0]=="command" {
                if commands.count == 1 {
                    print("command syntax error: \(commands)")
                    self.bleCentral.log.addItem(logText: "command syntax error: \(commands)")
                } else {
                    if commands[1]=="wifi" {
                        if commands.count != 5 {
                            print("command[wifi] syntax error: \(commands)")
                            self.bleCentral.log.addItem(logText: "command[wifi] syntax error: \(commands)")
                        } else {
                            let ssid = commands[2]
                            let pass = commands[3]
                            let edgeIP = commands[4]
                            self.wifi.edgeIP = "set for debug"
                            
                            print(ssid, pass, edgeIP, self.wifi.edgeIP)
                            
                            self.wifi.connect(ssid: ssid, password: pass, edgeIP: edgeIP)
                        }
                    }
                }
            }
        }
        
        // wifitestからコピペ、引数だけ修正
        func obsolute_connect(ssid:String, pass:String) {
            print("connect")
            print(ssid)
            print(pass)
            // https://qiita.com/Howasuto/items/0538f7b3795a9470b5d9
            // Important
            
            // To use the NEHotspotConfigurationManager class, you must enable the Hotspot Configuration capability in Xcode. For more information, see Hotspot Configuration Entitlement.
            //インスタンスの生成
            // originalはshared()だったけど、エラーになるので修正
            let manager = NEHotspotConfigurationManager.shared
            //仮のSSIDを代入
            //ssid = "GR-MT300N-V2-d2a"
            //仮のPASSWORDを代入
            let password = pass
            //後ほど利用するisWEPの値としてtureを代入
            let isWEP = false // trueでエラーだったのでとりあえずfalse
            //変数にWifiスポットの設定を代入
            let hotspotConfiguration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: isWEP)
            //上記で記述したWifi設定に対して制限をかける。
            //hotspotConfiguration.joinOnce = false // trueを変更
            //ここでも有効期限として制限をかける。
            //hotspotConfiguration.lifeTimeInDays = 30 // 1を変更

            //ダイアログを出現させる。
            var res = "" // 本当は、画面表示の @State の変数だった
            // error は、apply が成功したかかどうかで、接続とは関係ない
            manager.apply(hotspotConfiguration) { (error) in
              if let error = error {
                  print(error)
                  if (error.localizedDescription == "already associated.") {
                      res = "associated"
                  } else {
                      res = "error"
                  }
              } else {
                  // 接続失敗は、apply自体は成功しているので、こちらに来る
                 print("success")
                 res = "success"
              }
            }
            print(res)

        }

    }
}


// ユーザが見えるメッセージと、下位のプロトコルのメッセージがごっちゃになっている
// 上位-> usermessage、下位->protocolmessageに修正する
// Transfer １つにつき、インスタンスを使う
// 実際には、ほとんど１つしか使わないと思うが、複数できるようにしておかないと
// 後で問題が発生するかもしれないので、そういう感じにしておく。
var transferCList: [TransferC] = []

class TransferC {
    var connectedPeripheral: CBPeripheral
    var bleCentral: BLECentral
    var protocolMessageQueue:[String]
    var protocolMessageIndex: Int
    var semaphore: DispatchSemaphore
    var loopLock: NSLock
    var valid: Bool
    
    init (bleCentral: BLECentral, connectedPeripheral: CBPeripheral) {
        self.connectedPeripheral = connectedPeripheral
        self.bleCentral = bleCentral
        self.protocolMessageQueue = []
        self.protocolMessageIndex = 0
        self.semaphore = DispatchSemaphore(value: 0)
        self.loopLock = NSLock()
        self.valid = true
    }
    
    // ＊重要＊ 通信他でエラーになった時の処理がない
    func start() {
        let queue = DispatchQueue.global(qos:.default)
        queue.async {
            print("transfer.start is called")
            self.bleCentral.log.addItem(logText: "in transferC.start() before lock, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
            //self.loopLock.lock() // この lock は何のため？ -> CtoP の時に、転送途中の処理を待つため。
            
            if (self.loopLock.lock(before:Date().addingTimeInterval(1))==false) {
                // エラー時の処理
                // C を stop した直後にここにくると、ここでlockに失敗するはず（実際には発生していない）
                
                self.bleCentral.log.addItem(logText:"TransferC.start loopLock.lock() failed")
                            
            } else { // 正常時の処理
                
                
                //self.bleCentral.log.addItem(logText: "in transferC.start() after lock, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
                self.bleCentral.log.addItem(logText: "C: MessageLoop start, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")

                // send BEGIN0
                self.bleCentral.writeData("BEGIN0\n", peripheral: self.connectedPeripheral)
                self.bleCentral.readfromP(peripheral: self.connectedPeripheral) // とりあえず、readが出来るかの確認
                // 値をどうやってもらうか？
                let returnProtocolMessage = self.getProtocolMessage()
                print("returnMessage \(returnProtocolMessage)")
                
                // send message loop
                self.sendMessageLoop()
                
                // receive message loop
                self.receiveMessageLoop()
                
                // １回のメッセージのやりとりは終了したので、終了処理をする。
                
                self.loopLock.unlock()
                
            }
            
            // disconnect
            // 変数の初期化（connectedPeripheral だけで良いのか？）
            self.valid = false
            self.bleCentral.centralManager.cancelPeripheralConnection(self.connectedPeripheral)
            //self.bleCentral.connectedPeripheral = nil

            print("end of TransferC.start.async 1")
            self.bleCentral.log.addItem(logText: "end of TransferC.start.async 1")

            // ここで無条件に restatScan してしまうと、stop ボタンが効かないのでやめる。
            //self.bleCentral.restartScan()
        }

    }
    
    func errorReset() {
        print("errorReset()")
        self.bleCentral.centralManager.cancelPeripheralConnection(self.connectedPeripheral)
        self.valid = false
        //self.bleCentral.connectedPeripheral = nil
    }
    
    func sendMessageLoop(){
        print("sendMessageLoop")
        self.bleCentral.log.addItem(logText:"C: enter sendMessageLoop")

        for userMessage in bleCentral.userMessage.userMessageList {
            print(userMessage.userMessageID,userMessage.userMessageText)
            
            // Time check
            if messageIDTimeCompare(messageID:userMessage.userMessageID, limit: 3600)==false {
                self.bleCentral.log.addItem(logText:"C:message \(userMessage.userMessageID) is too old")
                continue
            }
            
            // send IHAVE
            self.bleCentral.writeData("IHAVE\n\(userMessage.userMessageID)\n", peripheral: self.connectedPeripheral)
            self.bleCentral.readfromP(peripheral: self.connectedPeripheral) // read
            // 値をもらう
            let returnProtocolMessage = self.getProtocolMessage()
            print("returnMessage \(returnProtocolMessage)")
            // INEEDかどうかの確認
            let receiveCommand = getCommand(protocolMessageText: returnProtocolMessage)
            if receiveCommand[0] == "INEED" {
                print("receive INEED \(receiveCommand[1])")
                let sendMessage = "MSG\n" + userMessage.userMessageID + "\n" + userMessage.userMessageText // + "\n" // Do I need the last '\n' ?
                self.bleCentral.writeData(sendMessage, peripheral: self.connectedPeripheral)
                print("C send MSG")
                self.bleCentral.readfromP(peripheral: self.connectedPeripheral)
                // 値をもらう
                let returnProtocolMessage2 = self.getProtocolMessage()
                print("returnMessage for MSG \(returnProtocolMessage2)")
            } else { // should be ACK
                print("receive \(receiveCommand)")
                if receiveCommand[0] != "ACK" {
                    print("sendMessageLoop error")
                }
            }


        }
        print("sendMessageLoopEnd")
    }
    
    func receiveMessageLoop() {
        print("receiveMessageLoop")
        self.bleCentral.log.addItem(logText: "C: enter receiveMessageLoop")
        
        // send BEGIN1
        self.bleCentral.writeData("BEGIN1\n", peripheral: self.connectedPeripheral)
        
        while true {
            self.bleCentral.readfromP(peripheral: self.connectedPeripheral)
            // 値をもらう
            let returnProtocolMessage = self.getProtocolMessage()
            print("receiveMessageLoop \(returnProtocolMessage)")
            // END1 かどうかの確認
            let receiveCommand = getCommand(protocolMessageText: returnProtocolMessage)
            switch receiveCommand[0] {
            case "END1":
                print("end of receiveMessageLoop")
                self.bleCentral.log.addItem(logText: "C: receiveMessageLoop END1, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
                return
            
            case "IHAVE":
                print("C receive IHAVE \(receiveCommand[1])")
                self.bleCentral.log.addItem(logText: "C: receiveMessageLoop IHAVE \(receiveCommand[1])")
                
                var ihave: Bool = false
                for userMessage in bleCentral.userMessage.userMessageList {
                    if userMessage.userMessageID == receiveCommand[1] {
                        print("C already have \(userMessage.userMessageID)")
                        // send ACK
                        self.bleCentral.writeData("ACK\n", peripheral: self.connectedPeripheral)
                        ihave = true
                        break
                    }
                }
                if ihave != true {
                    print("C don't have \(receiveCommand[1])")
                    self.bleCentral.writeData("INEED\n"+receiveCommand[1]+"\n", peripheral: self.connectedPeripheral)
                }

            case "MSG":
                print("receive MSG (not implemented yet) \(receiveCommand[1])")
                self.bleCentral.log.addItem(logText:"C: receiveMessageLoop MSG, \(receiveCommand[1])")

                self.bleCentral.userMessage.addItemExternal(protocolMessageCommand: receiveCommand)
                // for debug
                // only send ACK
                self.bleCentral.writeData("ACK\n", peripheral: self.connectedPeripheral)

                
            default:
                print("receiveMessageLoopError \(receiveCommand[0])")
                self.bleCentral.log.addItem(logText:"C: receiveMessageLoop Error, \(receiveCommand[0])")
                errorReset()
                return
            }
        }

        
    }
    
    func getCommand(protocolMessageText:String) -> [String] {
        let command:[String] = protocolMessageText.components(separatedBy:"\n")
        return command
    }
    
    func appendMessage(protocolMessage:String) {
        // 本当はここでLockをかけるべき
        self.protocolMessageQueue.append(protocolMessage)
        self.bleCentral.log.addItem(logText:"appendMessage before signal")
        self.semaphore.signal()
        self.bleCentral.log.addItem(logText:"appendMessage after signal")
    }
    
    // 本当はロックを使って、正しいメッセージを読むべき
    // wait()を入れると全体が止まってしまう
    // start() を async にした。とりあえず、動いている
    func getProtocolMessage()-> String {
        switch (self.semaphore.wait(timeout: .now() + 30)) {
        case .success:
            self.bleCentral.log.addItem(logText:"wait in getProtocolMessage succeed, \( self.connectedPeripheral.name ), \( self.connectedPeripheral.identifier.uuidString ) ")
            
        case .timedOut:
            self.bleCentral.log.addItem(logText:"wait in getProtocolMessage failed, \( self.connectedPeripheral.name ), \( self.connectedPeripheral.identifier.uuidString ) ")
            return("getProtocolMessageTimedOut")
            
        }
        
        // 以下のロジックは不要なはず
        if self.protocolMessageQueue.count <= self.protocolMessageIndex {
            return "No Message"
        }
        
        let retProtocolMessage = self.protocolMessageQueue[self.protocolMessageIndex]
        self.protocolMessageIndex = self.protocolMessageIndex + 1
        return retProtocolMessage
    }
}

// peripheral側のtransfer

var transferP: TransferP?
enum TransferStatus {
    case phase0
    case phase1
}
class TransferP {
    var status:TransferStatus
    var blePeripheral:BLEPeripheral
    var protocolMessageQueue:[String]
    var protocolMessageIndex: Int
    var protocolMessageSemaphore: DispatchSemaphore
    var protocolMessageSyncSemaphore: DispatchSemaphore
    var receiveMessageQueue:[String]
    var receiveMessageIndex: Int
    var receiveMessageSemaphore: DispatchSemaphore
    
    init(blePeripheral: BLEPeripheral){
        self.status = .phase0
        self.blePeripheral = blePeripheral
        self.protocolMessageQueue = [] // from transfer to BLE
        self.protocolMessageIndex = 0
        self.protocolMessageSemaphore = DispatchSemaphore(value: 0)
        self.protocolMessageSyncSemaphore = DispatchSemaphore(value: 0)
        self.receiveMessageQueue = []
        self.receiveMessageIndex = 0
        self.receiveMessageSemaphore = DispatchSemaphore(value: 0)
    }
    
    func begin0(){
        self.blePeripheral.log.addItem(logText:"transferP.begin0,")
        write2C(writeData: "ACK\n")
    }
    
    func ack() {
        write2C(writeData: "ACK\n")
    }
    
    func write2C(writeData: String) {
        // messageをキュー（？）入れる
        // read request が来たら読める（はず）
        // notify する？
        
        // 本当はここでLockをかけるべき
        self.protocolMessageQueue.append(writeData)
        self.protocolMessageSemaphore.signal()
        // このロジックは合っているのか？
        switch(self.protocolMessageSyncSemaphore.wait(timeout: .now() + 30)) {
        case .success:
            print("success in write2C")
            
        case .timedOut:
            print("timedout in write2C")

            self.blePeripheral.log.addItem(logText:"timedOut in write2C")
            
        }

    }
    
    func appendReceiveMessage(receiveProtocolMessage:String) {
        // 本当はここでLockをかけるべき
        self.receiveMessageQueue.append(receiveProtocolMessage)
        self.receiveMessageSemaphore.signal()
    }
    
    func getProtocolMessageP()-> String {
        print("before protocol wait") // ここでブロックしてしまう
        switch (self.protocolMessageSemaphore.wait(timeout: .now() + 30)) { // どこで書いている？
        case .success:
            print("success in getProtocolMessageP")
            self.blePeripheral.log.addItem(logText: "success to wait in getProtocolMessageP")
        case .timedOut:
            print("timedOut in getProtocolMessageP")
            self.blePeripheral.log.addItem(logText: "fail to wait in getProtocolMessageP")
            return("timedOut")
        }
        if self.protocolMessageQueue.count <= self.protocolMessageIndex {
            return "No Message"
        }
        let retMessage = self.protocolMessageQueue[self.protocolMessageIndex]
        self.protocolMessageIndex = self.protocolMessageIndex + 1
        
        //self.protocolMessageSyncSemaphore.signal() // 早すぎないか？ -> BLE の didReceiveRead に移動
        return retMessage
    }
    
    func getReceiveProtocolMessage()-> String {
        print("before receive wait")
        switch (self.receiveMessageSemaphore.wait(timeout: .now() + 30)) { // どこで書いている？
        case .success:
            print("success in getReceiveProtocolMessage")
            self.blePeripheral.log.addItem(logText: "success to wait in getReceiveProtocolMessage")
        case .timedOut:
            print("timedOut in getReceiveProtocolMessage")
            self.blePeripheral.log.addItem(logText: "fail to wait in getReceiveProtocolMessage")
            return("timedOut")
        }
        if self.receiveMessageQueue.count <= self.receiveMessageIndex {
            return "No Message"
        }
        let retReceiveMessage = self.receiveMessageQueue[self.receiveMessageIndex]
        self.receiveMessageIndex = self.receiveMessageIndex + 1
        return retReceiveMessage
    }
    
    func ihave(userMessageID: String) {
        self.blePeripheral.log.addItem(logText:"transferP.ihave, \(userMessageID),")
        
        for userMessage in blePeripheral.userMessage.userMessageList {
            if userMessage.userMessageID == userMessageID {
                print("I already have \(userMessageID)")
                write2C(writeData: "ACK\n")
                return
            }
        }
        
        print("I don't have \(userMessageID)")
        write2C(writeData: "INEED\n\(userMessageID)\n")

    }
    
    func begin1() {
        self.blePeripheral.log.addItem(logText:"transferP.begin1,")

        for userMessage in blePeripheral.userMessage.userMessageList {
            print("I(P) have \(userMessage.userMessageID)")
            
            // Time check
            if messageIDTimeCompare(messageID:userMessage.userMessageID, limit: 3600)==false {
                self.blePeripheral.log.addItem(logText:"P:message \(userMessage.userMessageID) is too old")
                continue
            }
            
            // send IHAVE
            write2C(writeData: "IHAVE\n\(userMessage.userMessageID)\n")
            
            // get reply
            let protocolMessageText = getReceiveProtocolMessage()
            let command:[String] = protocolMessageText.components(separatedBy:"\n")
            switch command[0] {
            case "ACK":
                print("begin1 receive ACK")
                continue
                
            case "INEED":
                print("begin1 receive INEED (not implemented yet)")
                begin1_sendmsg(userMessageID: command[1])
                
            default:
                print("protocol error in begin1")
            }
        }
        
        write2C(writeData: "END1\n")
        self.blePeripheral.log.addItem(logText:"P: MessageLoop end")


    }
    
    func begin1_sendmsg(userMessageID: String){
        print("begin1_sendmsg \(userMessageID)")
        self.blePeripheral.log.addItem(logText:"transferP.begin1_sendmsg \(userMessageID),")
    
        for userMessage in blePeripheral.userMessage.userMessageList {
            if userMessage.userMessageID == userMessageID {
                let sendMessage = "MSG\n" + userMessage.userMessageID + "\n" + userMessage.userMessageText
                write2C(writeData: sendMessage)
                print("P send MSG")
                return
            }
        }
        
        print("Protocol error in begin1_sendmsg")
        self.blePeripheral.log.addItem(logText:"Protocol error in begin1_sendmsg,")

    }
}

func messageIDTimeCompare(messageID:String, limit: Int) -> Bool { // now() から limit 以内の過去なら true
    let now = Date() // 現在日時の取得
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
    dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
    
    let messageTimeStr = String(messageID.prefix(18))
    guard let date = dateFormatter.date(from: messageTimeStr) else { return false }
    
    let calender = Calendar.init(identifier: .gregorian)
    guard let timediff = calender.dateComponents([.second], from: date, to: now).second else { return false}
    
    if (timediff <= limit) {
        return true
    } else {
        return false
    }
    
}
