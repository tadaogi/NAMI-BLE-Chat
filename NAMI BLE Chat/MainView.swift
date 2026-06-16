//
//  MainView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import SwiftUI

struct MainView: View {
//    @State var userMessage: UserMessage
//    @StateObject private var vm: UserMessage
    @EnvironmentObject var userMessage: UserMessage
    
    init() {
        //self.userMessage = userMessage
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("message.txt")
/*
        _userMessage = StateObject(
            wrappedValue: UserMessage(
                store: MessageStore()
            )
        )
 */
 
    }
    
    var body: some View {
        TabView {
            MessageView()
                .tabItem{Text("Message")}
            MapView()
                .tabItem{
                    Text("map")
                }

            ContentView()
            /*
                //.environmentObject(User())
               // .environmentObject(Log()) // 使い方が分かっていないかも
                // ThreeCsViewを作ったときに以下の行があると同期されなかったのでコメントアウトした
                //.environmentObject(Devices())
                //.environmentObject(UserMessage())
             */
                .tabItem{
                    Text("Debug")
                }
            //            WiFiView(userMessage: UserMessage())
            WiFiView()
                .tabItem{Text("WiFi")}
            ThreeCsView()
                .tabItem{Text("3Cs")}
            ServerControlView(userMessage: userMessage)
                .tabItem{Text("WebServer")}
            BloodPressureView()
                .tabItem{Text("Health Care Data")}
            
        }
        //.environmentObject(UserMessage(store: MessageStore()))
        .environmentObject(UserDefine())
        .environmentObject(FileID())
        .environmentObject(WiFi())
        //.environmentObject(User())
        .onAppear {
            movingEdgeInit(userMessage: userMessage)
            movingEdgeFlag = UserDefaults.standard.bool(forKey: "movingEdgeFlag")
            userMessage.movingEdgeFlag = movingEdgeFlag

        }
    }
}

/*
struct MainView_Previews: PreviewProvider {
    @StateObject private var userMessage =
        UserMessage(store: MessageStore())
    
    static var previews: some View {
        MainView()
            .environmentObject(User())
            .environmentObject(Log())
            .environmentObject(Devices())
            .environmentObject(userMessage)
    }
}
*/
