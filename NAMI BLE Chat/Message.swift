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

var availableperiod = 3600 * 24 * 7 // 古いメッセージをどこまで処理するか。元々１時間だったけど短すぎるので１週間にしてみる。

class DateUtils {
    class func dateFromString(string: String, format: String) -> Date {
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter.date(from: string)!
    }

    class func stringFromDate(date: Date, format: String) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

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
    var movingEdgeFlag = UserDefaults.standard.bool(forKey: "movingEdgeFlag")
    var runflag: Bool = false
//    var area = UserDefaults.standard.string(forKey: "area") ?? "official"

    @Published var userMessageList : [UserMessageItem] = [ // array の方が正式名称らしいがとりあえずそのまま
        //UserMessageItem(userMessageID: "  ", userMessageText: "                                                                                        a"),
        //UserMessageItem(userMessageID: "20210101235900000-0001-NONE", userMessageText: "message2")
    ]
    @Published var pStatus: String = "i"

    var userMessageCount = 0
    var PmessageLoopLock = NSLock()
    var messageIDLock = NSLock()
    
    var wifi:WiFi!
    var user:User!
    
    private let store: MessageStore
    @Published var uploadfname: String = "message.txt"
    
    init(store: MessageStore) {
        self.store = store
    }
    
    func initBLE(bleCentral:BLECentral, blePeripheral:BLEPeripheral, log: Log) {
        self.bleCentral = bleCentral
        self.blePeripheral = blePeripheral
        // auto だと log が設定されないのでここで設定する
        bleCentral.log = log
        blePeripheral.log = log
        
        print("Message.initBLE() is called")
    }
    
    func initWiFi(wifi: WiFi) {
        self.wifi = wifi
    }
    
    func initUser(user: User) {
        self.user = user
        print(self.user)
    }
    
