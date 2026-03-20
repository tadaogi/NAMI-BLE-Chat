//
//  BLEcommTest0App.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI

@main
struct BLEcommTest0App: App {
    @StateObject private var server = WebServerManager()
    @StateObject private var userMessage =
        UserMessage(store: MessageStore())
    @StateObject private var log = Log()
    @StateObject private var devices = Devices()
    @StateObject private var params = Params()
    @StateObject private var user = User()

    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(userMessage)
//                .environmentObject(User())
                .environmentObject(user)
//                .environmentObject(Log()) // これだと、Logが何度も呼ばれる
                .environmentObject(log) // これで１回しか呼ばれないはず
                //.environmentObject(Devices())
                .environmentObject(devices)
// NAMI Chat に合わせて修正
//                .environmentObject(UserMessage())
//                .environmentObject(Params())
                .environmentObject(params)
                .environmentObject(server)
        }
    }
}
