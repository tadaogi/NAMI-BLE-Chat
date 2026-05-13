//
//  MessageStore.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2026/02/14.
//

import Foundation
import SwiftUI

/*
struct UserMessage: Codable {
    let userMessageID: String
    let userMessageText: String
}
*/

final class MessageStore: ObservableObject {

    private let fileURL: URL

    
    init() {
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent("message.txt")
        self.fileURL = path
    }

    func append(_ message: JsonMessageItem) throws {

        let encoder = JSONEncoder()
        var data = try encoder.encode(message)
        data.append(0x0A) // newline

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }

    func loadAll() throws -> [JsonMessageItem] {

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")

        let decoder = JSONDecoder()

        return try lines.map {
            try decoder.decode(JsonMessageItem.self, from: Data($0.utf8))
        }
    }
}

final class MessageViewModel: ObservableObject {

    @Published var messages: [JsonMessageItem] = []

    private let store: MessageStore

    init(store: MessageStore) {
        self.store = store
    }

    // これは使っていないのでは？
    func addMessage(id: String, text: String) {

        let message = JsonMessageItem(userMessageID: id,
                                  userMessageText: text)

        do {
            try store.append(message)
            messages.append(message)
        } catch {
            print("save error:", error)
        }
    }

    func load() {
        do {
            messages = try store.loadAll()
        } catch {
            print("load error:", error)
        }
    }
}
