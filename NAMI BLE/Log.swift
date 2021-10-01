//
//  Log.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/20.
//

import Foundation
import Combine
import SwiftUI

class GlobalVar {
    private init() {
        
    }
    static let shared = GlobalVar()
    
    var gLog: Log?
}



struct LogItem {
    var code = UUID()
    var logtext: String
}
class Log : ObservableObject {
    //@Published var logtext: String = "initial\n1\n2\n3\n4\n5\n6\n"
    //@Published var loglist : [LogItem] = [
    @Published var loglist : [LogItem] = [
          LogItem(logtext: "--- log start ---"),
//        LogItem(logtext: "log2")
    ]
    //var count = 0
    var logcount = 0
    
    var timer: Timer? = nil
    
    //func add() {
    //    count = count + 1
    //    self.logtext += "add \(self.count)\n"
    //}
    
    init() {
        GlobalVar.shared.gLog = self
        
        let versiontext = Bundle.main.infoDictionary!["CFBundleVersion"]
        print(versiontext!)
        addItem(logText: "NAMI BLE (ver.\(versiontext!)) started,")
    }
    
    func addItem(logText: String) {
        let now = Date() // 現在日時の取得
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
        let currenttime = dateFormatter.string(from: now) // -> 2021/01/20 19:57:17.234
        print(currenttime + " " + logText)
        
        logcount = logcount + 1
        
        // デバッグのために、10件ごとにログを消す
        if logcount%10 == 0 {
            loglist = [
                LogItem(logtext: "--- log deleted ---"),
            ]
        }
        let text = "\(currenttime), [\(self.logcount)], \(logText)"
        loglist.append(LogItem(logtext: text))
        
        // デバッグのために書かないで見る -> 関係なさそうなのでもとに戻す
        appendlocal(fname: "NAMI.log", text: text+"\n")

    }
    
    func appendlocal(fname: String, text: String) {
        do {
            let fileManager = FileManager.default
            let docs = try fileManager.url(for: .documentDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil, create: false)
            let path = docs.appendingPathComponent(fname)
            let data = text.data(using: .utf8)!

            print(path)
            
            if fileManager.fileExists(atPath: path.path) {
                    print("exists")
            
                let fileHandle = try FileHandle(forWritingTo: path)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                fileManager.createFile(atPath: path.path,
                                   contents: data, attributes: nil)
            }
        } catch {
            print(error)
        }
    }
    
    func readlocal(fname:   String)-> String {
        do {
            let fileManager = FileManager.default
            let docs = try fileManager.url(for: .documentDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil, create: false)
            let path = docs.appendingPathComponent(fname)

            print(path)
            
            //reading
            if fileManager.fileExists(atPath: path.path) {
                print("exists")
                let text2 = try String(contentsOf: path, encoding: .utf8)
                print(text2)
            
                return text2
            } else {
                print("not exists")
                return ""
            }
            
        } catch {
            print(error)
        }
        
        return "error"
    }
    
    func rmlocal(fname: String) {
        print("rmlocal(\(fname))")
        do {
            let fileManager = FileManager.default
            let docs = try fileManager.url(for: .documentDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil, create: false)
            let path = docs.appendingPathComponent(fname)
            print(path.absoluteString)
            print(path.absoluteURL)
            try fileManager.removeItem(at: path)
        } catch {
            print(error)
        }
    }
    
    func upload(fname: String) {
        print("Log.upload()")
        
        let url = URL(string: "https://content.dropboxapi.com/2/files/upload")
        var request = URLRequest(url: url!)
        // POSTを指定
        request.httpMethod = "POST"
        // header
        request.addValue("Bearer 53t8RlQgs0cAAAAAAAAAAe3UGhe_0W0rW03zdeSlEVM2Ubl9fRtuVICTFBg8OGDo", forHTTPHeaderField: "Authorization")
        
        // パス名に日本語が入っていると４００で失敗する
        var encodedfname: String = ""
        for c in fname.utf16 {
            encodedfname = encodedfname + String(format: "\\u%04X",c)
        }
        //let encodedfname = fname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        //print(encodedfname)
        //request.addValue("{\"path\": \"/NAMIupload/\(encodedfname)\",\"mode\": \"add\",\"autorename\": true,\"mute\": false,\"strict_conflict\": false}",forHTTPHeaderField: "Dropbox-API-Arg")
        request.addValue("{\"path\": \"/NAMIupload/\(encodedfname)\",\"mode\": \"add\",\"autorename\": true,\"mute\": false,\"strict_conflict\": false}",forHTTPHeaderField: "Dropbox-API-Arg")
        request.addValue("application/octet-stream",forHTTPHeaderField: "Content-Type")
        //print(request)
        //return
        // POSTするデータをBodyとして設定
        request.httpBody = readlocal(fname: "NAMI.log").data(using: .utf8)
        
        
        let session = URLSession.shared
        session.dataTask(with: request) { (data, response, error) in
            if error == nil, let response = response as? HTTPURLResponse {
                // HTTPヘッダの取得
                print("Content-Type: \(response.allHeaderFields["Content-Type"] ?? "")")
                // HTTPステータスコード
                print("statusCode: \(response.statusCode)")
                //print(String(data: data, encoding: .utf8) ?? "")
            }
        }.resume()
    }
    
    func writeToFile(fname: String) {
        print("Log.writeToFile()")
        let stringToSave = "The string I want to save"
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent("myFile")

        if let stringData = stringToSave.data(using: .utf8) {
            try? stringData.write(to: path)
        }
     
    }
    
    func timerStart (bleCentral: BLECentral, timerIntervalString: String) {
        print("Log.timerStart()")
        let timerInterval = Int(timerIntervalString)
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timerInterval ?? 300), repeats: true, block: {_ in
            print("timer called")
            bleCentral.timerFunc()
        })
        
    }
    
    func timerStop () {
        print("Log.timerStop")
        timer?.invalidate()
    }
}
