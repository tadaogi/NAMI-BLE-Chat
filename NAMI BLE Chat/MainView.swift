//
//  MainView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/02/03.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            MessageView()
                .tabItem{Text("Message")}
            ContentView()
                .environmentObject(User())
               // .environmentObject(Log()) // 使い方が分かっていないかも
                // ThreeCsViewを作ったときに以下の行があると同期されなかったのでコメントアウトした
                //.environmentObject(Devices())
                //.environmentObject(UserMessage())
                .tabItem{
                    Text("Debug")
                }
            ThreeCsView()
                .tabItem{Text("3Cs")}
        }
        .environmentObject(UserMessage())
        .environmentObject(UserDefine())
        .environmentObject(FileID())
        .environmentObject(WiFi())
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(User())
            .environmentObject(Log())
            .environmentObject(Devices())
            //.environmentObject(UserMessage())
    }
}
