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
    
    var body: some View {
        
        VStack(alignment: .leading) {
            Text("UserMessages")

            ScrollView(.vertical,showsIndicators: true) {
                // これがないと、最初に書いたテキストの幅に固定されてしまう
                Rectangle()
                    .fill(Color.white)
                    .frame(minWidth: 0.0, maxWidth: .infinity)
                    .frame(height: 0)
                ForEach(self.userMessage.userMessageList, id: \.code) { messageitem in
                    //HStack {
                    var tmptext = messageitem.userMessageID+","+messageitem.userMessageText
                    Text(tmptext)
                            .padding([.leading], 15)
                    //Spacer()
                    //}
                }
 
            }.background(Color("lightBackground"))
            .foregroundColor(Color.black)
        
            Text("Comment")
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
    }
    
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        /// 以下の行を追加
        ForEach(["iPhone SE (2nd generation)", "iPhone 6s Plus", "iPad Pro (9.7-inch)"], id: \.self) { deviceName in
            MessageView()
                .environmentObject(UserMessage())
                /// 以下の2行を追加
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
