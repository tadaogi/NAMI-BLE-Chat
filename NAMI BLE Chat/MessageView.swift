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
    @State var PhotoSheet: Bool = false
    @State var edgeIP: String = "10.9.153.163"
    @State private var active = false
    @EnvironmentObject var fileID: FileID

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
                        let tmptext = messageitem.userMessageID+","+messageitem.userMessageText
                        /*
                        Text(.init(tmptext))
                            .padding([.leading], 15)
                         */
                        Text(.init(setmessage(messageitem: messageitem)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.leading], 5)
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
                        PhotoShow(edgeIP: $edgeIP)
                        
                    }

                
                HStack {
                    Text("Comment")
                    Button (action: {
                        print("photo")
                        PhotoSheet.toggle()
                    }) {
                        Text("Photo")
                    }
                    .sheet(isPresented: $PhotoSheet, onDismiss: didDismiss) {
                        PhotoView(edgeIP: $edgeIP)
                        
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
                        self.userMessage.addItem(userMessageText: inputmessage)
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
            let arr:[String] = messageitem.userMessageID.components(separatedBy: "-")
            let usrID = arr[2]
            tmptext = "[\(usrID)] " + messageitem.userMessageText
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
