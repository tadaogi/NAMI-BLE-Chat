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

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                HStack {
                    Text("UserMessages")
                    Spacer()
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
                    print(match.0)
                    print(match.message)
                    message = String(match.message)
                }
                tmptext = "[\(usrID)] " + message
            } else {
                tmptext = ""
            }
        }
        return tmptext
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        /// 以下の行を追加
        ForEach(["iPhone SE (2nd generation)", "iPhone 6s Plus", "iPad Pro (9.7-inch)"], id: \.self) { deviceName in
            MessageView()
                .environmentObject(UserMessage())
                .environmentObject(FileID())
                /// 以下の2行を追加
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
