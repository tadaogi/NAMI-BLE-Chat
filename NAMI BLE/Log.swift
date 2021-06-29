//
//  Log.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/20.
//

import Foundation
import Combine
import SwiftUI

struct LogItem {
    var code = UUID()
    var logtext: String
}
class Log : ObservableObject {
    //@Published var logtext: String = "initial\n1\n2\n3\n4\n5\n6\n"
    //@Published var loglist : [LogItem] = [
    @Published var loglist : [LogItem] = [
//        LogItem(logtext: "--- log start ---"),
//        LogItem(logtext: "log2")
    ]
    //var count = 0
    var logcount = 0
    
    //func add() {
    //    count = count + 1
    //    self.logtext += "add \(self.count)\n"
    //}
    
    func addItem(logText: String) {
        let now = Date() // 現在日時の取得
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
        let currenttime = dateFormatter.string(from: now) // -> 2021/01/20 19:57:17.234
        print(currenttime + " " + logText)
        
        logcount = logcount + 1
        loglist.append(LogItem(logtext: "\(currenttime)[\(self.logcount)]: \(logText)"))
    }
    
}
