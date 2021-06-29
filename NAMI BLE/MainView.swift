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
                .tabItem{Text("First")}
            ContentView()
                .environmentObject(User())
                .environmentObject(Log())
                .environmentObject(Devices())
                .tabItem{
                    Text("Debug")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
