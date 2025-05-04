//
//  BLEcommTest0App.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI

@main
struct BLEcommTest0App: App {
    var body: some Scene {
        WindowGroup {
            MainView(userMessage: UserMessage())
//                .environmentObject(User())
                .environmentObject(Log())
                .environmentObject(Devices())
// NAMI Chat に合わせて修正
//                .environmentObject(UserMessage())
                .environmentObject(Params())

        }
    }
}
