//
//  MessageTestView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2021/12/29.
//

import SwiftUI
var MessageTestTimer: Timer = Timer()

struct JsonMessageItem: Codable {
    var userMessageID: String
    var userMessageText: String
}

struct MessageTestView: View {
    @EnvironmentObject var user: User
    @State var message_interval: Int = 600
    @State var buttonText = "tmp"
    @State var testflag = false
    @State var userMessage: UserMessage
    
    @State var uploadfname : String = "message.txt"

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
                HStack {
                    Text("debugMessage")
                    Toggle(isOn: $userMessage.debugMessageFlag) {
                        EmptyView()
                    }
                }
            }
            
            HStack {
                Button (action: {
                    print("write to file button")
                    WriteMessagetoFile(filename: uploadfname)
                    //self.log.writeToFile(fname: uploadfname)
                }) {
                    Text("WriteToFile")
                    // テキストのサイズを指定
                        .frame(width: 140, height: 40, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )}
                Button (action: {
                    print("read from file button")
                    ReadMessagefromFile(filename: uploadfname)
                    //self.log.writeToFile(fname: uploadfname)
                }) {
                    Text("ReadFromFile")
                    // テキストのサイズを指定
                        .frame(width: 140, height: 40, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )}
            }

        
            TextField("file name",
                  text: $uploadfname,
                  onCommit: {
                print("uploadfname:\(uploadfname)")
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
        

            
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
    
    func ReadMessagefromFile(filename: String) {
        print(filename)
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: path) else {
            fatalError("error in ReadMessagefromFile")
        }
        
        print(data)
        
        let decoder = JSONDecoder()
        guard let messageData = try? decoder.decode([JsonMessageItem].self, from: data) else {
            fatalError("JSONデコードエラー")
        }
        print(messageData)
        
        userMessage.userMessageList = []
        for messageItem in messageData {
            userMessage.userMessageList.append(
                UserMessageItem(userMessageID: messageItem.userMessageID, userMessageText: messageItem.userMessageText)
            )
        }
        
    }
    
    func WriteMessagetoFile(filename: String) {
        print(filename)
        print(userMessage)
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(filename)
        let encoder = JSONEncoder()
        //var jsonArray:[Data] = []
        var jsonArray : [Dictionary<String, Any>] = []
        for userMessageItem in userMessage.userMessageList {
            print(userMessageItem.userMessageID)
            print(userMessageItem.userMessageText)
//            print(userMessageItem.user)
            var jsonDic = Dictionary<String, Any>() // キーString、値AnyのDictionary
            jsonDic["userMessageID"] = userMessageItem.userMessageID
            jsonDic["userMessageText"] = userMessageItem.userMessageText

            print(jsonDic)
            jsonArray.append(jsonDic)
        }
        print(jsonArray)
        let strarr = try! JSONSerialization.data(withJSONObject: jsonArray,options:[])
        print(String(bytes:strarr, encoding: .utf8)!)
        let str:String = String(bytes:strarr, encoding: .utf8) ?? "JSON error"
        print(str)
        
        if let stringData = str.data(using: .utf8) {
            try? stringData.write(to: path)
        }
        

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
            .environmentObject(User())
    }
}
