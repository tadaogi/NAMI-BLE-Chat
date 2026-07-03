//
//  Dialog.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2026/07/03.
//


import SwiftUI
import Combine

@MainActor
final class Dialog: ObservableObject {

    static let shared = Dialog()

    @Published var isShowing = false
    @Published var title = "Message"
    @Published var message = ""

    private init() {}

    func show(_ message: String, title: String = "Message") {
        self.title = title
        self.message = message
        self.isShowing = true
    }

    func close() {
        isShowing = false
    }
}
