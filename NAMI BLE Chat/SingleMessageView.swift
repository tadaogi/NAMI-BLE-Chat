//
//  SingleMessageView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2024/07/23.
//
//
//  SingleMessageView.swift
//  NAMIMessageTest
//
//  Created by Tadashi Ogino on 2024/07/21.
//

import SwiftUI
import UniformTypeIdentifiers

// もっと簡単な方法があるはずだけど、、、
struct OriginalPhoto: View {
    // 渡される引数の定義
    var filename: String
    var width: Double
    
    @State var fileexist = false
    @EnvironmentObject var wifi: WiFi


    var body: some View {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            
            if fileURL.pathExtension != "" {
                if UTType(filenameExtension: fileURL.pathExtension)!.conforms(to: .image) {
                    AsyncImage(url: fileURL) { image  in
                        
//                        image.framedAspectRatio(contentMode: .fit)
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: width)
                        
                    } placeholder: {
                        ProgressView()
                    }
                    //Text(filename)
                    
                } else if UTType(filenameExtension: fileURL.pathExtension)!.conforms(to: .movie) {
                    Text("movie")
                    
                } else {
                    Image("UnKnown256")
                        .resizable()
                        .frame(width:64, height:64)
                }
            } else {
                Image("UnKnown256")
                    .resizable()
                    .frame(width:64, height:64)
            }
        } else {
            if fileRequest() {
                
            }
            Image("NoImage256")
                    .resizable()
                    .frame(width:64, height:64)

            //Text("not exist")
        }

    }
        
    func fileRequest() -> Bool {
        wifi.fileRequest(fname: filename)
        return true
    }

    
}

struct SingleMessageView: View {
    // 渡される引数の定義
    //var userMessageText: String
    var userMessageData: MsgData
    
    @EnvironmentObject var params: Params
    @EnvironmentObject var userMessage : UserMessage


    
    var body: some View {
        GeometryReader { proxy in
            let dialogWidth = proxy.size.width * 0.9
            let dialogHeight = proxy.size.height * 0.9
            
            VStack {
                Spacer()
                HStack(alignment: .center) {
                    Spacer()
                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: dialogWidth,
                                   height: dialogHeight)
                        VStack {
                            Text("["+userMessageData.userName+"]")
                            Text("DateTime:"+userMessageData.dateTime)
                            //Text("Single Message View")
                            HStack(spacing: 5) {
                                Spacer()
                                Text(getPremessage(message: userMessageData.userMessageText))
                                Spacer()
                            }

                            //Text("Photo must be here")
                            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let filename = getFilename(message: userMessageData.userMessageText)
                            if filename != "" {
                                OriginalPhoto(filename: filename, width: dialogWidth*0.9)
                            } else {
                            }


                            HStack(spacing: 5) {
                                Spacer()
                                Text(getPostmessage(message: userMessageData.userMessageText))
                                Spacer()
                            }
                            Button("close") {
                                params.showmap = false
                                //showMsgDialog = false
                            }
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
    
    
    func getPremessage(message: String) -> String {
        var premessage = message
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            premessage = String(match.1)
        }
        print(userMessage.debugMessageFlag)
        if !userMessage.debugMessageFlag {
            // [GPS,xxx,xxx] は表示しない
            let reg = /^\[[^\]]*\](?<message>.*)$/
            if let match = premessage.firstMatch(of: reg) {
                print(match.0)
                print(match.message)
                premessage = String(match.message)
            }
        }
        return premessage
    }
    
    func getFilename(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.2)
        } else {
            return ""
        }
    }
    func getPostmessage(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.3)
        } else {
            return ""
        }
    }
    
    func DocumentPhotoPath(filename: String) -> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)

        return fileURL.path
    }

}

#Preview {
    SingleMessageView(userMessageData: MsgData())
}
