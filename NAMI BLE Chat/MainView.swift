//
//  MainView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import SwiftUI

struct MainView: View {
    @State var userMessage: UserMessage
    
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
        }
        .environmentObject(UserMessage())
        .environmentObject(UserDefine())
        .environmentObject(FileID())
        .environmentObject(WiFi())
        .environmentObject(User())
        .onAppear {
            movingEdgeInit(userMessage: userMessage)
            movingEdgeFlag = UserDefaults.standard.bool(forKey: "movingEdgeFlag")
            userMessage.movingEdgeFlag = movingEdgeFlag

        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(userMessage: UserMessage())
            .environmentObject(User())
            .environmentObject(Log())
            .environmentObject(Devices())
            //.environmentObject(UserMessage())
    }
}
