//
//  MessageView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import SwiftUI

struct MessageView: View {
    @State private var inputmessage = ""
    @EnvironmentObject var userMessage : UserMessage
    @State private var PhotoSheet: Bool = false
    //@State var edgeIP: String = "10.9.153.163" // この値が PhotoView で使われる
    @EnvironmentObject var wifi: WiFi
    @State private var active = false
    @EnvironmentObject var fileID: FileID
    @EnvironmentObject var user : User
    @EnvironmentObject var log : Log
    
    @State private var ShowOfficial = true
    @State private var ShowLocal = true
    
    @EnvironmentObject var server: WebServerManager
    
    @StateObject private var dialog = Dialog.shared
    private var crypt = NAMICrypt() // 暗号化・復号化用のクラス
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                HStack {
                    Text("UserMessages")
                    Spacer()
                    Button(action: {
                        ShowOfficial.toggle()
                    }) {
                        Text("Official")
                            .padding(5)
                            .frame(width: 90, height: 19)
                            .background(ShowOfficial ? Color("lightBackground") : Color("lightGray"))
                            .foregroundColor(ShowOfficial ? Color.black : Color.gray)
                    }
                    Button(action: {
                        ShowLocal.toggle()
                    }) {
                        Text("Local")
                            .padding(5)
                            .frame(width: 90, height: 19)
                            .background(ShowLocal ? Color("lightBackground") : Color("lightGray"))
                            .foregroundColor(ShowLocal ? Color.black : Color.gray)

                    }
                    Text(userMessage.pStatus)
                }
                