    func addItemWithGPS(userMessageText: String) {
        // ここではGPSの情報を得られない → user が見えていれば大丈夫
        var sendText = userMessageText
        if self.user != nil {
            var location = user.gps.getLastLocation()
            let latitude = String(format: "%.6f", location.latitude)
            let longitude = String(format: "%.6f", location.longitude)
            let locationTxt = "[GPS,\(latitude),\(longitude)]"
            sendText = locationTxt + userMessageText
            //print(sendText)
        } else {
            var location = globalgps?.getLastLocation()
            let latitude = String(format: "%.6f", location?.latitude ?? 0.0)
            let longitude = String(format: "%.6f", location?.longitude ?? 0.0)
            let locationTxt = "[GPS,\(latitude),\(longitude)]"
            sendText = locationTxt + userMessageText
            //print(sendText)
        }

        addItem(userMessageText: sendText)
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
        let UUID:String = (UserDefaults.standard.string(forKey: "UUID") ?? "00000001-0000-0000-0000-000000000001") as String
        // let userMessageID = currenttime + "-" + sValue + "-" + myID + "(0)" // 最後の()はホップの回数とする
        
        // Split Send の実装 2024/5/16
        let mtu = 512 // ここは相手が決まっていないので、MTUを知ることが出来ない。なので、決め打ちで512にしておく。
        //let mtu = 4
        let userMessageIDformat = currenttime + "-" + sValue + "-" + myID + "-%@(0)" // %@は下で、シーケンス番号に置き換える
        let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
        //var userMessageID : String = ""
        var sequence = 0 // シーケンス番号、０から始まる
        var index = 0 // データを、どこから送るか
        var restToSend = userMessageText.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
        var dataToSend = userMessageText.data(using: .utf8)
        
        DispatchQueue.main.async {
            // ここから下が、Splitのロジック
            while (restToSend>0) {
                var amountToSend = min(restToSend,mtu-headerLength) // 今回送るデータ長
                print("amountToSend=", amountToSend)
                
                var chunk = dataToSend?.subdata(in: index..<(index + amountToSend)) // 今回送るデータ
                var userMessageID : String = ""
                if (index + amountToSend < dataToSend!.count) {
                    print("sequence=",sequence)
                    userMessageID = String(format: userMessageIDformat, String(sequence))
                } else {
                    print("sequence=",sequence)
                    print("last")
                    userMessageID = String(format: userMessageIDformat, String(sequence)+"L")
                }
                print("userMessageID=", userMessageID)
                // print("debugMessageFlag:",self.debugMessageFlag) // メッセージ長さが変わってしまうので、とりあえずここでは使わない
                var UserMessageTextString = String(data:chunk ?? Data(), encoding: .utf8)! // encodeした送るテキスト
                //print(UserMessageTextString)
                self.userMessageCount = self.userMessageCount + 1

                self.userMessageList.append(UserMessageItem(userMessageID: userMessageID, userMessageText: "\(UserMessageTextString)"))
                // message.txt に追加
                let path = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask)[0].appendingPathComponent(self.uploadfname)
                do {
                    try self.appendUserMessage(
                        message: UserMessageItem(userMessageID: userMessageID, userMessageText: UserMessageTextString),
                        to: path
                    )
                } catch {
                    print("append error:", error)
                }

                if (self.movingEdgeFlag) {
                    sendMessage(userMessageID:userMessageID, userMessageText:userMessageText)
                }
                
                index = index + amountToSend
                restToSend = userMessageText.count - index
                sequence = sequence + 1
                
                
                // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
                if self.pStatus == "|" {
                    self.pStatus="-"
                } else {
                    self.pStatus="|"
                }
            }
                        
            // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
            if self.pStatus == "|" {
                self.pStatus="-"
            } else {
                self.pStatus="|"
            }
        }
    }
    
    // addItemを改修して、他のパラメータも渡すように改修
    // MongoEdge から使う
    func addItem2(userMessageID: String, userMessageText: String) {
        
        let IDcomponents = userMessageID.components(separatedBy: "-")
        var dateString:String
        if let tmpString = IDcomponents.first {
            dateString = tmpString
        } else {
            dateString = "20250127055900.123"
        }
        //print(dateString)
        
        let userID = IDcomponents[2]
        //print(userID)
        
        /*
        let now = Date() // 現在日時の取得
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
        dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
        let currenttime = dateFormatter.string(from: now) // -> 2021/01/20 19:57:17.234
        */
        let currenttime = dateString
        //print(currenttime + " " + userMessageText)
        
        /*
        let iValue = Int.random(in: 1 ... 0xffff)
        let sValue = String(format: "%04x", iValue)
        */
        let sValue = IDcomponents[1]
        
        /*
        let myID:String = (UserDefaults.standard.string(forKey: "myID") ?? "NONE") as String
        let UUID:String = (UserDefaults.standard.string(forKey: "UUID") ?? "00000001-0000-0000-0000-000000000001") as String
        */
        let myID = userID
        // let userMessageID = currenttime + "-" + sValue + "-" + myID + "(0)" // 最後の()はホップの回数とする
        
        // Split Send の実装 2024/5/16
        let mtu = 512 // ここは相手が決まっていないので、MTUを知ることが出来ない。なので、決め打ちで512にしておく。
        //let mtu = 4
        let userMessageIDformat = currenttime + "-" + sValue + "-" + myID + "-%@(0)" // %@は下で、シーケンス番号に置き換える
        let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
        //var userMessageID : String = ""
        var sequence = 0 // シーケンス番号、０から始まる
        var index = 0 // データを、どこから送るか
        var restToSend = userMessageText.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
        var dataToSend = userMessageText.data(using: .utf8)
        
        DispatchQueue.main.async {
            // ここから下が、Splitのロジック
            while (restToSend>0) {
                var amountToSend = min(restToSend,mtu-headerLength) // 今回送るデータ長
                print("amountToSend=", amountToSend)
                
                var chunk = dataToSend?.subdata(in: index..<(index + amountToSend)) // 今回送るデータ
                var userMessageID : String = ""
                if (index + amountToSend < dataToSend!.count) {
                    print("sequence=",sequence)
                    userMessageID = String(format: userMessageIDformat, String(sequence))
                } else {
                    print("sequence=",sequence)
                    print("last")
                    userMessageID = String(format: userMessageIDformat, String(sequence)+"L")
                }
                print("userMessageID=", userMessageID)
                // print("debugMessageFlag:",self.debugMessageFlag) // メッセージ長さが変わってしまうので、とりあえずここでは使わない
                var UserMessageTextString = String(data:chunk ?? Data(), encoding: .utf8)! // encodeした送るテキスト
                //print(UserMessageTextString)
                self.userMessageCount = self.userMessageCount + 1

                self.userMessageList.append(UserMessageItem(userMessageID: userMessageID, userMessageText: "\(UserMessageTextString)"))
                // message.txt に追加
                let path = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask)[0].appendingPathComponent(self.uploadfname)
                do {
                    try self.appendUserMessage(
                        message: UserMessageItem(userMessageID: userMessageID, userMessageText: UserMessageTextString),
                        to: path
                    )
                } catch {
                    print("append error:", error)
                }
                
                index = index + amountToSend
                restToSend = userMessageText.count - index
                sequence = sequence + 1
                
                
                // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
                if self.pStatus == "|" {
                    self.pStatus="-"
                } else {
                    self.pStatus="|"
                }
            }
                        
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
        
        if self.blePeripheral.log != nil { // なぜかここで log = nil になった
            Task { @MainActor in
                
                self.blePeripheral.log.addItem(logText: "enter startTransfer, \(connectedPeripheral.name), \(connectedPeripheral.identifier.uuidString) ")
            }
        }
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

            Task { @MainActor in
                
                self.blePeripheral.log.addItem(logText: "call transferC.start(), \( connectedPeripheral.name ), \( connectedPeripheral.identifier.uuidString) ")
            }

            transferC.start()
        } else {
            Task { @MainActor in
                
                self.blePeripheral.log.addItem(logText: "not runnning in transferC.start()")
            }

        }
    }
    
    func logaddItem(logText: String) {
        Task { @MainActor in
            self.blePeripheral.log.addItem(logText: logText)
        }
    }
    // Peripheral側のロジック
    // 本当はすべて transferP の中のほうが良い気がする
    public func analyzeText(protocolMessageText: String) {
        print("message.analyzeText is called")
        let command:[String] = protocolMessageText.components(separatedBy:"\n")
        Task { @MainActor in
            
            self.blePeripheral.log.addItem(logText:"command \(command[0]),")
        }
        switch command[0] {
        case "BEGIN0":
            print("P receive BEGIN0")
            //            self.blePeripheral.log.addItem(logText:"BEGIN0 before PmessageLoopLock.lock()")
            logaddItem(logText:"BEGIN0 before PmessageLoopLock.lock()")
            if (PmessageLoopLock.lock(before:Date().addingTimeInterval(1))==false) {
                // P を stop した直後にBegin0がくると、ここでlockに失敗する。
                // C側をエラーにするためにエラーを返したい。この方法で返るのか怪しい。
                logaddItem(logText:"BEGIN0 PmessageLoopLock.lock() failed")
                
                transferP = TransferP(blePeripheral: self.blePeripheral)
                transferP?.write2C(writeData: "error")
            
                return // return で良いのか？
            }
            //self.blePeripheral.log.addItem(logText:"BEGIN0 after PmessageLoopLock.lock()")
            
            logaddItem(logText:"P: MessageLoop start")
            transferP = TransferP(blePeripheral: self.blePeripheral)
            // ここで transferPがnilということはない
            transferP?.begin0()
        
        case "IHAVE":
            // error check が必要か？
            print("P receive IHAVE \(command[1])")
            if transferP == nil {
                logaddItem(logText:"protocolErro (analyzeText:IHAVE)")
                return
            }
            transferP!.ihave(userMessageID: command[1])
            
        case "MSG":
            print("receive MSG")
            // more actions are needed !!!
            addItemExternal(protocolMessageCommand: command)
            
            if transferP == nil {
                logaddItem(logText:"protocolErro (analyzeText:MSG)")
                return
            }
            transferP!.ack()
            logaddItem(logText:"P send ACK for MSG,")
            print("P sent ACK for MSG")

            
        case "BEGIN1":
            print("P receive BEGIN1")
            
            if transferP == nil {
                logaddItem(logText:"protocolErro (analyzeText:BEGIN1)")
                return
            }

            transferP!.begin1()
            // この時点で、ループは終了なので、transferPをnilにしていいはず
            logaddItem(logText:"after BEGIN1, finish loop,")
            transferP = nil // ここで、nil にしてしまうと、まだ相手がメッセージを読んでないのでエラーになる。-> 修正した（はず）
            PmessageLoopLock.unlock()
            logaddItem(logText:"after BEGIN1, unlock PmessageLoopLock,")

            
        case "ACK":
            print("P receive ACK")
            
            if transferP == nil {
                logaddItem(logText:"protocolError (analyzeText:ACK)")
                return
            }

            transferP!.appendReceiveMessage(receiveProtocolMessage: protocolMessageText)
            
        case "INEED":
            print("P receive INEED")
            
            if transferP == nil {
                logaddItem(logText:"protocolErro (analyzeText:INEED)")
                return
            }

            transferP!.appendReceiveMessage(receiveProtocolMessage: protocolMessageText)
            
        case "DEBUG":
            logaddItem(logText:"DEBUG analyzeText \(protocolMessageText),")
            
        default:
            print("P receive OTHER COMMAND (ERROR)")
            transferP = nil
            PmessageLoopLock.unlock()
            logaddItem(logText:"protocol error, unlock PmessageLoopLock,")


        }

    }
    
    // 相手から来たメッセージには、相手の時刻、相手のメッセージ番号が入っている
    // これらをどうするかちゃんと決めないといけない
    // とりあえずそのまま表示
    func addItemExternal(protocolMessageCommand: [String]) {
        //DispatchQueue.main.async {
        Task { @MainActor in
            self.bleCentral.log.addItem(logText: "async addItemExternal")
            //self.messageIDLock.lock() // original
            
            if (self.messageIDLock.lock(before:Date().addingTimeInterval(30)) == false) { // 大きいけど、ここでのエラーは発生していない
                if self.bleCentral != nil {
                    self.bleCentral.log.addItem(logText: "messageIDLock failed in addItemExternal")
                }
                return
            }
            
            for userMessage in self.userMessageList {
                var id0 = userMessage.userMessageID
                var id1 = protocolMessageCommand[1]
                let reg = /^(?<message>[^(]*)\([0-9]*\)$/
                if let match = id0.firstMatch(of: reg) {
                    id0 = String(match.message)
                }
                if let match = id1.firstMatch(of: reg) {
                    id1 = String(match.message)
                }
                if id0 == id1 {
                    print("I already have \(userMessage.userMessageID)")
                    if self.bleCentral != nil {
                        self.bleCentral.log.addItem(logText: "I already have \(userMessage.userMessageID) in addItemExternal")
                    }
                    self.messageIDLock.unlock()
                    return
                }
            }
            
            self.userMessageCount = self.userMessageCount + 1 // これを増やす必要があるか不明
            
            // IDから時刻を取り出して、現在時刻と比較
            var recUserMessageID = protocolMessageCommand[1]
            let IDarray = recUserMessageID.split(separator:"-")
            if IDarray.count <= 1 {
                print("illeagal userMessageID")
                self.bleCentral.log.addItem(logText: "illeagal userMessageID in addItemExternal")
                
                // ここで必要なはずなので追加 2024/7/24
                self.messageIDLock.unlock()
                
                return
            }
            let IDdateString = String(IDarray[0])
            let date = DateUtils.dateFromString(string: IDdateString , format: "yyyyMMddHHmmss.SSS")
            //print(date)
            let now = Date() // 現在日時の取得
            //print(now)
            let diffsec = now.timeIntervalSince(date)
            //print(diffsec)
            
            if diffsec > Double(availableperiod) { // 1hour -> 1 week
                print("too old userMessageID")
                self.bleCentral.log.addItem(logText: "too old userMessageID in addItemExternal")
                
                // ここで必要なはずなので追加 2024/7/24
                self.messageIDLock.unlock()
                
                return
                
            }
            
            // hop 回数
            var regex = /\((\d+)\)/
            
            var match = recUserMessageID.firstMatch(of: regex)
            if match == nil {
                print("illeagal userMessageID(hop)")
                self.bleCentral.log.addItem(logText: "illeagal userMessageID(hop) in addItemExternal")
                
                // ここで必要なはずなので追加 2024/7/24
                self.messageIDLock.unlock()
                
                return
            }
            var originalhopStr = match?.1 ?? "0"
            var hop = Int(match?.1 ?? "0") ?? 0
            hop = hop + 1
            print(hop)
            if hop > 10 {
                print("too many hops ")
                self.bleCentral.log.addItem(logText: "too many hops in addItemExternal")
                
                // ここで必要なはずなので追加 2024/7/24
                self.messageIDLock.unlock()
                
                return
                
            }
            var newID = recUserMessageID.replacingOccurrences(of: "("+originalhopStr+")", with: "("+String(hop)+")")
            print(newID)
            
            
            self.userMessageList.append(UserMessageItem(userMessageID: newID, userMessageText: protocolMessageCommand[2]))
            // message.txt に追加
            let path = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask)[0].appendingPathComponent(self.uploadfname)
            do {
                try self.appendUserMessage(
                    message: UserMessageItem(userMessageID: newID, userMessageText: protocolMessageCommand[2]),
                    to: path
                )
            } catch {
                print("append error:", error)
            }
            
            self.messageIDLock.unlock()
            self.bleCentral.log.addItem(logText: "addItemExternal append, \(protocolMessageCommand[1]), \(protocolMessageCommand[2]) ")
            
            if (self.movingEdgeFlag) {
                sendMessage(userMessageID:newID, userMessageText:protocolMessageCommand[2])
            }
            
            
            // ここで split されたデータの処理をする 2024/5/16
            var regex2 = /-(?<sequence>\w*)\((?<hop>\d*)\)/ // hopの回数も分かるので、上の処理を直せるが、とりあえずそのまま
            var match2 = newID.firstMatch(of: regex2) // recUserMessageIDでも同じ
            if match2 == nil {
                print("illegal message ID ")
                self.bleCentral.log.addItem(logText: "illegal message ID in addItemExternal")
                
                // ここで必要なはずなので追加 2024/7/24
                self.messageIDLock.unlock()
                
                return
            }
            let seq = match2!.sequence
            let last = String(seq.suffix(1))
            
            if last=="L" {
                print("LAST")
                let n = Int(seq.prefix(seq.count-1))!
                if n==0 {
                    print("not split")
                } else {
                    print("last of split data ",newID)
                    // mergeSplitData(messageID: newID)
                }
                
            }
            // 到達の順番が変わることがあるので、とにかく毎回チェックする
            self.mergeSplitData(messageID: newID)
            
            // append直後に移動 2024/7/24
            //self.messageIDLock.unlock()
            //self.bleCentral.log.addItem(logText: "addItemExternal append, \(protocolMessageCommand[1]), \(protocolMessageCommand[2]) ")
            
            // command かどうか確認 2024.2.19 commandなら実行
            self.MessageCommandCheck(MessageCommand: protocolMessageCommand[2])
            
            // 画面表示を変えないとredrawできないので、姑息な手段で書き換える。
            if self.pStatus == "|" {
                self.pStatus="-"
            } else {
                self.pStatus="|"
            }
        }
    }
        
        // 思ったより長くなっている
        func mergeSplitData(messageID: String) {
            var lastfound = false
            logaddItem(logText: "mergeSplitData called messageID=\(messageID)")

            print("mergeSplitData with ", messageID)
            var regex3 = /^(?<IDbody>.*)-(?<sequence>\w*)\((?<hop>\d*)\)$/

            // 渡されたIDから、共通部分とｎを知る
            var match3 = messageID.firstMatch(of:regex3)
            var IDbody = ""
            var sequence = ""
            var last = ""
            var n = 0
            if let match3 {
                print(match3.IDbody)
                print(match3.sequence)
                IDbody = String(match3.IDbody)
                sequence = String(match3.sequence)
                last = String(sequence.suffix(1))

            }
            print(IDbody)
            print(sequence)
            print(last)
  
            // 毎回チェックにしたので、ラストでなくても処理する
            /*
            if last != "L" { // 関数を呼ぶ前にチェックしているのでここにはこないはず
                print("not LAST error")
                return
            }
             */
            if last != "L" {
                n = Int(sequence) ?? 0
            } else {
                n = Int(sequence.prefix(sequence.count-1))!
            }
            print("n=",n)
            
            // n+1個入る配列を準備する
            var UserMessageList : [UserMessageItem?] = Array(repeating: nil, count: n+1)


            var itemCount = 0 // 見つかった数
            for userMessageItem in self.userMessageList {
                let userMessageItemID = userMessageItem.userMessageID
                print(userMessageItemID)
                let matchItem = userMessageItemID.firstMatch(of:regex3)
                var ItemIDbody = ""
                var ItemSequence = ""
                if let matchItem {
                    print(matchItem.IDbody)
                    print(matchItem.sequence)
                    ItemIDbody = String(matchItem.IDbody)
                    ItemSequence = String(matchItem.sequence)
                }
                //print(ItemIDbody)
                if IDbody == ItemIDbody { // 分割のパートを見つけた時
                    print("find the part of split")
                    
                    last = String(ItemSequence.suffix(1))
                    var ItemSequenceNum = -1
                    if last=="L" {
                        lastfound = true
                        ItemSequenceNum = Int(ItemSequence.prefix(ItemSequence.count-1))!
                    } else {
                        ItemSequenceNum = Int(ItemSequence)!
                    }
                    print(ItemSequenceNum)
                    // 配列の大きさ（n+1)、indexはnまで、を超えていたら拡張する
                    if ItemSequenceNum >= n+1 {
                        UserMessageList += Array(repeating: nil, count: ItemSequenceNum-n)
                        n = ItemSequenceNum
                    }
                    // 同じメッセージがくる場合がある
                    // それ自体がバグではあるが、ここでも避ける 2024/7/24
                    if UserMessageList[ItemSequenceNum] == nil {
                        UserMessageList[ItemSequenceNum] = userMessageItem
                        
                        itemCount = itemCount + 1
                    }
                }
                if itemCount >= n+1 {
                    break
                }
            }
                
            // ここで itemCount が n+1 だったら、全部見つかった。はず。
            // と思ったけど、Lが来ていない状態で、すべて見つかる場合もある。
            // その時は、base64のdecodeで失敗するので、そのまま return するはず
            // と思ったが、成功する時もあるらしい。なので、lastfoundを確認する
            if (itemCount >= n+1) && lastfound {
                logaddItem(logText: "mergeSplitData find all splits (maybe)")

                print("find all split")
                var AllMessage = ""
                for eachItem in UserMessageList {
                    if eachItem != nil {
                        AllMessage.append(contentsOf: eachItem!.userMessageText)
                    } else { // 1個でもなかったら return する. ここにはこないはず？
                        print("internal error")
                        return
                    }
                }
                //print(AllMessage)
                
                let reg = /^\[base64,fname=(?<fname>[^\]]*)\](?<data>.*)$/
                let match = AllMessage.firstMatch(of: reg)
                if let res = match { // 見つかった場合
                    //print(res.fname)
                    //print(res.data.count)
                    let base64data = String(res.data.utf8)
                    //print(base64data)
                    let fname = String(res.fname)
                    
                    let decodebase64String = Data(base64Encoded: base64data!)
                    if decodebase64String == nil {
                        return
                    }
                    //print(decodebase64String!)
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let decodepath = fname
                    let decodefileURL = documentsURL.appendingPathComponent(decodepath)
                    //print(decodefileURL)
                    
                    //DispatchQueue.global(qos: .userInitiated).async {
                    DispatchQueue.global(qos: .default).async { // warningが出るので、変えてみた。2024/5/30
                        print("anync write")
                        do {
                            try decodebase64String!.write(to: decodefileURL)
                        } catch {
                            print("write decoded data error")
                        }
                        print("write finish")
                        self.bleCentral.log.addItem(logText: "mergeSplitData finished for \(messageID)")
                    }
                } else {
                    // base64 がない場合
                    // ファイルでもないのに文字数が多くなるとここにくる
                    // healthcare data だと、WatchOS側のMTUが小さい（240）ので、ヘルスケアデータが分割される
                    // 今まで処理がなかったのを発見した 2025/5/25
                    // NAMI同志の場合は、何もしなくても良い（同じメッセージが送られるだけだから）
                    // 自分が edge の場合は、マージしたデータを BBS に送るようにする
                    //     func addItem(userMessageText: String) {
                    // からロジックを持ってくる
                    
                    if (self.movingEdgeFlag) {
                        let userMessageText = AllMessage
                        let userMessageID = IDbody + "-0L(0)"
                        //print(userMessageText)
                        DispatchQueue.main.async {
                            sendMessage(userMessageID:userMessageID, userMessageText:userMessageText)
                        }
                    }
                }

            } else {
                print("something missing")
                // 見つからなかった。エラー処理が必要か？
                // エラーの原因が不明なので、対応方法も不明
                // 全部揃ってから、手作業でマージできる方法を残しておくのが良いかも
                logaddItem(logText: "mergeSplitData something is missing for \(messageID)")
                for i in 0..<n+1 { // 実際には n は最後なので抜けていることはない
                    if UserMessageList[i] == nil {
                        print("UserMessageList[",i,"] is missing")
                    }
                }
            }
        }
        
        func MessageCommandCheck(MessageCommand: String) {
            //print(MessageCommand)
            // MessageCommand = "command,wifi,<SSID>,<PASS>,<edgeIP>"
        
            let commands:[String] = MessageCommand.components(separatedBy:",")
            //print(commands)
            
            if commands[0]=="command" {
                if commands.count == 1 {
                    print("command syntax error: \(commands)")
                    logaddItem(logText: "command syntax error: \(commands)")
                } else {
                    if commands[1]=="wifi" {
                        if !user.EdgeMode {
                            if commands.count != 5 {
                                print("command[wifi] syntax error: \(commands)")
                                logaddItem(logText: "command[wifi] syntax error: \(commands)")
                            } else {
                                let ssid = commands[2]
                                let pass = commands[3]
                                let edgeIP = commands[4]
                                self.wifi.edgeIP = edgeIP
                                
                                print(ssid, pass, edgeIP, self.wifi.edgeIP)
                                
                                self.wifi.connect(ssid: ssid, password: pass, edgeIP: edgeIP)
                            }
                        }
                    }
                }
            }
        }
        
        // wifitestからコピペ、引数だけ修正
        func obsolete_connect(ssid:String, pass:String) {
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
    
    // messageのセーブ・リストア機能
    
    func ReadMessagefromFile(filename: String) {
        print(filename)
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(filename)
        print(path)
        let decoder = JSONDecoder()
        
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let text = try String(contentsOf: path, encoding: .utf8)
                let lines = text.split(separator: "\n")

                for line in lines {
                    let data = Data(line.utf8)
                    let message = try decoder.decode(JsonMessageItem.self, from: data)
                    //print(message.userMessageID)
                    //print(message.userMessageText)
                    self.userMessageList.append(
                        UserMessageItem(userMessageID: message.userMessageID, userMessageText: message.userMessageText)
                    )

                }
                
                
                
            } catch {
                print("read error: \(error)")
            }
        } else {
            print("file not found \(path)")
        }
        
    }
    
    func WriteMessagetoFile(filename: String) {
        print(filename)
        print(self)
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(filename)
        let encoder = JSONEncoder()
        //var jsonArray:[Data] = []
        var jsonArray : [Dictionary<String, Any>] = []
        for userMessageItem in self.userMessageList {
            //print(userMessageItem.userMessageID)
            //print(userMessageItem.userMessageText)
            
            do {
                try appendUserMessage(
                    message: userMessageItem,
                    to: path
                )
            } catch {
                print("append error:", error)
            }
//            print(userMessageItem.user)
/*            var jsonDic = Dictionary<String, Any>() // キーString、値AnyのDictionary
            jsonDic["userMessageID"] = userMessageItem.userMessageID
            jsonDic["userMessageText"] = userMessageItem.userMessageText

            //print(jsonDic)
            jsonArray.append(jsonDic)
 */
        }
        /*
        print(jsonArray)
        let strarr = try! JSONSerialization.data(withJSONObject: jsonArray,options:[])
        print(String(bytes:strarr, encoding: .utf8)!)
        let str:String = String(bytes:strarr, encoding: .utf8) ?? "JSON error"
        print(str)
         
        
        if let stringData = str.data(using: .utf8) {
            try? stringData.write(to: path)
        }
        */

    }

    func appendUserMessage(
        message: UserMessageItem,
        to path: URL
    ) throws {

        let jsonObject: [String: Any] = [
            "userMessageID": message.userMessageID,
            "userMessageText": message.userMessageText
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "JSONEncodeError", code: -1)
        }

        let line = jsonString + "\n"
        let lineData = line.data(using: .utf8)!


        if FileManager.default.fileExists(atPath: path.path) {
            let fileHandle = try FileHandle(forWritingTo: path)
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: lineData)
            try fileHandle.close()
        } else {
            try lineData.write(to: path)
        }
    }


}


