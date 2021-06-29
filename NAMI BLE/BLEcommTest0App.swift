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
            MainView()
                .environmentObject(User())
                .environmentObject(Log())
                .environmentObject(UserMessage())
        }
    }
}
