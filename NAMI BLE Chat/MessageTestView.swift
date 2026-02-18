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
            Text("Moving Edge Setting")
            HStack {
                Text("moving edge")
                Toggle(isOn: $userMessage.movingEdgeFlag) {
                    EmptyView()
                }
            }
            /*
            HStack {
                Text("Area")
                TextField("",
                          text: $user.area,
                      onCommit: {
                    print("area:\(user.area)")
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            */
            HStack {
                Text("lat")
                TextField("",
                          value: $user.latitude,
                    format: .number)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("lon")
                TextField("",
                          value: $user.longitude,
                    format: .number)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            }

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
            Text("DocumentPath:")
            Text("\(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path)")
                .frame(width:300)
//                .textSelection(.enabled)
//            Text("Copy DocumentPath")
            .contextMenu(ContextMenu(menuItems: {
              Button("Copy", action: {
                  UIPasteboard.general.string =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
              })
            }))
            HStack {
                Button (action: {
                    print("write to file button")
                    userMessage.WriteMessagetoFile(filename: uploadfname)
                    //WriteMessagetoFile(filename: uploadfname)
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
                    userMessage.ReadMessagefromFile(filename: uploadfname)
                    //ReadMessagefromFile(filename: uploadfname)
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
                userMessage.uploadfname = uploadfname
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
            userMessage.movingEdgeFlag = UserDefaults.standard.object(forKey: "movingEdgeFlag") as? Bool ?? false
//            userMessage.area = UserDefaults.standard.string(forKey: "area") ?? "official"
            //@Published var latitude: Double = 35.31937839258047 // 鎌倉市役所
            //@Published var longitude: Double = 139.5472510462028

            user.latitude = UserDefaults.standard.double(forKey: "latitude")
            if user.latitude == 0 {
                user.latitude = 35.31937839258047
            }
            user.longitude = UserDefaults.standard.double(forKey: "longitude")
            if user.longitude == 0 {
                user.longitude = 139.5472510462028
            }
            uploadfname = UserDefaults.standard.string(forKey: "uploadfname") ?? "message.txt"
            userMessage.uploadfname = uploadfname


        })
        .onDisappear(perform: {
            print("disappear")
            UserDefaults.standard.set(userMessage.movingEdgeFlag, forKey: "movingEdgeFlag")
            movingEdgeFlag = userMessage.movingEdgeFlag
//            UserDefaults.standard.set(userMessage.area, forKey: "area")
            UserDefaults.standard.set(user.latitude, forKey: "latitude")
            UserDefaults.standard.set(user.longitude, forKey: "longitude")
            UserDefaults.standard.set(uploadfname, forKey: "uploadfname")
            // 以下をやると、現在の値に上書きされてしまう。
            /*
            if globalgps != nil {
                globalgps!.lastlatitude = user.latitude
                globalgps!.lastlongitude = user.longitude
            }
            */
        })
    }
    
    func OldReadMessagefromFile(filename: String) {
        print(filename)
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(filename)
        print(path)
        
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let data = try Data(contentsOf: path)
                // 使用処理
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

                
            } catch {
                print("read error: \(error)")
            }
        } else {
            print("file not found \(path)")
        }
        // 以下のロジックだと、ファイルが存在しないとアプリが死ぬので上に修正した
        /*
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
         */
        
    }

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
                    print(message.userMessageID)
                    print(message.userMessageText)
                    userMessage.userMessageList.append(
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

    func OldWriteMessagetoFile(filename: String) {
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

            print(jsonDic)
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
        MessageTestView(userMessage: UserMessage(store: MessageStore()))
            .environmentObject(User())
    }
}
