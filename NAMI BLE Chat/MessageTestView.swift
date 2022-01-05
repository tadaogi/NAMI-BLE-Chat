//
//  MessageTestView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2021/12/29.
//

import SwiftUI
var MessageTestTimer: Timer = Timer()

struct MessageTestView: View {
    @EnvironmentObject var user: User
    @State var message_interval: Int = 600
    @State var buttonText = "tmp"
    @State var testflag = false
    @State var userMessage: UserMessage
    
    var body: some View {
        ScrollView([.vertical, .horizontal],showsIndicators: true) {
            Text("Message Test Setting")
            VStack {
                HStack {
                    Text("Message Interval")
                    Spacer()
                    TextField("", value: $message_interval, formatter: NumberFormatter(),
                              onCommit: {
                        print("message_interval")
                        print(message_interval)
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                Button (action: {
                    print("action")
                    if ( user.testMessageFlag == false ) {
                        startMessage()
                        buttonText = "Stop"
                        user.testMessageFlag = true
                    } else {
                        stopMessage()
                        buttonText = "Start"
                        user.testMessageFlag = false
                    }
                }) {
                    Text(buttonText)
                    // テキストのサイズを指定
                        .frame(width: 160, height: 40, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )}
            }
            Text("NAMI BLE Chat (ver.\(versiontext))")
                .padding(20)
            Text("NAMI BLE Chat (ver.\(versiontext))")
                .padding(.bottom, 20)
        }
        .onAppear(perform: {
            if user.testMessageFlag {
                buttonText = "Stop"
            } else {
                buttonText = "Start"
            }
        })
        .onDisappear(perform: {
            print("disappear")
        })
    }
    
    func startMessage() {
        print("startMessage")
        MessageTestTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(message_interval), repeats: true, block: {(timer) in
            print("startMessageTimer")
            let date = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = " HH:mm:ss"
            let strDate = formatter.string(from: date)
            userMessage.addItem(userMessageText: "[DEBUG] repeated message at \(strDate)")
        })
    }

    func stopMessage() {
        print("stopMessage")
        MessageTestTimer.invalidate()
    }
}

struct MessageTestView_Previews: PreviewProvider {
    static var previews: some View {
        MessageTestView(userMessage: UserMessage())
    }
}
