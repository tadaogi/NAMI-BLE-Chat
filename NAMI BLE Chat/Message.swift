//
//  Message.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import Foundation
import Combine
import CoreBluetooth

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

    @Published var userMessageList : [UserMessageItem] = [ // array の方が正式名称らしいがとりあえずそのまま
        //UserMessageItem(userMessageID: "  ", userMessageText: "                                                                                        a"),
        //UserMessageItem(userMessageID: "20210101235900000-0001-NONE", userMessageText: "message2")
    ]
    @Published var pStatus: String = "i"

    var userMessageCount = 0
    var PmessageLoopLock = NSLock()
    
    func initBLE(bleCentral:BLECentral, blePeripheral:BLEPeripheral) {
        self.bleCentral = bleCentral
        self.blePeripheral = blePeripheral
        
        print("Message.initBLE() is called")
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
            self.userMessageCount = self.userMessageCount + 1
            self.userMessageList.append(UserMessageItem(userMessageID: userMessageID, userMessageText: "\(currenttime)[\(self.userMessageCount)]: \(userMessageText)"))
        
            
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
        print("startTransfer is called")
        if pStatus == "|" {
            pStatus="-"
        } else {
            pStatus="|"
        }
        // ここで、validでないTransferCをクリアする
        transferCList.removeAll(where:{$0.valid == false})
        
        let transfer = TransferC(bleCentral: self.bleCentral, connectedPeripheral: connectedPeripheral)
        transferCList.append(transfer)
        print("transfer list \(transferCList)")
        
        transfer.start()
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
            PmessageLoopLock.lock()
            transferP = TransferP(blePeripheral: self.blePeripheral)
            // ここで transferPがnilということはない
            transferP!.begin0()
        
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
            self.blePeripheral.log.addItem(logText:"P send ACK for MSGH,")
            print("P sent ACK for MSG")

            
        case "BEGIN1":
            print("receive BEGIN1")
            
            if transferP == nil {
                self.blePeripheral.log.addItem(logText:"protocolErro (analyzeText:BEGIN1)")
                return
            }

            transferP!.begin1()
            // この時点で、ループは終了なので、transferPをnilにしていいはず
            self.blePeripheral.log.addItem(logText:"after BEGIN1, finish loop")
            transferP = nil // ここで、nil にしてしまうと、まだ相手がメッセージを読んでないのでエラーになる。-> 修正した（はず）
            PmessageLoopLock.unlock()

            
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

        }

    }
    
    // 相手から来たメッセージには、相手の時刻、相手のメッセージ番号が入っている
    // これらをどうするかちゃんと決めないといけない
    // とりあえずそのまま表示
    func addItemExternal(protocolMessageCommand: [String]) {
        DispatchQueue.main.async {
            self.userMessageCount = self.userMessageCount + 1 // これを増やす必要があるか不明

            self.userMessageList.append(UserMessageItem(userMessageID: protocolMessageCommand[1], userMessageText: protocolMessageCommand[2]))
            
            // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
            if self.pStatus == "|" {
                self.pStatus="-"
            } else {
                self.pStatus="|"
            }
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
    var valid: Bool
    
    init (bleCentral: BLECentral, connectedPeripheral: CBPeripheral) {
        self.connectedPeripheral = connectedPeripheral
        self.bleCentral = bleCentral
        self.protocolMessageQueue = []
        self.protocolMessageIndex = 0
        self.semaphore = DispatchSemaphore(value: 0)
        self.valid = true
    }
    
    // ＊重要＊ 通信他でエラーになった時の処理がない
    func start() {
        let queue = DispatchQueue.global(qos:.default)
        queue.async {
            print("transfer.start is called")
            
        
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
            // disconnect
            // 変数の初期化（connectedPeripheral だけで良いのか？）
            self.valid = false
            self.bleCentral.centralManager.cancelPeripheralConnection(self.connectedPeripheral)
            //self.bleCentral.connectedPeripheral = nil

            print("end of TransferC.start.async 1")
            
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
        for userMessage in bleCentral.userMessage.userMessageList {
            print(userMessage.userMessageID,userMessage.userMessageText)
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
                return
            
            case "IHAVE":
                print("C receive IHAVE \(receiveCommand[1])")
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
                self.bleCentral.log.addItem(logText:"transferC received MSG,")

                self.bleCentral.userMessage.addItemExternal(protocolMessageCommand: receiveCommand)
                // for debug
                // only send ACK
                self.bleCentral.writeData("ACK\n", peripheral: self.connectedPeripheral)

                
            default:
                print("receiveMessageLoopError \(receiveCommand[0])")
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
        self.semaphore.signal()
    }
    
    // 本当はロックを使って、正しいメッセージを読むべき
    // wait()を入れると全体が止まってしまう
    // start() を async にした。とりあえず、動いている
    func getProtocolMessage()-> String {
        self.semaphore.wait()
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
        self.protocolMessageSemaphore.wait() // どこで書いている？
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
        self.receiveMessageSemaphore.wait()
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
        self.blePeripheral.log.addItem(logText:"P sent END1,")


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