// ユーザが見えるメッセージと、下位のプロトコルのメッセージがごっちゃになっている
// 上位-> usermessage、下位->protocolmessageに修正する
// Transfer １つにつき、インスタンスを使う
// 実際には、ほとんど１つしか使わないと思うが、複数できるようにしておかないと
// 後で問題が発生するかもしれないので、そういう感じにしておく。
var transferCList: [TransferC] = []
var maxmessagestosend = 200 // 5->500 ハングしたら減らす 50

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
        //let queue = DispatchQueue.global(qos:.userInitiated)
        // Warningが出るので、QoSクラスを変えてみた。あっているかどうか不明 2024/5/30
        queue.async {
            print("transfer.start is called")
            Task { @MainActor in
                self.bleCentral.log.addItem(logText: "in transferC.start() before lock, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
            }
            //self.loopLock.lock() // この lock は何のため？ -> CtoP の時に、転送途中の処理を待つため。
            
            if (self.loopLock.lock(before:Date().addingTimeInterval(1))==false) {
                // エラー時の処理
                // C を stop した直後にここにくると、ここでlockに失敗するはず（実際には発生していない）
                
                self.bleCentral.log.addItem(logText:"TransferC.start loopLock.lock() failed")
                            
            } else { // 正常時の処理
                
                
                //self.bleCentral.log.addItem(logText: "in transferC.start() after lock, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
                Task { @MainActor in
                    self.bleCentral.log.addItem(logText: "C: MessageLoop start, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
                }

                // send BEGIN0
                self.bleCentral.writeData("BEGIN0\n", peripheral: self.connectedPeripheral)
                if (self.bleCentral.readfromP(peripheral: self.connectedPeripheral) == true) { // 失敗だったら disconnect に行く
                    
                    // とりあえず、readが出来るかの確認
                    // 値をどうやってもらうか？
                    let returnProtocolMessage = self.getProtocolMessage()
                    print("returnMessage \(returnProtocolMessage)")
                    
                    if (returnProtocolMessage != "getProtocolMessageTimedOut") { // timeoutの時はエラーにする
                        // send message loop
                        if (self.sendMessageLoop() == true) {
                            
                            // receive message loop
                            self.receiveMessageLoop()
                        }
                    }
                    // １回のメッセージのやりとりは終了したので、終了処理をする。
                    
                    //self.loopLock.unlock()
                }
                
                // １回のメッセージのやりとりは終了したので、終了処理をする。
                
                self.loopLock.unlock()
                
            }
            
            // disconnect
            // 変数の初期化（connectedPeripheral だけで良いのか？）
            self.valid = false
            self.bleCentral.centralManager.cancelPeripheralConnection(self.connectedPeripheral)
            //self.bleCentral.connectedPeripheral = nil

            print("end of TransferC.start.async 1")
            print("skip log in TransferC.start.async 1")
            //self.bleCentral.log.addItem(logText: "end of TransferC.start.async 1")

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
    
    func logaddItem(logText: String) {
        //Task { @MainActor in
            self.bleCentral.log.addItem(logText: logText)
        //}
    }
    func sendMessageLoop()->Bool{
        print("sendMessageLoop")
        logaddItem(logText:"C: enter sendMessageLoop")

        for userMessage in bleCentral.userMessage.userMessageList.suffix(maxmessagestosend) { // たくさん送らない 2026/3/19
            //print(userMessage.userMessageID,userMessage.userMessageText)
            
            // Time check
            if messageIDTimeCompare(messageID:userMessage.userMessageID, limit: availableperiod)==false {
                logaddItem(logText:"C:message \(userMessage.userMessageID) is too old")
                continue
            }
            
            // hop 回数 動作確認はしていない
            let regex = /\((\d+)\)/

            let match = userMessage.userMessageID.firstMatch(of: regex)
            if match == nil {
                print("illeagal userMessageID(hop)")
                logaddItem(logText: "illeagal userMessageID(hop) in sendMessageLoop")
                continue
            }
            let originalhopStr = match?.1 ?? "0"
            let hop = Int(match?.1 ?? "0") ?? 0
            print(hop)
            if hop > 10 {
                print("too many hops ")
                logaddItem(logText: "too many hops in sendMessageLoop")
                continue
            }
            
            
            // send IHAVE
            self.bleCentral.writeData("IHAVE\n\(userMessage.userMessageID)\n", peripheral: self.connectedPeripheral)
            if (self.bleCentral.readfromP(peripheral: self.connectedPeripheral) != true) { // read
                print("TransferC: readfromP failed")
                break
            }
            // 値をもらう
            let returnProtocolMessage = self.getProtocolMessage()
            print("returnMessage \(returnProtocolMessage)")
            if (returnProtocolMessage == "getProtocolMessageTimedOut") {
                print("sendMessageLoop: getProtocolMessageTimedOut")
                return false
            }
            // INEEDかどうかの確認
            let receiveCommand = getCommand(protocolMessageText: returnProtocolMessage)
            if receiveCommand[0] == "INEED" {
                print("receive INEED \(receiveCommand[1])")
                let sendMessage = "MSG\n" + userMessage.userMessageID + "\n" + userMessage.userMessageText // + "\n" // Do I need the last '\n' ?
                self.bleCentral.writeData(sendMessage, peripheral: self.connectedPeripheral)
                print("C send MSG")
                if (self.bleCentral.readfromP(peripheral: self.connectedPeripheral) != true) {
                    print("TransferC: readfromP failed 2")
                    break
                }
                // 値をもらう
                let returnProtocolMessage2 = self.getProtocolMessage()
                print("returnMessage for MSG \(returnProtocolMessage2)")
                if (returnProtocolMessage2 == "getProtocolMessageTimedOut") {
                    print("sendMessageLoop: getProtocolMessageTimedOut 2")
                    return false
                }

            } else { // should be ACK
                print("receive \(receiveCommand)")
                if receiveCommand[0] != "ACK" {
                    print("sendMessageLoop: command error")
                    return false
                }
            }


        }
        print("sendMessageLoopEnd")
        return true
    }
    
    func receiveMessageLoop() {
        print("receiveMessageLoop")
        logaddItem(logText: "C: enter receiveMessageLoop")
        
        // send BEGIN1
        self.bleCentral.writeData("BEGIN1\n", peripheral: self.connectedPeripheral)
        
        while true {
            if (self.bleCentral.readfromP(peripheral: self.connectedPeripheral) != true) {
                print("TransferC: readfromP error 3")
                return
            }
            // 値をもらう
            let returnProtocolMessage = self.getProtocolMessage()
            print("receiveMessageLoop \(returnProtocolMessage)")
            if (returnProtocolMessage == "getProtocolMessageTimedOut") {
                print("receiveMessageLoop: getProtocolMessageTimedOut")
                return
            }

            // END1 かどうかの確認
            let receiveCommand = getCommand(protocolMessageText: returnProtocolMessage)
            switch receiveCommand[0] {
            case "END1":
                print("end of receiveMessageLoop")
                logaddItem(logText: "C: receiveMessageLoop END1, \( self.connectedPeripheral.name ?? "unknown"), \( self.connectedPeripheral.identifier.uuidString) ")
                return
            
            case "IHAVE":
                print("C receive IHAVE \(receiveCommand[1])")
                logaddItem(logText: "C: receiveMessageLoop IHAVE \(receiveCommand[1])")
                
                var ihave: Bool = false
                for userMessage in bleCentral.userMessage.userMessageList {
                    // hopを消す
                    let ID0 = userMessage.userMessageID
                    let arr0:[String] = ID0.components(separatedBy: "(")
                    let ID0nohop = arr0[0]

                    let ID1 = receiveCommand[1]
                    let arr1:[String] = ID1.components(separatedBy: "(")
                    let ID1nohop = arr1[0]
                    
                    if ID0nohop == ID1nohop {
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
                logaddItem(logText:"C: receiveMessageLoop MSG, \(receiveCommand[1])")

                self.bleCentral.userMessage.addItemExternal(protocolMessageCommand: receiveCommand)
                // for debug
                // only send ACK
                self.bleCentral.writeData("ACK\n", peripheral: self.connectedPeripheral)

                
            default:
                print("receiveMessageLoopError \(receiveCommand[0])")
                logaddItem(logText:"C: receiveMessageLoop Error, \(receiveCommand[0])")
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
        logaddItem(logText:"appendMessage before signal")
        self.semaphore.signal()
        logaddItem(logText:"appendMessage after signal")
    }
    
    // 本当はロックを使って、正しいメッセージを読むべき
    // wait()を入れると全体が止まってしまう
    // start() を async にした。とりあえず、動いている
    func getProtocolMessage()-> String {
        switch (self.semaphore.wait(timeout: .now() + 3)) { // 30 -> 3
        case .success:
            logaddItem(logText:"wait in getProtocolMessage succeed, \( self.connectedPeripheral.name ), \( self.connectedPeripheral.identifier.uuidString ) ")
            
        case .timedOut:
            logaddItem(logText:"wait in getProtocolMessage failed, \( self.connectedPeripheral.name ), \( self.connectedPeripheral.identifier.uuidString ) ")
            /* 読み飛ばしたメッセージは、もう読まない 2026/4/1 */
            self.protocolMessageIndex = self.protocolMessageIndex + 1
            
            return("getProtocolMessageTimedOut") // 上位でこの文字列を見ているので変更しない
            
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
    var sendMessageList:[UserMessageItem] = [] // begin1の後に送るリスト。
    
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
    
    func logaddItem(logText: String) {
        //Task { @MainActor in
            self.blePeripheral.log.addItem(logText:logText)
        //}
    }
    
    func begin0(){
        logaddItem(logText:"transferP.begin0,")
        sendMessageList = blePeripheral.userMessage.userMessageList.suffix( maxmessagestosend)
//        for userMessage in blePeripheral.userMessage.userMessageList.suffix(2 * maxmessagestosend) { // たくさん送らない

        write2C(writeData: "ACK\n")
    }
    
    func ack() {
        write2C(writeData: "ACK\n")
    }
    
    func write2C(writeData: String) -> Bool {
        // messageをキュー（？）入れる
        // read request が来たら読める（はず）
        // notify する？
        
        // 本当はここでLockをかけるべき
        self.protocolMessageQueue.append(writeData)
        self.protocolMessageSemaphore.signal()
        // このロジックは合っているのか？
        // ここで実行時のwarningが出るので、デバッグする 2024/5/31
        print("QoS debug (wait)", Thread.isMainThread, Thread.current, Thread.current.qualityOfService.rawValue)
        if Thread.current.qualityOfService == QualityOfService.userInitiated {
            print("QoS : user initiated")
        }

        print("wait for 3 seconds in write2C")
        switch(self.protocolMessageSyncSemaphore.wait(timeout: .now() + 3)) { //  本質的には変えてないけど、30を3に減らしたので、もしここで待っているなら少し改善する
        case .success:
            print("success in write2C")
            return true // 2026.4.2
            
        case .timedOut:
            print("timedout in write2C")

            logaddItem(logText:"timedOut in write2C")
            return false // 2026.4.2 Timeoutしていたら、上位でエラー処理に行くようにする。
            
        }

    }
    
    func appendReceiveMessage(receiveProtocolMessage:String) {
        // 本当はここでLockをかけるべき
        self.receiveMessageQueue.append(receiveProtocolMessage)
        self.receiveMessageSemaphore.signal()
    }
    
    func getProtocolMessageP()-> String {
        print("before protocol wait") // ここでブロックしてしまう
        switch (self.protocolMessageSemaphore.wait(timeout: .now() + 3)) { // どこで書いている？ // 30 -> 3
        case .success:
            print("success in getProtocolMessageP")
            logaddItem(logText: "success to wait in getProtocolMessageP")
        case .timedOut:
            print("timedOut in getProtocolMessageP")
            logaddItem(logText: "fail to wait in getProtocolMessageP")
            
            /* 読み飛ばしたメッセージは、もう読まない 2026/4/1 */
            self.protocolMessageIndex = self.protocolMessageIndex + 1

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
        switch (self.receiveMessageSemaphore.wait(timeout: .now() + 3)) { // どこで書いている？ // 30 -> 3
        case .success:
            print("success in getReceiveProtocolMessage")
            logaddItem(logText: "success to wait in getReceiveProtocolMessage")
        case .timedOut:
            print("timedOut in getReceiveProtocolMessage")
            logaddItem(logText: "fail to wait in getReceiveProtocolMessage")
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
        logaddItem(logText:"transferP.ihave, \(userMessageID),")
        
        for userMessage in blePeripheral.userMessage.userMessageList {
            // hopを消す
            let ID0 = userMessage.userMessageID
            let arr0:[String] = ID0.components(separatedBy: "(")
            let ID0nohop = arr0[0]

            let ID1 = userMessageID
            let arr1:[String] = ID1.components(separatedBy: "(")
            let ID1nohop = arr1[0]

            if ID0nohop == ID1nohop {
                print("P already has \(userMessageID)")
                write2C(writeData: "ACK\n")
                return
            }
        }
        
        print("P doesn't have \(userMessageID)")
        write2C(writeData: "INEED\n\(userMessageID)\n")

    }
    
    func begin1() {
        logaddItem(logText:"transferP.begin1,")

        //for userMessage in blePeripheral.userMessage.userMessageList.suffix(2 * maxmessagestosend) { // たくさん送らない
        for userMessage in sendMessageList { // sendmessagelist は *2 はない
            print("I(P) have \(userMessage.userMessageID)")
            
            // Time check
            if messageIDTimeCompare(messageID:userMessage.userMessageID, limit: availableperiod)==false {
                logaddItem(logText:"P:message \(userMessage.userMessageID) is too old")
                continue
            }
            
            // send IHAVE
            if (write2C(writeData: "IHAVE\n\(userMessage.userMessageID)\n") != true) {
                // errorだった break するように修正 2026/4/6
                print("write2C in TransferP.begin1() write error")
                logaddItem(logText:"P: write2C in TransferP.begin1() write error")
                break
            }
            
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
                // errorだった break するように修正 2026/4/6
                print("P: protocol error in TransferP.begin1()")
                logaddItem(logText:"P: protocol error in TransferP.begin1()")
                break

            }
        }
        
        write2C(writeData: "END1\n")
        logaddItem(logText:"P: MessageLoop end")


    }
    
    func begin1_sendmsg(userMessageID: String){
        print("begin1_sendmsg \(userMessageID)")
        logaddItem(logText:"transferP.begin1_sendmsg \(userMessageID),")
    
        for userMessage in blePeripheral.userMessage.userMessageList {
            if userMessage.userMessageID == userMessageID {
                let sendMessage = "MSG\n" + userMessage.userMessageID + "\n" + userMessage.userMessageText
                write2C(writeData: sendMessage)
                print("P send MSG")
                return
            }
        }
        
        print("Protocol error in begin1_sendmsg")
        logaddItem(logText:"Protocol error in begin1_sendmsg,")

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