                ScrollView(.vertical,showsIndicators: true) {
                    // これがないと、最初に書いたテキストの幅に固定されてしまう
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                    ForEach(self.userMessage.userMessageList, id: \.code) { messageitem in
                        //HStack {
                        /*
                        var tmptext=""
                        if userMessage.debugMessageFlag {
                            tmptext = messageitem.userMessageID+","+messageitem.userMessageText
                        } else {
                            tmptext = messageitem.userMessageText
                        }
                         */
                        //let tmptext = messageitem.userMessageID+","+messageitem.userMessageText
                        /*
                        Text(.init(tmptext))
                            .padding([.leading], 15)
                         */
                        
                        var ShowFlag = true
                        if messageitem.userMessageText.contains("#official") {
                            if ShowOfficial {
                                MyMessage(message: setmessage(messageitem: messageitem), active: $active)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding([.leading], 5)
                                    .onTapGesture {
                                        print("tap")
                                        tapAction(messageitem: messageitem)
                                    }
                                // 行間が狭すぎるので、以下を入れた
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(minWidth: 0.0, maxWidth: .infinity)
                                    .frame(height: 0)

                            }
                        } else {
                            if ShowLocal {
                                MyMessage(message: setmessage(messageitem: messageitem), active: $active)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding([.leading], 5)
                                    .onTapGesture {
                                        print("tap")
                                        tapAction(messageitem: messageitem)
                                    }
                                // 行間が狭すぎるので、以下を入れた
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(minWidth: 0.0, maxWidth: .infinity)
                                    .frame(height: 0)

                            }
                        }
                        /*
                        MyMessage(message: setmessage(messageitem: messageitem), active: $active)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.leading], 5)
                            .onTapGesture {
                                print("tap")
                            }
                         
                        // 行間が狭すぎるので、以下を入れた
                        Rectangle()
                            .fill(Color.white)
                            .frame(minWidth: 0.0, maxWidth: .infinity)
                            .frame(height: 0)
                         */

                        // 上に置き換える
                        /*
                        Text(.init(setmessage(messageitem: messageitem)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.leading], 5)
                        */
                        //Spacer()
                        //}
                    }
                    .environment(\.openURL,
                                  OpenURLAction { url in
                        print("FileID clicked \(url.absoluteString)")
                        fileID.name = url.absoluteString
                        active.toggle()
                        //PhotoShow()
                        // ここで PhotoShow() しても表示されない
                        //return .discarded
                        
                        return .handled
                    })
                    
                }.background(Color("lightBackground"))
                    .foregroundColor(Color.black)
                    .sheet(isPresented: $active, onDismiss: didDismiss) {
                        //PhotoShow(edgeIP: $edgeIP)
                        PhotoShow()
                    }

                
                HStack {
                    Text("Comment")
                        .onAppear{
                            print("onAppear in MessageView")
                        } // ここも来る
                    Button (action: {
                        print("photo")
                        PhotoSheet.toggle()
                    }) {
                        Text("Photo")
                    }
                    .sheet(isPresented: $PhotoSheet, onDismiss: didDismiss) {
                        //PhotoView(edgeIP: $edgeIP)
                        PhotoView()
                    }
                    // ここでも動く
                    /*
                     .sheet(isPresented: $active, onDismiss: didDismiss) {
                        PhotoShow()
                        
                    }
                     */

                }
                // HStack(){
                ScrollView(.vertical,showsIndicators: true) {
                    
                    TextField("your message",
                              text: $inputmessage,
                              onCommit: {
                        print("onCommit:\(inputmessage)")
                    })
                }.background(Color("lightBackground"))
                    .foregroundColor(Color.black)
                    .frame(height:50)
                Button (action: {
                    if inputmessage != "" {
                        print("SEND: \(inputmessage)")
                        self.userMessage.addItemWithGPS(userMessageText: inputmessage)
                        inputmessage = ""
                        
                    }
                }) {
                    Text("SEND")
                }
                // server が呼ばれることの確認。OK
                /*
                Button ("debug"){
                    server.debug()
                }
                 */
                //}
            }
            .navigationBarTitle("Message", displayMode: .inline)
            .navigationBarItems(
                trailing:
                    NavigationLink( destination: MessageTestView(userMessage: userMessage)) {
                        Text("NAMI")
                        
                    }
            )
            // ここだと表示されない
            /*
            .navigationDestination(isPresented: $active, destination: {

                PhotoShow()
            })
             */
            .onAppear{
                print("good onAppear") // here
                //userMessage.initUser(user: self.user)
                // これはうまくいかなかった
                
                //print(globalgps?.dummy())
                //print("AAA")
                // この時点で globalgps にアクセスできる事の確認
                // できたのでコメントアウトした
            }
            .alert(dialog.title,
                   isPresented: $dialog.isShowing) {

                Button("OK") {
                    dialog.close()
                }

            } message: {

                Text(dialog.message)
            }


            
        }
        // Macの表示が、「MessageView」と「ContentView]で違うので
        // これをいれると同じになるのか試しにいれる。2024/2/16 OK
        // 以下の行で、iPad と iPhone と同じ表示になる
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    
    func didDismiss() {
        print("didDismiss")
//        inputmessage = "didDismiss"
//        print($edgeIP)
    }
    
    func requestFile() {
        
    }
    
    func setmessage(messageitem: UserMessageItem) -> String {
        var tmptext=""
        if userMessage.debugMessageFlag {
            tmptext = messageitem.userMessageID+","+messageitem.userMessageText
        } else {
            // [GPS で始まっていないメッセージは、データなので、表示しない
            if messageitem.userMessageText.hasPrefix("[GPS,") {
                let arr:[String] = messageitem.userMessageID.components(separatedBy: "-")
                let arr2:[String] = arr[2].components(separatedBy: "(")
                let usrID = arr2[0]
                var message = messageitem.userMessageText
                // [GPS,xxx,xxx] は表示しない
                let reg = /^\[[^\]]*\](?<message>.*)$/
                if let match=messageitem.userMessageText.firstMatch(of: reg) {
                    //print(match.0)
                    //print(match.message)
                    // 多分ここで画面表示されるメッセージが全部printされていた
                    message = String(match.message)
                }
                tmptext = "[\(usrID)] " + message
            } else {
                tmptext = ""
            }
        }
        return tmptext
    }
    
    func tapAction(messageitem: UserMessageItem) {
        print("tapAction")
        print(messageitem.userMessageID)
        print(messageitem.userMessageText)
        
        // ここで merge 処理が必要
        let mergedmessage = mergeSplitDataOnly(messageID: messageitem.userMessageID)
        print(mergedmessage)
        //Dialog.shared.show(mergedmessage)
        // GPSの扱いを考えること
        
        
        /*
        var str = messageitem.userMessageText
        
        str = """
        [GPS,0,0][EncData,
        {
            "nonce": "5y5W4U24BthDUDkm",
            "ciphertext": "Xz2beqTB1WharsndqrDoK6nsVcbLRc01crE07N1sXHJoZPcwBkk63BSh106VeKaXEQ=="
        }]
"""
         */
        print(mergedmessage)
        if let json = extractJSON(from: mergedmessage) {
            print(json)
            let decryptedmessage = crypt.decrypt(inputJSON: json)
            print(decryptedmessage)

            Dialog.shared.show(decryptedmessage)
        }
        // extractJSONに失敗すると Dialog を表示しない。
        
    }
    
    func logaddItem(logText: String) {
        Task { @MainActor in
            self.log.addItem(logText: logText)
        }
    }
    // 思ったより長くなっている
    // Message.swiftからコピーして修正
    // originalはファイルの拡張とかもしているが、mergeのみとする
    func mergeSplitDataOnly(messageID: String)->String {
        var lastfound = false
        logaddItem(logText: "mergeSplitDataOnly called messageID=\(messageID)")

        print("mergeSplitDataOnly with ", messageID)
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
        
        // Lを探す
        for userMessageItem in self.userMessage.userMessageList {
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
                    n = Int(ItemSequence.prefix(ItemSequence.count-1))!
                    break
                }
            }
        }
        print("n=\(n)")
        
        // n+1個入る配列を準備する
        var UserMessageList : [UserMessageItem?] = Array(repeating: nil, count: n+1)


        var itemCount = 0 // 見つかった数
        for userMessageItem in self.userMessage.userMessageList {
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
                    
                    return("merge error: something missing [0]")
                }
            }
            print(AllMessage)
            return(AllMessage)
            

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
            return("merge error: something missing [1]")
        }
    }
    
    func extractJSON(from str: String) -> String? {
        guard let start = str.range(of: "[EncData,") else {
            return nil
        }

        let jsonStart = start.upperBound

        guard let end = str.lastIndex(of: "]") else {
            return nil
        }

        return String(str[jsonStart..<end])
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        /// 以下の行を追加
        ForEach(["iPhone SE (2nd generation)", "iPhone 6s Plus", "iPad Pro (9.7-inch)"], id: \.self) { deviceName in
            MessageView()
                .environmentObject(UserMessage(store: MessageStore()))
                .environmentObject(FileID())
                /// 以下の2行を追加
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
