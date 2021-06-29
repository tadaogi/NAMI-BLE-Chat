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
                ForEach(self.userMessage.userMessageList, id: \.code) { messageitem in
                    //HStack {
                        Text(messageitem.userMessageID) // for debug

                        Text(messageitem.userMessageText)
                            .padding([.leading], 15)
                        Spacer()
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
        MessageView()
            .environmentObject(UserMessage())
    }
}
