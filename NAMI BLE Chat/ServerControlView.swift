//
//  ServerControllView.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2026/02/14.
//
//
//  ContentView.swift
//  NAMIsimplehttp
//
//  Created by 荻野正 on 2026/02/14.
//

import SwiftUI
import GCDWebServer //  https://github.com/yene/GCDWebServer
import SQLite3
import Combine
import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// ------------------------------
// Model
// ------------------------------
struct Message: Codable {
    let userMessageID: String
    let message: String
    let userID: String
    let date: String
    let groupName: String
}

struct PostBody: Codable {
    let userID: String
    let message: String
    let groupName: String
}

struct MessagesResponse: Codable {
    let messages: [Message]
}

struct AppConfig: Codable {
    let defaultarea: String?
    let optionarea: [String]?
    let ssid: String?
    let password: String?
    let showDebug: String?
}

struct IDRow: Codable {
    let userMessageID: String
}

struct GetIDResponse: Codable {
    let userMessageIDs: [IDRow]
}

struct GetMessageResponse: Codable {
    let userID: String
    let userMessageID: String
    let message: String
    let date: String      // Flaskの isoformat 相当（文字列で返す）
    let group: String
}

struct ErrorResponse: Codable {
    let error: String
}

struct SendMessageRequest: Codable {
    let message: String?
    let userMessageID: String?
    let group: String?     // Flaskでは受け取るが最終的に上書きする
}

struct ParsedID {
    let userID: String
    let dateISO: String   // SQLiteには文字列で保存（ISO推奨）-> messageIDからとってきた文字列
    let incrementedUserMessageID: String
}

// ------------------------------
// SQLite (no external deps)
// ------------------------------
final class MessageDB {
    private var db: OpaquePointer?
    
    private let q = DispatchQueue(label: "MessageDB.sqlite.serial")

    func withDB<T>(_ work: () throws -> T) rethrows -> T {
        try q.sync {
            guard db != nil else { throw NSError(domain: "sqlite", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey:"db is nil"]) }
            return try work()
        }
    }
    init() throws {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("messages.sqlite3")
        
        //var db: OpaquePointer? = nil
        print("DB PATH =", url.path)
        print("exists =", FileManager.default.fileExists(atPath: url.path))

        let rcOpen = sqlite3_open(url.path, &db)
        print("open rc=\(rcOpen) db=\(String(describing: db))")
        if rcOpen != SQLITE_OK {
            print("open errmsg=\(String(cString: sqlite3_errmsg(db)))")
            throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "sqlite3_open failed"])
        }

        let sql = """
        CREATE TABLE IF NOT EXISTS messages(
          userMessageID TEXT,
          message TEXT,
          userID  TEXT,
          date    TEXT,
          groupName   TEXT
        );
        """
        var errMsg: UnsafeMutablePointer<Int8>? = nil
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "(nil)"
            print("exec rc=\(rc) errMsg=\(msg)")
            sqlite3_free(errMsg)
            print("errmsg(db)=\(String(cString: sqlite3_errmsg(db)))")
            throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: "sqlite3_exec failed"])
        }
        
        let res = Bundle.main.resourceURL!
        print("resourceURL =", res.path)

        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: res.path)
            print("Top resources:", names.sorted())
        } catch {
            print("contents error:", error)
        }

        let staticDir = res.appendingPathComponent("static", isDirectory: true)
        print("staticDir =", staticDir.path)
        print("exists(staticDir) =", FileManager.default.fileExists(atPath: staticDir.path))


        if let url = Bundle.main.resourceURL?.appendingPathComponent("static") {
            print("static path:", url.path)
            print("exists:", FileManager.default.fileExists(atPath: url.path))
        }


    }

    deinit {
        sqlite3_close(db)
    }
    
    func pragma() {
        let sql = "PRAGMA table_info(messages);"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            print("column:", name)
        }
        sqlite3_finalize(stmt)
    }

    func insert(userMessageID: String, message: String, userID: String, date: String, groupName: String) throws {
        try withDB {
            pragma()
            let sql = "INSERT OR REPLACE INTO messages(userMessageID, message, userID, date, groupName) VALUES(?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard db != nil else {
                fatalError("DB is nil")
            }
            print("insert SQL => \(sql)")   // ★これがないと場所が追えません
            let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard rc == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                print("SQLite prepare error rc=\(rc): \(message)")
                throw NSError(
                    domain: "sqlite",
                    code: Int(rc),
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (userMessageID as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (message as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (userID as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (groupName as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "sqlite", code: 4, userInfo: [NSLocalizedDescriptionKey: "insert failed"])
            }
        }
    }

    func list(limit: Int, after: String?) throws -> [Message] {
        try withDB {
            // after があれば ts > after で取得
            let sql: String
            if after != nil {
                sql = "SELECT userMessageID, message, userID, date, groupName FROM messages WHERE date > ? ORDER BY userMessageID ASC LIMIT ?;"
            } else {
                sql = "SELECT userMessageID, message, userID, date, groupName FROM messages ORDER BY userMessageID DESC LIMIT ?;"
            }
            
            var stmt: OpaquePointer?
            print("list SQL => \(sql)")   // ★これがないと場所が追えません
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "sqlite", code: 5, userInfo: [NSLocalizedDescriptionKey: "prepare failed"])
            }
            defer { sqlite3_finalize(stmt) }
            
            var idx: Int32 = 1
            if let after {
                sqlite3_bind_text(stmt, idx, (after as NSString).utf8String, -1, nil)
                idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(limit))
            
            var out: [Message] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let userMessageID = String(cString: sqlite3_column_text(stmt, 0))
                let message = String(cString: sqlite3_column_text(stmt, 1))
                let userID = String(cString: sqlite3_column_text(stmt, 2))
                let date = String(cString: sqlite3_column_text(stmt, 3))
                let groupName = String(cString: sqlite3_column_text(stmt, 4))
                out.append(Message(
                    userMessageID: userMessageID,
                    message: message,
                    userID: userID,
                    date: date,
                    groupName: groupName))
            }
            
            // after==nil のとき DESC で取ってるので、UI用に ASC に揃える
            if after == nil { out.reverse() }
            return out
        }
    }
    
    func getMessage(userMessageID: String) throws -> [Message] {
        try withDB {
            // after があれば ts > after で取得
            let sql: String
            sql = "SELECT userMessageID, message, userID, date, groupName FROM messages WHERE userMessageID=?;"
            
            var stmt: OpaquePointer?
            print("list SQL => \(sql)")   // ★これがないと場所が追えません
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "sqlite", code: 5, userInfo: [NSLocalizedDescriptionKey: "prepare failed"])
            }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (userMessageID as NSString).utf8String, -1, nil)
            
            var out: [Message] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let userMessageID = String(cString: sqlite3_column_text(stmt, 0))
                let message = String(cString: sqlite3_column_text(stmt, 1))
                let userID = String(cString: sqlite3_column_text(stmt, 2))
                let date = String(cString: sqlite3_column_text(stmt, 3))
                let groupName = String(cString: sqlite3_column_text(stmt, 4))
                out.append(Message(
                    userMessageID: userMessageID,
                    message: message,
                    userID: userID,
                    date: date,
                    groupName: groupName))
            }
            
            return out
        }
    }

}

// ------------------------------
// Web Server
// ------------------------------
@MainActor
final class WebServerManager: ObservableObject {
    @Published var status: String = "stopped"
    private var webServer: GCDWebServer?
    private let db: MessageDB
    private var isConfigured = false
    
    // チェックボックスに対応するフラグ
    @MainActor @Published var showOfficialFlag: Bool = true
    @MainActor @Published var showLocalFlag: Bool = true
    @MainActor @Published var showDebugFlag: Bool = true
    
    init() {
        do {
            self.db = try MessageDB()
        } catch {
            // 起動時に落とすより、状態表示に出す
            fatalError("DB init failed: \(error)")
        }
        ensureDataFolderExists()
    }

    func start(port: UInt = 8080) {
        stop()

        let server = GCDWebServer()
        self.webServer = server
        print("WebServerManager init:", ObjectIdentifier(self))
        print("server instance:", ObjectIdentifier(server))

        // 1) ルート登録（最初の1回だけ）
        /*
        if !isConfigured {
            configureRoutes()
            isConfigured = true
        }
         */
        
        // --- UI (single page) ---
        server.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { _ in
            //let displayURL = "192.168.0.1(displayURL)"
            let displayURL = self.getURL()
            let html = self.makeIndexHTML(
                displayURL: displayURL,
                showOfficial: self.showOfficialFlag,
                showLocal: self.showLocalFlag,
                showDebug: self.showDebugFlag
            )
            return GCDWebServerDataResponse(html: html)
        }

        // /redraw : checkboxの値を読み、フラグ更新 → /へリダイレクト
        server.addHandler(forMethod: "GET", path: "/redraw", request: GCDWebServerRequest.self) { [weak self] req in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }

            // GET クエリ: /redraw?showOfficial=1&showLocal=1 のように来る
            let q = req.query ?? [:]

            // checkboxは「ある/ない」で判定するのが確実
            let official = (q["showOfficial"] != nil)   // checkedなら true
            let local    = (q["showLocal"]    != nil)

            // Swiftフラグを更新（UI連動してるならMainActorで）
            Task { @MainActor in
                self.showOfficialFlag = official
                self.showLocalFlag = local
            }

            // 302 Redirect で / に戻す（ブラウザは / を再GETする）
            let resp = GCDWebServerResponse(redirect: URL(string: "/")!, permanent: false)
            return resp
        }
        
        // favicon.ico のエラーを消す
        server.addHandler(
            forMethod: "GET",
            path: "/favicon.ico",
            request: GCDWebServerRequest.self
        ) { _ in
            return GCDWebServerResponse(statusCode: 204)
        }

        // --- UI (settings) ---
        server.addHandler(forMethod: "GET", path: "/settings", request: GCDWebServerRequest.self) { [weak self] req in
            // クエリ ?saved=1 を判定
            let savedFlag = (req.query?["saved"] as? String) == "1"
            let settingshtml = self?.makeSettingsHTML(savedFlag: savedFlag)
            ?? "<html><body><h1>Error: settings.html not found.</h1></body></html>"
            return GCDWebServerDataResponse(html: settingshtml)
        }

        
        // ---- POST /settings  (フォーム内容を保存) ----
        server.addHandler(forMethod: "POST",
                             path: "/settings",
                             request: GCDWebServerURLEncodedFormRequest.self) { [weak self] req in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }
            guard let formReq = req as? GCDWebServerURLEncodedFormRequest else {
                return GCDWebServerResponse(statusCode: 400)
            }

            // formReq.arguments は [AnyHashable: Any]
            let args = formReq.arguments ?? [:]

            let defaultarea = (args["defaultarea"] as? String) ?? ""
            let optionareaText = (args["optionarea"] as? String) ?? ""
            let ssid = (args["ssid"] as? String) ?? ""
            let password = (args["password"] as? String) ?? ""

            // checkbox: チェックされていると "1" が来る。来ない場合は nil。
            let showDebug = ((args["showDebug"] as? String) == "1") ? "1" : "0"
            // Swiftフラグを更新（UI連動してるならMainActorで）
            Task { @MainActor in
                if showDebug == "1" {
                    self.showDebugFlag = true
                } else {
                    self.showDebugFlag = false
                }
                print("showDebugFlag: \(self.showDebugFlag)")
            }

            let config = AppConfig(
                defaultarea: defaultarea,
                optionarea: parseOptionArea(optionareaText),
                ssid: ssid,
                password: password,
                showDebug: showDebug
            )

            do {
                try saveConfigToDocuments(config)
            } catch {
                let resp = GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "\(error)"])
                resp?.statusCode = 500
                return resp
            }

            // ★ saved=1 を付けた同一URLへGETで戻す（POST再送防止）
            var comps = URLComponents(url: req.url, resolvingAgainstBaseURL: false)
            comps?.queryItems = [URLQueryItem(name: "saved", value: "1")]
            let location = comps?.url?.absoluteString ?? req.url.absoluteString

            let resp = GCDWebServerResponse(statusCode: 303)
            resp.setValue(location, forAdditionalHeader: "Location")
            return resp
        }

        // --- UI (showQR code) ---
        server.addHandler(forMethod: "GET", path: "/showQR", request: GCDWebServerRequest.self) { _ in
            let fname = "config.json"
            let config = self.loadConfigFromDocuments(fname: fname)
            var wifibase64: String = ""
            let displayURL = self.getURL() // getURLに置き換える
            var bbsbase64: String = ""

            // Wi-Fi 接続のqrコードを作成
            do {
                let url = try QRCodeUtil.saveQRCodePNG(
                    text: "WIFI:S:\(config.ssid);T:WPA;P:\(config.password);;",
                    filename: "Wi-FiQR.png",
                    size: 600,
                    correctionLevel: "H"
                )
                print("Saved:", url.path)
                wifibase64 = try self.pngFileToBase64(filename: "Wi-FiQR.png")
                print(wifibase64)
            } catch {
                print("Save failed:", error)
            }
            // BBS 接続のqrコードを作成
            do {
                let url = try QRCodeUtil.saveQRCodePNG(
                    text: displayURL,
                    filename: "BBSQR.png",
                    size: 600,
                    correctionLevel: "H"
                )
                print("Saved:", url.path)
                bbsbase64 = try self.pngFileToBase64(filename: "BBSQR.png")
                print(bbsbase64)
            } catch {
                print("Save failed:", error)
            }
            let showQRhtml = self.makeshowQRHTML(wifibase64: wifibase64, bbsbase64: bbsbase64)
            return GCDWebServerDataResponse(html: showQRhtml)
        }
        // 例: /qr.png でDocuments内の qr_hello.png を返す
        server.addHandler(forMethod: "GET", path: "/Wi-FiQR.png", request: GCDWebServerRequest.self) { _ in
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = docs.appendingPathComponent("Wi-FiQR.png")

            do {
                let data = try Data(contentsOf: fileURL)
                return GCDWebServerDataResponse(data: data, contentType: "image/png")
            } catch {
                return GCDWebServerResponse(statusCode: 404)
            }
        }
        // --- UI (download) ---
        server.addHandler(
            forMethod: "GET",
            path: "/downloadmsg",
            request: GCDWebServerRequest.self,
            processBlock: { [weak self] _ in

                guard let self else {
                    return GCDWebServerResponse(statusCode: 500)
                }

                do {
                    try self.saveMessagesHTML(limit: 500, after: nil)
                    return GCDWebServerDataResponse(text: "OK")
                } catch {
                    print("downloadmsg error: \(error)")

                    guard let resp = GCDWebServerDataResponse(text: "NG: \(error.localizedDescription)") else {
                        return GCDWebServerResponse(statusCode: 500)
                    }

                    resp.statusCode = 500
                    return resp
                }
            }
        )
/*
        server.addHandler(
            forMethod: "POST",
            path: "/api/download",
            request: GCDWebServerRequest.self,
            processBlock: { [weak self] request in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }
            
            do {
                try self.saveMessagesHTML(limit: 500, after: nil)
                return GCDWebServerDataResponse(text: "OK")

            } catch {
                print("downloadmsg error")
                return GCDWebServerDataResponse(text: "NG: \(error.localizedDescription)")
                  .withStatusCode(500)
            }
            return GCDWebServerDataResponse(text: "OK")
        }
*/
        
        /*
        server.addHandler(forMethod: "GET", path: "/setting_fixed.png", request: GCDWebServerRequest.self) { _ in
            guard let path = Bundle.main.path(forResource: "setting_fixed", ofType: "png") else {
                return GCDWebServerResponse(statusCode: 404)
            }
            guard let img = UIImage(contentsOfFile: path),
                  let data = img.pngData() else {
                return GCDWebServerResponse(statusCode: 500)
            }
            let resp = GCDWebServerDataResponse(data: data, contentType: "image/png")
            resp.setValue("no-store", forAdditionalHeader: "Cache-Control")
            
            print("WebServerManager init:", ObjectIdentifier(self))
            print("server instance:", ObjectIdentifier(server))

            return resp
        }

        server.addHandler(forMethod: "GET", path: "/setting.png", request: GCDWebServerRequest.self) { _ in
            guard let base = Bundle.main.resourceURL else { return GCDWebServerResponse(statusCode: 500) }
            let path = base.appendingPathComponent("setting.png").path

            guard FileManager.default.fileExists(atPath: path) else {
                print("NOT FOUND:", path)
                return GCDWebServerResponse(statusCode: 404)
            }

            self.logHead(path) // ★これ

            return GCDWebServerFileResponse(file: path) ?? GCDWebServerResponse(statusCode: 500)
        }
         */
        // 画像アイコン
        
        server.addHandler(forMethod: "GET", pathRegex: "^/.*\\.(png|jpg|jpeg|gif|webp)$", request: GCDWebServerRequest.self) { req in
            let filename = (req.path as NSString).lastPathComponent
            guard let base = Bundle.main.resourceURL else { return GCDWebServerResponse(statusCode: 500) }
            let url = base.appendingPathComponent(filename)

            guard FileManager.default.fileExists(atPath: url.path) else {
                return GCDWebServerResponse(statusCode: 404)
            }
            
            let path = base.appendingPathComponent("setting.png").path
            self.logHead(path) // ★これ
            
            return GCDWebServerFileResponse(file: url.path)
        }
        
        
        // --- GET /api/messages?limit=100&after=ts ---
        server.addHandler(forMethod: "GET", path: "/api/messages", request: GCDWebServerRequest.self) { [weak self] req in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }

            let limit = Int((req.query?["limit"] as? String) ?? "100") ?? 100
            let afterStr = req.query?["after"] as? String
            let after = afterStr // ISODateの文字列にする
/*
            struct Message: Codable {
                let userMessageID: String
                let message: String
                let userID: String
                let date: String
                let groupName: String
            }
*/
            do {
                let msgs = try self.db.list(limit: max(1, min(limit, 500)), after: after)
                let resp = ["messages": msgs.map { [
                    "userMessageID": $0.userMessageID,
                    "message": $0.message,
                    "userID": $0.userID,
                    "date": $0.date,
                    "groupName": $0.groupName
                ] }]
                return GCDWebServerDataResponse(jsonObject: resp)
            } catch {
                return GCDWebServerDataResponse(jsonObject: ["error": "\(error)"])
            }
        }

        // debug用
        /*
        server.addHandler(forMethod: "GET", pathRegex: ".*", request: GCDWebServerRequest.self) { req in
            print("[REQ]", req.method, req.path, req.url.absoluteString)
            return GCDWebServerResponse(statusCode: 404)
        }
        */
        
        // --- POST /api/messages {userMessageID,message} ---
        server.addHandler(
            forMethod: "POST",
            path: "/api/messages",
            request: GCDWebServerDataRequest.self
        ) { [weak self] req -> GCDWebServerResponse? in

            guard let self = self else {
                return GCDWebServerResponse(statusCode: 500)
            }

            // req は GCDWebServerRequest として入ってくるので DataRequest に落とす
            guard let dataReq = req as? GCDWebServerDataRequest else {
                return GCDWebServerResponse(statusCode: 400)
            }

            print("dataReq = \(dataReq)")
            do {
                let body = try JSONDecoder().decode(PostBody.self, from: dataReq.data)
                print("body =\(body)")
                let userID = body.userID.trimmingCharacters(in: .whitespacesAndNewlines)
                var message = body.message.trimmingCharacters(in: .whitespacesAndNewlines)
                let groupName = body.groupName.trimmingCharacters(in: .whitespacesAndNewlines)

                
                var location = globalgps?.getLastLocation()
                let latitude = String(format: "%.6f", location?.latitude ?? 0.0)
                let longitude = String(format: "%.6f", location?.longitude ?? 0.0)
                let locationTxt = "[GPS,\(latitude),\(longitude)]"
                message = locationTxt + message
                print(message)

                guard !userID.isEmpty, !message.isEmpty else {
                    return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "user/text required"])
                }

                // messageにgroupNameをtagとしてつける
                message = message + " #" + groupName
                
                let userMessageIDformat = mkuserMessageIDformat(userID: userID)
                // spllitの処理が抜けている
                // ＊ 要修正 ＊
                // UserMessage.addItemからコピペして修正
                let mtu = 51200000 // split しないように 512 から増やしてみる。
                // ここは相手が決まっていないので、MTUを知ることが出来ない。なので、決め打ちで512にしておく。
                //let mtu = 100 // debug用に小さくしてみた
                let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
                var sequence = 0 // シーケンス番号、０から始まる
                var index = 0 // データを、どこから送るか
                var restToSend = message.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
                var dataToSend = message.data(using: .utf8)
                guard let dataToSend = dataToSend else {
                    print("dataToSend is nil")
                    return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "dataToSend is nil"])

                    //return
                }
                
                let IDparts = userMessageIDformat.split(separator: "-")
                var userMessageID: String = ""
                let date = String(IDparts[0])
                //let groupName = group // ここはあとで修正する
                
                // 3) date文字列 → Date → ISO文字列
                // Flask: date_string = m.group('date'); date_string += "000"
                // "%Y%m%d%H%M%S.%f" なので、datePart は "YYYYMMDDHHMMSS.SSS" みたいな想定
                // ここでは末尾に "000" を付けてマイクロ秒 6桁にする
                let dateString = date + "000"

                let df = DateFormatter()
                df.calendar = Calendar(identifier: .gregorian)
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0) // Flaskと一致させたいならUTC推奨（必要なら変更）
                df.dateFormat = "yyyyMMddHHmmss.SSSSSS"

                guard let date = df.date(from: dateString) else {
                    throw NSError(domain: "sendMessage", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "date parse failed: \(dateString)"])
                }

                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let dateISO = iso.string(from: date)

            
                
                // ここから下が、Splitのロジック
                while (restToSend>0) {
                    var amountToSend = min(restToSend,mtu-headerLength) // 今回送るデータ長
                    print("amountToSend(initial)=", amountToSend)
                    print("restToSend=\(restToSend)")
                    print("mtu=\(mtu)")
                    print("headerLength=\(headerLength)")
                    
                    //var chunk = dataToSend?.subdata(in: index..<(index + amountToSend)) // 今回送るデータ
                    let maxPayload = mtu - headerLength
                    guard maxPayload > 0 else {
                        print("maxPayload <= 0")
                        return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "maxPayload <= 0"])
                    }
                    guard let chunk = nextUTF8Chunk(from: dataToSend, start: index, maxLength: maxPayload) else {
                        print("Failed to split UTF-8 safely at index \(index)")
                        break
                    }
                    amountToSend = chunk.count
                    print("amountToSend(actual)=", amountToSend)

                    
                    var userMessageID : String = ""
                    if (index + amountToSend < dataToSend.count) {
                        print("sequence=",sequence)
                        userMessageID = String(format: userMessageIDformat, String(sequence))
                    } else {
                        print("sequence=",sequence)
                        print("last")
                        userMessageID = String(format: userMessageIDformat, String(sequence)+"L")
                    }
                    print("userMessageID=", userMessageID)
                    // print("debugMessageFlag:",self.debugMessageFlag) // メッセージ長さが変わってしまうので、とりあえずここでは使わない
                    
                    /*
                     guard let data = chunk else {
                        print("chunk is nil")
                        //return
                        return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "chunk is nil"])
                    }
                     */
                    let data = chunk

                    print("chunk count =", data.count)
                    print("chunk hex =", data.map { String(format: "%02X", $0) }.joined(separator: " "))

                    if let text = String(data: data, encoding: .utf8) {
                        print("decoded text =", text)
                    } else {
                        print("UTF-8 decode failed")
                    }
                    // 以下で落ちるので、デバッグ用ロジック（上）を入れる
                    var UserMessageTextString = String(data:chunk ?? Data(), encoding: .utf8)! // encodeした送るテキスト
                    print(UserMessageTextString)

                    let IDparts = userMessageID.split(separator: "-")
                    let date = String(IDparts[0])
                    //let groupName = "DEBUGofficial"
                    try self.db.insert(
                        userMessageID: userMessageID,
                        message: UserMessageTextString,
                        userID: userID,
                        date: dateISO,
                        groupName: groupName
                    )

                    print("(before)index=\(index)")
                    print("amountToSend=\(amountToSend)")
                    index = index + amountToSend
                    print("(after)index=\(index)")
                    print("message.count = \(message.count)")
                    print("(before) restToSend = \(restToSend)")
                    print("message.count = \(message.count)")
                    print("dataToSend!.count = \(dataToSend.count)")
                    restToSend = dataToSend.count - index // ここはなぜか UserMessageTextString だとだめ
                    print("(after) restToSend = \(restToSend)")

                    sequence = sequence + 1
                    
                }

                return GCDWebServerDataResponse(jsonObject: ["ok": true, "userMessageID": userMessageID])
            } catch {
                return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "\(error)"])
            }
        }
        
        /*
         server.addHandler(forMethod: "GET", path: "/api/messages", request: GCDWebServerRequest.self) { [weak self] req in
             guard let self else { return GCDWebServerResponse(statusCode: 500) }

         */
        // sync用 getID
        server.addHandler(
            forMethod: "GET",
            path: "/getID",
            request: GCDWebServerRequest.self
        ) { [weak self] request -> GCDWebServerResponse? in

            guard let self else {
                return GCDWebServerResponse(statusCode: 500)
            }

            do {
                let ids = try getMessageIDList()
                let payload = GetIDResponse(
                    userMessageIDs: ids.map { IDRow(userMessageID: $0) }
                )

                let encoder = JSONEncoder()
                let data = try encoder.encode(payload)

                return GCDWebServerDataResponse(
                    data: data,
                    contentType: "application/json"
                )
            } catch {
                return GCDWebServerDataResponse(
                    jsonObject: ["error": error.localizedDescription]
                )
            }
        }

        // sync用 /getMessage
        server.addHandler(
                   forMethod: "GET",
                   path: "/getMessage",
                   request: GCDWebServerRequest.self
               ) { [weak self] req -> GCDWebServerResponse? in
                   guard let self else { return GCDWebServerResponse(statusCode: 500) }

                   // クエリ取得
                   let userMessageID = req.query?["userMessageID"] as? String

                   guard let userMessageID, !userMessageID.isEmpty else {
                       return GCDWebServerDataResponse(
                           jsonObject: ["error": "userMessageID が指定されていません"]
                       )?.withStatus(400)
                   }

                   do {
                       let rows = try self.db.getMessage(userMessageID: userMessageID)
                       
                       if rows.isEmpty {
                           return GCDWebServerDataResponse(
                            jsonObject: ["error": "no message found"]
                           )?.withStatus(500)
                       }
                       let    row = rows[0]
                       
                       let payload = GetMessageResponse(
                           userID: row.userID,
                           userMessageID: row.userMessageID,
                           message: row.message,
                           date: row.date,        // DBにISO文字列を保存している前提
                           group: row.groupName
                       )

                       let enc = JSONEncoder()
                       let data = try enc.encode(payload)
                       let resp = GCDWebServerDataResponse(data: data, contentType: "application/json; charset=utf-8")
                       return resp
                   
                   } catch {
                       return GCDWebServerDataResponse(
                           jsonObject: ["error": error.localizedDescription]
                       )?.withStatus(500)
                   }
               }

        // sync要 /sendMessage
        server.addHandler(
                    forMethod: "POST",
                    path: "/sendMessage",
                    request: GCDWebServerDataRequest.self
                ) { [weak self] req -> GCDWebServerResponse? in
                    guard let self else { return GCDWebServerResponse(statusCode: 500) }

                    // Config 読み込み（Flask同様、毎回読む）
                    let fname = "config.json"
                    let config = loadConfigFromDocuments(fname: fname)
                    let defaultarea = config.defaultarea
                    // optionareaはFlaskで作ってるが、この処理では使っていないので省略（必要なら join も可）
                    // let optionarea = config.optionarea.joined(separator: "\n")

                    // JSON decode
                    guard let dataReq = req as? GCDWebServerDataRequest else {
                        return GCDWebServerDataResponse(jsonObject: ["error": "no body"])?.withStatus(400)
                    }

                    let body = dataReq.data

                    let decoded: SendMessageRequest
                    do {
                        decoded = try JSONDecoder().decode(SendMessageRequest.self, from: body)
                    } catch {
                        return GCDWebServerDataResponse(jsonObject: ["error": "invalid json"])?.withStatus(400)
                    }

                    guard let message = decoded.message, !message.isEmpty,
                          let userMessageID0 = decoded.userMessageID, !userMessageID0.isEmpty else {
                        return GCDWebServerDataResponse(jsonObject: ["error": "missing message/userMessageID"])?.withStatus(400)
                    }

                    // dup check
                    do {
                        if try self.countID(userMessageID: userMessageID0) > 0 {
                            // Flaskのスペルに合わせる
                            return GCDWebServerDataResponse(jsonObject: ["status": "dupulicated ID"])
                        }
                    } catch {
                        return GCDWebServerDataResponse(jsonObject: ["error": error.localizedDescription])?.withStatus(500)
                    }

                    // group 判定
                    // この処理が正しいか要確認
                    let groupName: String
                    if message.contains("#official") {
                        groupName = "official"
                    } else {
                        groupName = defaultarea
                    }

                    // userID/date 抽出 & hop+1
                    let parsed: ParsedID
                    do {
                        parsed = try parseAndIncrement(userMessageID: userMessageID0)
                    } catch {
                        return GCDWebServerDataResponse(jsonObject: ["error": error.localizedDescription])?.withStatus(400)
                    }

                    // INSERT
                    /*
                     func insert(userMessageID: String, message: String, userID: String, date: String, groupName: String) throws {
                     */
                    do {
                        try self.db.insert(
                            userMessageID: parsed.incrementedUserMessageID,
                            message: message,
                            userID: parsed.userID,
                            date: parsed.dateISO,
                            groupName: groupName
                        )
                        return GCDWebServerDataResponse(jsonObject: ["status": "OK"])
                    } catch {
                        return GCDWebServerDataResponse(jsonObject: ["error": error.localizedDescription])?.withStatus(500)
                    }
                }

        do {
            try server.start(options: [
                GCDWebServerOption_Port: port,
                GCDWebServerOption_BindToLocalhost: false,
                GCDWebServerOption_AutomaticallySuspendInBackground: false
            ])
            self.status = "running: \(server.serverURL?.absoluteString ?? "")"
            print("Server running:", server.serverURL?.absoluteString ?? "")
        } catch {
            self.status = "failed: \(error)"
        }
    }

    // chunkを作る時に、UTF8境界になるようにする
    func nextUTF8Chunk(from data: Data, start: Int, maxLength: Int) -> Data? {
        guard start < data.count else { return nil }
        guard maxLength > 0 else { return nil }

        let maxEnd = min(start + maxLength, data.count)
        var end = maxEnd

        while end > start {
            let chunk = data.subdata(in: start..<end)
            if String(data: chunk, encoding: .utf8) != nil {
                return chunk
            }
            end -= 1
        }

        return nil
    }
    
    func getURL() -> String {
        guard let server = self.webServer else { return "not started" }
                
        return( server.serverURL?.absoluteString ?? "")
    }
    
    func stop() {
        webServer?.stop()
        webServer = nil
        status = "stopped"
    }
    /*
    func sync() {
        print("server.sync() is called")
    }
    */
    private func logHead(_ path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let head = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[PNG?] path=\(path) size=\(data.count) head=\(head)")
        } catch {
            print("[PNG?] read error:", error)
        }
    }

    private func configureRoutes() {
        // Bundle内の web/ を探す（Xcodeで web フォルダをターゲットに含めておく）
        guard let webURL = Bundle.main.resourceURL?.appendingPathComponent("web") else {
            print("web/ not found in bundle")
            return
        }
        let webPath = webURL.path

        // "/" を web/ にマウント
        let server = self.webServer!
        server.addGETHandler(
            forBasePath: "/",
            directoryPath: webPath,
            indexFilename: "index.html",
            cacheAge: 3600,
            allowRangeRequests: true
        )
    }
    
    func mkuserMessageIDformat(userID: String) -> String {
        let now = Date() // 現在日時の取得
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
        dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
        let currenttime = dateFormatter.string(from: now) // -> 2021/01/20 19:57:17.234
        
        
        let iValue = Int.random(in: 1 ... 0xffff)
        let sValue = String(format: "%04x", iValue)
        let userMessageIDformat = currenttime + "-" + sValue + "-" + userID + "-%@(0)" //
        
        return userMessageIDformat
    }
    func mkGroupPullDown() -> String {
        let fname = "config.json"
        let config = loadConfigFromDocuments(fname: fname)
        let defaultarea = config.defaultarea
        let optionarea = config.optionarea

        print("defaultares = \(config.defaultarea)")
        print("optionares = \(config.optionarea)")
        
        var pullDownHtml = "<option value = \"\(defaultarea)\">\(defaultarea)</option>\n"
        
        let optionlist = optionarea.components(separatedBy: "\n")
        for optionarea1 in optionlist {
            pullDownHtml += "<option value = \"\(optionarea1)\">\(optionarea1)</option>\n"
        }
        if !pullDownHtml.contains("official") {
            pullDownHtml += "<option value = \"official\">official</option>\n"

        }

        print(pullDownHtml)
        return pullDownHtml
    }
    // ブラウザUI（最小）
    private static let ipaddress = "127.0.0.1(dummy)"
//    private static let indexHTML = """
    private func makeIndexHTML(displayURL: String, showOfficial: Bool, showLocal: Bool, showDebug: Bool) -> String {
        // checked を差し込む
        let officialChecked = showOfficial ? "checked" : ""
        let localChecked = showLocal ? "checked" : ""
        let fname = "config.json"
        let config = loadConfigFromDocuments(fname: fname)
        let defaultarea = config.defaultarea
        let optionarea = config.optionarea

        print("defaultares = \(config.defaultarea)")
        print("optionares = \(config.optionarea)")
        
        return(
"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="referrer" content="unsafe-url">
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>NAMI BBS</title>
<!--
  <link rel="stylesheet" href="./css/font-awesome.min.css">
-->
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; margin: 16px; }
    #log { border: 1px solid #ccc; padding: 12px; height: 55vh; overflow: auto; white-space: pre-wrap; }
    .row { margin-top: 12px; display: flex; gap: 8px; }
    input, button { font-size: 16px; padding: 10px; }
    input { flex: 1; }
    .meta { color: #666; font-size: 12px; }
      html {
        font-family: sans-serif;
      }

      body {
        margin: 0;
      }

      header {
        background: white;
        height: 5vh;
      }

      h1 {
        text-align: center;
        color: black;
        line-height: 100px;
        margin: 0;
      }

      article {
        padding: 10px;
        margin: 10px;
        background: white;
      }

      footer {
        padding: 10px;
        margin: 0px;
        font-size: 20px;
      }
      /* Add your flexbox CSS below here */
      section {
        overflow: scroll;
        height: 60vh;
        flex-direction: column;
        background: aqua;
        border: 2px solid gray;
      }

      /* 歯車アイコンを右上に固定 */
      .settings-icon {
          position: fixed;
          top: 20px;
          right: 20px;
          font-size: 24px;
          cursor: pointer;
      }

      .QR-icon {
        position: fixed;
        top: 20px;
        right: 60px;
        font-size: 24px;
        cursor: pointer;
      }

      .xxxdownload-icon {
        position: fixed;
        top: 20px;
        right: 100px;
        font-size: 24px;
        cursor: pointer;
      }

        .icon-button {
          position: fixed;
          top: 20px;
          font-size: 24px;
          cursor: pointer;

          background: none;
          border: none;
          padding: 0;
          margin: 0;
        }

        .download-icon { right: 100px; }

      .container {
            display: flex;
            justify-content: space-between;
            width: 100%;
        }
      .toast {
        position: fixed;
        top: 70px;            /* アイコン列の下に出すなら */
        right: 20px;
        max-width: 70vw;
        padding: 10px 14px;
        border-radius: 10px;
        box-shadow: 0 6px 18px rgba(0,0,0,0.2);
        background: rgba(30, 30, 30, 0.92);
        color: white;
        font-size: 14px;
        z-index: 9999;

        opacity: 0;
        transform: translateY(-8px);
        pointer-events: none;
        transition: opacity 160ms ease, transform 160ms ease;
      }

      .toast.show {
        opacity: 1;
        transform: translateY(0);
      }

  </style>
</head>
<body>
    <header>
      <h1 style="line-height: 50px;">NAMI BBS<font size="4"> ( \(displayURL))</font></h1>
    </header>

    <!-- 歯車アイコン -->
    <a href="/settings" class="settings-icon">
      <img src="/mysetting3.jpg" width="24" height="24">
    </a>

    <a href="/showQR" class="QR-icon">
      <img src="/myqrcode.jpg" width="24" height="24">
    </a>

<!--
    <a href="/downloadmsg" class="download-icon">
      <img src="/mydownload.jpg" width="24" height="24">
    </a>
-->
    <button type="button" class="icon-button download-icon" onclick="downloadMessages()">
      <img src="/mydownload.jpg" width="24" height="24">
    </button>
<script>
let toastTimer = null;

function showToast(message, ms = 1800) {
  const el = document.getElementById('toast');
  el.textContent = message;
  el.classList.add('show');

  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), ms);
}

async function downloadMessages() {
  try {
    showToast('Saving...', 1200);

    const res = await fetch('/downloadmsg', { method: 'GET' });

    // 失敗時はサーバの本文も拾う（デバッグに有用）
    const body = await res.text();

    if (!res.ok) {
      console.error('downloadmsg failed:', res.status, body);
      showToast('Failed to save', 2200);
      return;
    }

    // body が "OK" でも表示は変わらない（fetchだから）
    showToast('Saved ✅', 1800);

  } catch (e) {
    console.error(e);
    showToast('Network error', 2200);
  }
}

function OLDdownloadMessages() {
    fetch('/downloadmsg', { method: 'GET' })
        .then(response => {
            if (!response.ok) {
                console.error("download failed");
            }
        })
        .catch(err => console.error(err));
}
</script>
<div id="toast" class="toast" aria-live="polite"></div>

    <h3>
      <div class="container">
        <span>
          <label style="padding: 10px;">UserMessages</label>
        </span>
        <span>
          <form action="/redraw" method="GET">
          <input type="checkbox"  id="showOfficial" name="showOfficial" value="1"
          \(officialChecked)
            onchange="this.form.submit()">
          <label for="checkbox1">Official</label>
          <input type="checkbox" id="showLocal" name="showLocal" value="1" 
          \(localChecked)
          onchange="this.form.submit()">
          <label style="padding-right:20px;" for="checkbox2">Local</label>  
          </form>
        </span>
      </div>
    </h3>

    <section id="messageSection">

    <div id="log"></div>

    </section>

    <footer>
<!--
      <form method="POST" action="/"">
-->
      <div style="font-size: 20px;"><b>Comment</b><button form="Photo" style="margin-left: 10px; margin-bottom: 10px; margin-right: 20px;font-size: 20px">Photo</button>
        <b> UserID</b><input id="userID" name="userID" type="text" placeholder="" style="margin-left: 10px;width: 30%; align-items: center; font-size: 20px;">
        <b></b>
        <strong style="margin-left: 20px;"> Group</strong>
        <!--
        <input name="groupName" type="text" placeholder="" style="margin-left: 10px;width: 30%; align-items: center; font-size: 20px;">
        -->
        <select id="groupName" name="groupName" style="font-size:20px">
<!--
          <option value="{{ defaultarea }}" > {{ defaultarea  }}</option>
          {% for optionarea in optionarray %}
          <option value="{{optionarea}}" >{{ optionarea }}</option>
          {% endfor %}
          {% if defaultarea != "official" %}<# defaultがofficial以外だったら #>
          <option value="official" >official</option>
          {% endif %}
-->
          \(mkGroupPullDown())
<!--
<option value="debug">debug</option>
-->
        </select>
      </div>
      <div>
        <textarea id="message" name="message"placeholder="Your message" rows="5" style="width: 100%; font-size: 20px;"></textarea>
<!--  
      <button style="margin-left: 10px; font-size: 20px" type="submit">SEND</button>
-->
      <button style="margin-left: 10px; font-size: 20px" id="send">SEND</button>

      </div>
<!--
      </form>
-->

      <form method="POST" action="/Photo" id="Photo"></form>
    </footer>
<!--
  <div class="row">
    <input id="userID" placeholder="userID" value="NONE"/>
    <input id="message" placeholder="message"/>
    <button id="send">Send</button>
  </div>
-->

<script>

function esc(s){return (s||"").replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}

function formatDate(str) {
  const base = str.slice(0,12)
//  const base = str.split('.')[0];   // 小数部分を除去

  const year   = base.slice(0, 4);
  const month  = base.slice(4, 6);
  const day    = base.slice(6, 8);
  const hour   = base.slice(8,10);
  const minute = base.slice(10,12);

  return `${year}-${month}-${day} ${hour}:${minute}`;
}

let callCount = 0;
let seen = new Set();   // まずは簡単に。件数多いならリングバッファ化
let timer = null;

let failStreak = 0;

async function fetchMessages(){
  console.log("fetchMessages called", new Date().toISOString());
  try {
      console.log("fetchMessages called", ++callCount, new Date().toISOString());
      const url = "/api/messages?limit=200";
      //const res = await fetch(url);
      const res = await fetch(url, { cache: "no-store" });

      if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
      }


      failStreak = 0; // ★成功したら連続失敗リセット
      
      const js = await res.json();
      const msgs = (js.messages || []);
      if (msgs.length === 0) return;

      const showOfficialchecked = document.getElementById("showOfficial").checked;
      console.log("showOfficialchecked "+showOfficialchecked);   // true / false
      const showLocalchecked = document.getElementById("showLocal").checked;
      console.log("showLocalchecked "+showLocalchecked);   // true / false
      
      console.log("showDebug "+ "\(showDebug)");

      const log = document.getElementById("log");
      for (const m of msgs){
        const id = m.userMessageID;          // ここが一意キーになる前提
        if (!id || seen.has(id)) continue;  // 既に表示済みはスキップ

        if (m.message.includes("#official")) {
            if (!showOfficialchecked) continue;
        } else {
            if (!showLocalchecked) continue;
        }

        seen.add(id);

        var showmessage = m.message
        if ("\(showDebug)" != "true") {
            if (showmessage.startsWith("[GPS,")) {
                const end = showmessage.indexOf("]");
                if (end !== -1) {
                    showmessage = showmessage.substring(end + 1).trim();
                }
            }
        }
    
        console.log("showmessage=",showmessage)

        const date = m.date;
console.log(m.userID);
        log.innerHTML +=  \
          `<div style="background-color: white; margin: 10px; padding: 10px; border-radius: 0px;">\
<strong>${esc(m.userID)}</strong>\
<strong style="margin-left: 20px;">${esc(m.groupName)}</strong>\
 <small>${formatDate(m.userMessageID)}</small>\
<small style="margin-left: 10px;">${esc(m.userMessageID)}</small>\
<p>${esc(showmessage)}</p>\
</div>`;
console.log(log.innerHTML);
//                <strong> ${esc(m.userID)}</strong>\\n
//                <strong style="margin-left: 20px;">groupdummy</strong>\\n
//                <small>datedummy</small>\\n
//                <small style="margin-left: 10px;">${esc(m.userMessageID)}</small>\\n
//                <p>${esc(m.message)}</p>\\n';

      }
      log.scrollTop = log.scrollHeight;
  } catch(e) {

    failStreak++;
    console.warn(`fetchMessages failed streak=${failStreak}:`, e);

    // ★3連続失敗したら停止（好みで調整）
    if (failStreak >= 3) {
      stopPolling("server offline (connection failed)");
    }
  }
}

let starts = 0;
function startPolling(){
  console.log("startPolling", ++starts);
  // ★多重起動の根絶：既存があれば必ず止めてから開始
  stopPolling();

  failStreak = 0;
  fetchMessages();
//  timer = setInterval(fetchMessages, 1000);
  console.log("polling started", timer);
}

function stopPolling(reason = "") {
    console.log("stopPolling is called", timer, reason);

  if (timer !== null) {
    clearInterval(timer);
    console.log("polling stopped", timer, reason);
    timer = null;
  }
}
function showStatus(text){
  const el = document.getElementById("status");
  if (el) el.textContent = text;
}

window.addEventListener("load", startPolling);
window.addEventListener("beforeunload", stopPolling);
async function sendRowMessage(){
  console.log("sendRowMessage")
  const userID = document.getElementById("userID").value || "NONE";
  const message = document.getElementById("message").value || "empty message";
  const groupName = document.getElementById("groupName").value || "default";
  //if (text.trim().length === 0) return;
  console.log('groupName=',groupName)

  const res = await fetch("/api/messages", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({userID, message, groupName})
  });
  const js = await res.json();
  if (!js.ok) alert(js.error || "send failed");
  document.getElementById("message").value = "";
  await fetchMessages();
}

document.getElementById("send").addEventListener("click", sendRowMessage);
//document.getElementById("message").addEventListener("keydown", (e)=>{ if(e.key==="Enter") sendRowMessage(); });
// 上があると改行で送られてしまうので除く

//setInterval(fetchMessages, 1500);
fetchMessages();
</script>
</body>
</html>
"""
    )
    }
    
    private func makeSettingsHTML(savedFlag: Bool) -> String {
        let fname = "config.json"
        let config = loadConfigFromDocuments(fname: fname)
        var checked: String;

        print("defaultares = \(config.defaultarea)")
        print("optionares = \(config.optionarea)")
        if (config.showDebug == "1") {
            checked = "checked"
        } else {
            checked = ""
        }
        
        
        let bannerHTML = savedFlag
            ? """
              <div id="savedBanner" style="margin:10px 0;padding:10px;border:1px solid #4caf50;background:#e8f5e9;color:#2e7d32;font-size:18px;">
                ✅ Saved!
              </div>
              <script>
                // 2秒後にバナーを消して、URLから ?saved=1 を消す
                setTimeout(() => {
                  const b = document.getElementById('savedBanner');
                  if (b) b.remove();
                  const u = new URL(window.location.href);
                  u.searchParams.delete('saved');
                  history.replaceState(null, '', u.toString());
                }, 2000);
              </script>
              """
            : ""

        
        return(
        """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Settings</title>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
            <style>
                .settings-icon {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    font-size: 24px;
                    cursor: pointer;
                }
                /* inputとtextareaに同じフォントを指定 */
                input, textarea {
                    font-family: Arial, sans-serif; /* 任意のフォントを指定 */
                    font-size: 16px; /* フォントサイズも揃える場合は指定 */
                }
            </style>
        </head>
        <body>
        \(bannerHTML)
            <header>
            <h1>NAMI Settings <font size="4">( configfile = \(fname) )</font></h1>
            </header>

            <h2> Areas </h2>
            <form action="/settings" method="POST">
                default
                <br>
                <input name="defaultarea" value="\(config.defaultarea)" style="margin-left: 10px;width: 30%; align-items: center; font-size: 20px;"></input>
                <p>
                option
                <br>
                <textarea name="optionarea" rows="5" style="margin-left: 10px; width: 30%; font-size: 20px;">\(config.optionarea)</textarea>
                <p></p>
                <h2> Wi-Fi </h2>
                SSID
                <br>
                <input name="ssid" value="\(config.ssid)" style="margin-left: 10px;width: 30%; align-items: center; font-size: 20px;"></input>
                <br>
                PASSWORD
                <br>
                <input name="password" value="\(config.password)" style="margin-left: 10px;width: 30%; align-items: center; font-size: 20px;"></input>
                <br>
                <p></p>
                <h2> Debug </h2>
                <input type="checkbox"  name="showDebug" value="1"
                \(checked)
                >
                <label for="showDebug">showDebug</label>
                <p></p>
                <button type="submit" style="margin-left: 10px; font-size: 20px" >Save</button>
                <button type="reset" style="margin-left: 10px; font-size: 20px" >Reset</button>
            </form>
            
            <!-- ホームに戻るリンク -->
            <a href="/" class="settings-icon">
                <img src="myhome.jpg"></img>
            </a>
        </body>
        </html>        
        """
        )
    }
    
    private func makeshowQRHTML(wifibase64: String, bbsbase64: String) -> String {
        
        return(
        """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>QR code</title>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
            <style>
                .settings-icon {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    font-size: 24px;
                    cursor: pointer;
                }
            </style>
        </head>
        <body>
            <center>
                <h1>QR code</h1>

                <h2> connect Wi-Fi </h2>
                <img src="data:image/png;base64,\(wifibase64)" />
                <h2> connect BBS </h2>
                <img src="data:image/png;base64,\(bbsbase64)" />
            </center>
            <!-- ホームに戻るリンク -->
            <a href="/" class="settings-icon">
                <img src="myhome.jpg"></img>
            </a>
        </body>
        </html>
        """
        )
    }
    
    func removeGPSHeaderIfNeeded(_ text: String) -> String {
        if (self.showDebugFlag) {
            return text
        } else {
            let pattern = #"^\[GPS,[^\]]+\]\s*"#
            return text.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
    }

    private func makedownloadmsgHTML() -> String {
        """
        under construction
        """
    }
    
    func ensureDataFolderExists() {
        let fileManager = FileManager.default
        
        guard let documentsURL = fileManager.urls(for: .documentDirectory,
                                                  in: .userDomainMask).first else {
            return
        }
        
        let dataFolderURL = documentsURL.appendingPathComponent("data")
        
        if !fileManager.fileExists(atPath: dataFolderURL.path) {
            do {
                try fileManager.createDirectory(at: dataFolderURL,
                                                withIntermediateDirectories: true)
                print("data folder created")
            } catch {
                print("Failed to create data folder:", error)
            }
        }
    }

    
    func loadConfigFromDocuments(fname: String) -> (
        defaultarea: String,
        optionarea: String,
        ssid: String,
        password: String,
        showDebug: String
    ) {
        
        var defaultarea = "default"
        var optionareaString = "area0\narea1\n"
        var ssid = "APname"
        var password = "pass"
        var showDebug = "1"
        
        let fileManager = FileManager.default
        
        // Documents URL
        guard let documentsURL = fileManager.urls(for: .documentDirectory,
                                                  in: .userDomainMask).first else {
            print("Documents directory not found")
            return (defaultarea, optionareaString, ssid, password, showDebug)
        }
        
        let dataFolderURL = documentsURL.appendingPathComponent("data")
        let configURL = dataFolderURL.appendingPathComponent(fname)
        
        // ファイルが存在しない場合
        guard fileManager.fileExists(atPath: configURL.path) else {
            print("config.json not found at \(configURL.path)")
            return (defaultarea, optionareaString, ssid, password, showDebug)
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            
            defaultarea = config.defaultarea ?? ""
            ssid = config.ssid ?? ""
            password = config.password ?? ""
            showDebug = config.showDebug ?? ""
            
            if let optionarea = config.optionarea {
                optionareaString = optionarea.joined(separator: "\n")
            }
            
        } catch {
            print("JSON decode error:", error)
        }
        
        return (defaultarea, optionareaString, ssid, password, showDebug)
    }
    
    private func configFileURL() throws -> URL {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Documents not found"])
        }
        let dir = docs.appendingPathComponent("data", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        print("configdir = \(dir.absoluteString)")
        return dir.appendingPathComponent("config.json")
    }

    private func saveConfigToDocuments(_ config: AppConfig) throws {
        let url = try configFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }

    private func parseOptionArea(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    func pngFileToBase64(filename: String) throws -> String {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent(filename)

        let data = try Data(contentsOf: fileURL)
        return data.base64EncodedString()
    }
    
    func makeMessagesHTML(_ msgs: [Message]) -> String {

//        let inputFormatter = ISO8601DateFormatter()
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone.current
        inputFormatter.dateFormat = "yyyyMMddHHmmss.SSS"

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")

        var html =
            """
            <!DOCTYPE html>
            <html lang="en-US">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width">
                <title>NAMI BBS (download)</title>
                <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
                <style>
                  html {
                    font-family: sans-serif;
                  }

                  body {
                    margin: 0;
                  }

                  header {
                    background: white;
                    height: 5vh;
                  }

                  h1 {
                    text-align: center;
                    color: black;
                    line-height: 100px;
                    margin: 0;
                  }

                  /* Add your flexbox CSS below here */
                  section {
                    overflow: scroll;
                    height: 95vh;
                    flex-direction: column;
                    background: aqua;
                    border: 2px solid gray;
                  }

                </style>
              </head>
              <body>
                <header>
                  <h1 style="line-height: 45px;">NAMI BBS
                    <span style="font-size:0.5em">
                    (downloaded on saveddate)
                    </span>
                </header>


                <section id="messageSection">

            """
        

        for message in msgs {

            let formattedDate: String
            if let date = inputFormatter.date(from: message.date) {
                formattedDate = outputFormatter.string(from: date)
            } else {
                formattedDate = message.date
            }

            html += """
            <div style="background-color: white; margin: 10px; padding: 10px;">
            <strong>
            \(escapeHTML(message.userID))
            </strong>
            <strong style="margin-left: 20px;">
            \(escapeHTML(message.groupName))
            </strong>
            <small>
            \(formattedDate)
            </small>
            <small style="margin-left: 10px;">
            \(escapeHTML(message.userMessageID))
            </small>
            <p>
            \(escapeHTML(message.message))
            </p>
            </div>
            """
        }
        html += "</section>\n</body>\n"

        return html
    }
    
    func saveMessagesHTML(limit: Int, after: String?) throws {

        let msgs = try self.db.list(
            limit: max(1, min(limit, 500)),
            after: after
        )

        let html = makeMessagesHTML(msgs)

        let fileURL = documentsDirectory().appendingPathComponent(makeFileName())

        try html.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        print("Saved to: \(fileURL.path)")
    }

// 使っていない
    func makemsgfile() {
        do {
            let msgs = try self.db.list(limit: 500, after: nil)
            
            var html =
            """
            <!DOCTYPE html>
            <html lang="en-US">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width">
                <title>NAMI BBS (download)</title>
                <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">
                <style>
                  html {
                    font-family: sans-serif;
                  }

                  body {
                    margin: 0;
                  }

                  header {
                    background: white;
                    height: 5vh;
                  }

                  h1 {
                    text-align: center;
                    color: black;
                    line-height: 100px;
                    margin: 0;
                  }

                  /* Add your flexbox CSS below here */
                  section {
                    overflow: scroll;
                    height: 95vh; 
                    flex-direction: column;
                    background: aqua;
                    border: 2px solid gray;
                  }

                </style>
              </head>
              <body>
                <header>
                  <h1 style="line-height: 45px;">NAMI BBS
                    <span style="font-size:0.5em">
                    (downloaded on saveddate)
                    </span>
                </header>


                <section id="messageSection">

            """

            //let inputFormatter = ISO8601DateFormatter()
            let inputFormatter = DateFormatter()
            inputFormatter.locale = Locale(identifier: "en_US_POSIX")
            inputFormatter.timeZone = TimeZone.current
            inputFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
            
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            outputFormatter.locale = Locale(identifier: "en_US_POSIX")

            for message in msgs {
                
                html += """
                <div style="background-color: white; margin: 10px; padding: 10px; border-radius: 0px;">
                <strong>
                \(message.userID)
                </strong>
                <strong style="margin-left: 20px;">
                \(message.groupName)
                </strong>
                <small>
                \(formatDate(message.date, inputFormatter: inputFormatter, outputFormatter: outputFormatter))
                </small>
                <small style="margin-left: 10px;">
                \(message.userMessageID)
                </small>
                <p>
                \(escapeHTML(message.message))
                </p>
                </div>
                """
            }
            html += "</section>\n</body>\n"
            print(html)
        } catch {
            print("makemsgfile error: \(error)")
        }
    }
    
    func formatDate(
        _ dateString: String,
        inputFormatter: DateFormatter,
        outputFormatter: DateFormatter
    ) -> String {
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        } else {
            return dateString   // パース失敗時はそのまま返す
        }
    }
    
    func escapeHTML(_ string: String) -> String {
        var s = string
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "'", with: "&#39;")
        return s
    }
    
    func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    
    func makeFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "message_\(timestamp).html"
    }

    func getMessageIDList() -> [String] {
        do {
            let msgs = try self.db.list(limit: 500, after: nil)
            var result: [String] = []
            for msg in msgs {
                print(msg.userMessageID)
                result.append(msg.userMessageID)
            }
            return result
        } catch {
            print("Error: \(error)")
            return []
        }
    }
    
    func countID(userMessageID: String) -> Int {
        let baseID = getBaseID(id: userMessageID)
        let messageIDList = getMessageIDList()
        var count = 0
        
        for messageID in messageIDList {
            if messageID.contains(baseID) {
                count += 1
            }
        }
        
        return count
        
    }
    
    func getBaseID(id: String) -> String {

        if let index = id.firstIndex(of: "(") {
            let prefix = String(id[..<index])
            print(prefix)   // XXX-0L
            return prefix
        } else {
            return id
        }
    }

    func insertMessageToStore(userMessageItem: UserMessageItem) {
        print("WebServerManager.insertMessageToStore is called")
        
        let userMessageID = userMessageItem.userMessageID
        var message = userMessageItem.userMessageText
        let IDparts = userMessageID.split(separator: "-")
        let date = String(IDparts[0])
        let userID = String(IDparts[2])
        // NAMI側で作成されたメッセージには、groupNameがないので、Web側のdefaultareaを設定する必要がある
        let fname = "config.json"
        let config = loadConfigFromDocuments(fname: fname)
        var groupName = config.defaultarea
        if message.contains("#official") {
            groupName = "official"
        } else if let match = message.firstMatch(of: /\ #([^\s]+)$/) {
            // message の最後が #XXX で終わっていたらそれをgroupNameとする。
            groupName = String(match.1)
        } else {
            message += " #\(groupName)"
        }
        
        do {
            try self.db.insert(
                userMessageID: userMessageID,
                message: message,
                userID: userID,
                date: date,
                groupName: groupName
            )
            print("insertMessage \(userMessageItem.userMessageID) success")
        } catch {
            print("error in insertMessage. \(error)")
            markAndStop("error in insertMessageToStore. \(error)")
        }
    }
    
//    func markAndStop(_ label: String = "reached target") -> Never {
    func markAndStop(_ label: String = "reached target") {
        UserDefaults.standard.set(Date().description, forKey: "debug_reached_time")
        UserDefaults.standard.set(label, forKey: "debug_reached_label")
        UserDefaults.standard.synchronize()

        // ログだけ残して死なないようにしておく
        //fatalError("DEBUG STOP: \(label)")
    }
    
    func getMessageFromStore(userMessageID: String) -> [Message] {
        do {
            let out = try self.db.getMessage(userMessageID: userMessageID)
            return out
        } catch {
            print("error in WebServerManager.getMessageFromStore \(error)")
            return []
        }
    }
    
    /// userMessageID例（想定）: YYYYMMDDHHMMSS.xxx-...-USERID-XXXX(0)
    /// Flask: date_string + "000"（マイクロ秒合わせ）→ datetime.strptime("%Y%m%d%H%M%S.%f")
    /// Swift: まず date 部分 + "000" してから Dateへ → ISO文字列へ
    func parseAndIncrement(userMessageID: String) throws -> ParsedID {

        // 1) date と userID を抜く（Flaskの rex 相当）
        // (?P<date>[^-]*)-([^-]*)-(?P<userID>[^-]*)-([\w]*)\(([\w]*)\)
        let pattern = #"^([^-]*)-([^-]*)-([^-]*)-([\w]*)\((\d+)\)$"#
        let re = try NSRegularExpression(pattern: pattern)

        let range = NSRange(userMessageID.startIndex..<userMessageID.endIndex, in: userMessageID)
        guard let m = re.firstMatch(in: userMessageID, range: range) else {
            throw NSError(domain: "sendMessage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "userMessageID format invalid"])
        }

        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            guard let sr = Range(r, in: userMessageID) else { return "" }
            return String(userMessageID[sr])
        }

        let datePart = group(1)   // date
        let userID   = group(3)   // userID
        let hopStr   = group(5)
        let hop      = Int(hopStr) ?? 0

        // 2) hop + 1 して userMessageID の "(n)" を置換
        let newHop = hop + 1
        let incremented = re.stringByReplacingMatches(in: userMessageID, range: range,
                                                      withTemplate: "$1-$2-$3-$4(\(newHop))")

        // 3) date文字列 → Date → ISO文字列
        // Flask: date_string = m.group('date'); date_string += "000"
        // "%Y%m%d%H%M%S.%f" なので、datePart は "YYYYMMDDHHMMSS.SSS" みたいな想定
        // ここでは末尾に "000" を付けてマイクロ秒 6桁にする
        let dateString = datePart + "000"

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0) // Flaskと一致させたいならUTC推奨（必要なら変更）
        df.dateFormat = "yyyyMMddHHmmss.SSSSSS"

        guard let date = df.date(from: dateString) else {
            throw NSError(domain: "sendMessage", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "date parse failed: \(dateString)"])
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateISO = iso.string(from: date)

        return ParsedID(userID: userID, dateISO: dateISO, incrementedUserMessageID: incremented)
    }
}

// statusコードを付ける小ヘルパ（無ければそのまま setStatusCode でもOK）
private extension GCDWebServerResponse {
    func withStatus(_ code: Int) -> GCDWebServerResponse {
        self.statusCode = Int(code)
        return self
    }
}

enum QRSaveError: Error {
    case failedToMakeCIImage
    case failedToMakeCGImage
    case failedToMakePNGData
}

final class QRCodeUtil {
    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    /// 文字列からQRコードPNGを生成して Documents に保存する
    /// - Returns: 保存先URL
    static func saveQRCodePNG(
        text: String,
        filename: String = "qrcode.png",
        size: CGFloat = 512,
        correctionLevel: String = "M"   // "L","M","Q","H"
    ) throws -> URL {

        // 1) QR生成（CIImage）
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else {
            throw QRSaveError.failedToMakeCIImage
        }

        // 2) 원하는サイズへ拡大（整数倍率にすると綺麗）
        let extent = ciImage.extent.integral
        let scale = min(size / extent.width, size / extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 3) CIImage → CGImage → UIImage
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw QRSaveError.failedToMakeCGImage
        }
        let uiImage = UIImage(cgImage: cgImage)

        // 4) PNG化
        guard let pngData = uiImage.pngData() else {
            throw QRSaveError.failedToMakePNGData
        }

        // 5) Documents に保存
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)

        try pngData.write(to: url, options: [.atomic])

        return url
    }
    
    // 使っていない
    func convertDateString(_ input: String) -> String? {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone.current
        inputFormatter.dateFormat = "yyyyMMddHHmmss.SSS"

        guard let date = inputFormatter.date(from: input) else {
            return nil
        }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        outputFormatter.timeZone = TimeZone.current
        outputFormatter.dateFormat = "yyyy/MM/dd HH:mm"

        return outputFormatter.string(from: date)
    }
}

@MainActor
final class SyncManager: ObservableObject {

    @Published var userMessage: UserMessage
    private let server: WebServerManager
    var checkedAppIndex = 0
    var checkedWebIndex = 0
    var syncCount: Int = 0
    
    private var loopTask: Task<Void, Never>?


    init(userMessage: UserMessage, server: WebServerManager) {
        self.userMessage = userMessage
        self.server = server
    }
    
    func sync() async {
        var copiedAppCount: Int = 0
        var copiedWebCount: Int = 0
        print("SyncManager.sync start (\(syncCount))")
        print(userMessage.uploadfname)
        print(server.getURL())
        
        // userMessageからUserMessageIDを取得する
        var appUserMessageIDList = [] as [String]
//        for userMessageItem in userMessage.userMessageList {
        // 前回チェックした後だけリストにする
        let appList = userMessage.userMessageList
        var safeCheckedAppIndex = min(max(checkedAppIndex, 0), appList.count)

        // debug用に全部チェックにする 後で戻すこと
        safeCheckedAppIndex = 0
        
        print("checkedAppIndex: \(checkedAppIndex)")
        print("safeCheckedAppIndex: \(safeCheckedAppIndex)")
        print("appList.count: \(appList.count)")

        for userMessageItem in appList.suffix(from: safeCheckedAppIndex) {
            print(userMessageItem.userMessageID)
            appUserMessageIDList.append(userMessageItem.userMessageID)
        }
        print(appUserMessageIDList)
        checkedAppIndex = checkedAppIndex + appUserMessageIDList.count
        print("new checkedAppIndex: \(checkedAppIndex)")
        
        // WebStoreから取得
        // 前回チェックした後だけリストにする
        
        let storeList = server.getMessageIDList()
        var safeCheckedWebIndex = min(max(checkedWebIndex, 0), storeList.count)
        // debug用に全部チェックにする 後で戻すこと
        safeCheckedWebIndex = 0

        print("checkedWebIndex: \(checkedWebIndex)")
        print("safeCheckedWebIndex: \(safeCheckedWebIndex)")
        print("storeList.count: \(storeList.count)")

        print("checkedWebIndex: \(checkedWebIndex)")
        var storeUserMessageIDList = storeList.suffix(from: safeCheckedWebIndex)
        print(storeUserMessageIDList)
        checkedWebIndex = checkedWebIndex + storeUserMessageIDList.count
        print("new checkedWebIndex: \(checkedWebIndex)")
        
        // app to Web
        for appUserMessageID in appUserMessageIDList {
            print("check \(appUserMessageID)")
            var foundflag = false
            for storeUserMessageID in storeUserMessageIDList {
                print("storeUserMessageID \(storeUserMessageID)")
                if getBaseID2(id: appUserMessageID) == getBaseID2(id: storeUserMessageID) {
                    print("found: \(appUserMessageID)")
                    foundflag = true
                    break;
                } else {
                    print("not found \(appUserMessageID), \(storeUserMessageID)")
                }
            }
            if !foundflag {
                // split data かどうかを確認する
                print(getBaseID(id: appUserMessageID).suffix(2))
                if getBaseID(id: appUserMessageID).suffix(2) != "0L" {
                    // splitの場合
                    print("split file")
                    // 全IDがあるかどうか数える
                    var IDlist:[String] = []
                    
                    var numOfmsg = -2
                    for id in appUserMessageIDList {
                        if getBaseID2(id: appUserMessageID) == getBaseID2(id: id) {
                            if !IDlist.contains(id) {
                                IDlist.append(id)
                            }
                            
                            let baseID = getBaseID(id: id)

                            if baseID.suffix(1) == "L" {
                                if let match = baseID.firstMatch(of: /-(\d+)L$/) {
                                    numOfmsg = Int(String(match.1)) ?? -2
                                    print(numOfmsg)   // "123"
                                }
                            }
                        }
                    }
                    print("IDlist: \(IDlist)")
                    print("count: \(IDlist.count)")
                    if IDlist.count == numOfmsg + 1 {
                        print("All message is found")
                        print("need to merge and copy NOT IMPLEMENTED YET")
                        IDlist.sort()
                        print(IDlist)
                        var numofget = 0
                        var message = ""
                        for id in IDlist {
                            let userMessageItem = getMessageFromApp(userMessageID: id)
                            if userMessageItem == nil {
                                print("error to find \(appUserMessageID)")
                            } else {
                                message = message + (userMessageItem?.userMessageText ?? "NONE-MESSAGE")
                                numofget = numofget + 1
                            }
                        }
                        if numofget == IDlist.count {
                            print("success in merge")
                            var newID = getBaseID2(id: appUserMessageID) + "-0L(0)"
                            print(newID)
                            let newuserMessageItem = UserMessageItem(userMessageID: newID, userMessageText: message)
                            server.insertMessageToStore(userMessageItem: newuserMessageItem)
                            copiedWebCount = copiedWebCount + 1
                            
                            // 繰り返してコピーしないようにする
                            storeUserMessageIDList.append(newID)
                        }
                        
                    }
                } else {
                    // split でない場合は、そのままコピーする
                    print("not found in store: \(appUserMessageID)")
                    print("need to copy from \(appUserMessageID) app to store")
                    let userMessageItem = getMessageFromApp(userMessageID: appUserMessageID)
                    if userMessageItem == nil {
                        print("error to find \(appUserMessageID)")
                    } else {
                        server.insertMessageToStore(userMessageItem: userMessageItem!)
                    }
                    copiedWebCount = copiedWebCount + 1
                }
            }
        }
        
        // Web to app
        for storeUserMessageID in storeUserMessageIDList {
            print("check storeUserMessageID \(storeUserMessageID)")
            var foundflag = false
            for appUserMessageID in appUserMessageIDList {
                print("appUserMessageID \(appUserMessageID)")
                if getBaseID2(id: appUserMessageID) == getBaseID2(id: storeUserMessageID) {
                    // split data かどうかを確認する
                    print(getBaseID(id: appUserMessageID).suffix(2))
                    if getBaseID(id: appUserMessageID).suffix(2) != "0L" {
                        // splitの場合
                        print("split file")
                        // 全IDがあるかどうか数える
                        var IDlist:[String] = []
                        
                        var numOfmsg = -2
                        for id in appUserMessageIDList {
                            if getBaseID2(id: appUserMessageID) == getBaseID2(id: id) {
                                if !IDlist.contains(id) {
                                    IDlist.append(id)
                                }
                                
                                let baseID = getBaseID(id: id)

                                if baseID.suffix(1) == "L" {
                                    if let match = baseID.firstMatch(of: /-(\d+)L$/) {
                                        numOfmsg = Int(String(match.1)) ?? -2
                                        print(numOfmsg)   // "123"
                                    }
                                }
                            }
                        }
                        print("IDlist: \(IDlist)")
                        print("count: \(IDlist.count)")
                        if IDlist.count == numOfmsg + 1 {
                            print("All message is found")
                            foundflag = true
                        }
                    } else {
                        print("found: \(appUserMessageID)")
                        foundflag = true
                    }
                    break;
                } else {
                    print("not found \(appUserMessageID), \(storeUserMessageID)")
                }
            }
            if !foundflag {
                print("not found in App: \(storeUserMessageID)")
                print("need to copy \(storeUserMessageID) from store to app")
                
                let out = getMessageFromStore(userMessageID: storeUserMessageID)
                for message in out {
                    //print(message)
                    let copycount = insertMessageToApp(message: message)
                    //print("insertToApp \(message)")
                    copiedAppCount = copiedAppCount + copycount
                    
                }
                /*
                if userMessageItem == nil {
                    print("error to find \(appUserMessageID)")
                } else {
                    server.insertMessage(userMessageItem: userMessageItem!)
                }
                 */
            }
        }
        
        // syncが終了した時点で checkedIndex を更新する
        // 本当は、コピーでエラーを確認しないといけない
        checkedAppIndex = min(checkedAppIndex + copiedAppCount,userMessage.userMessageList.count)
        checkedWebIndex = min(checkedWebIndex + copiedWebCount,server.getMessageIDList().count)
        print("after sync")
        print("copiedAppCount: \(copiedAppCount)")
        print("checkedAppIndex: \(checkedAppIndex)")
        print("copiedWebCount: \(copiedWebCount)")
        print("checkedWebIndex: \(checkedWebIndex)")

        
        print("SyncManager.sync end \(syncCount)")
        syncCount = syncCount + 1
    }
    
    
    func start() {
        guard loopTask == nil else { return }
        
        loopTask = Task {
            while !Task.isCancelled {
                await sync()
                try? await Task.sleep(for: .seconds(300)) // ５分を１分に減らす。５分に戻す。
            }
        }
    }
    
    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }
    
    func startSyncTimer() {
        start()
    }
    
    func stopSyncTimer() {
        stop()
    }
    
    func syncOnce(){
        if loopTask != nil {
            print("loopTask is running.")
            return
        }
        Task {
            print("syncOnce")
            await sync()
        }
    }
    // Timerだと、時間内に終了しない時に２重起動になるので、上の方法に修正
    /*
    
    private var timer: Timer?
    
    
    func startSyncTimer() {
        // すでに動いていたら一旦止める
        stopSyncTimer()

        // 必要なら開始直後に1回実行
        //sync()

        // 5分ごとに実行
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    func stopSyncTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopSyncTimer()
    }
     */
    
    // chunkを作る時に、UTF8境界になるようにする
    // 同じ関数が上にもある
    func nextUTF8Chunk(from data: Data, start: Int, maxLength: Int) -> Data? {
        guard start < data.count else { return nil }
        guard maxLength > 0 else { return nil }

        let maxEnd = min(start + maxLength, data.count)
        var end = maxEnd

        while end > start {
            let chunk = data.subdata(in: start..<end)
            if String(data: chunk, encoding: .utf8) != nil {
                return chunk
            }
            end -= 1
        }

        return nil
    }

    func insertMessageToApp(message: Message) -> Int {
//        let userMessageItem = UserMessageItem(userMessageID: message.userMessageID, userMessageText: message.message)
        
        // splitの処理を追加 2026/6/22
        // count を return することが必要
        // start
        // ここから下が、Splitのロジック
        var messageText = message.message
        var index = 0
        var restToSend = messageText.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
        var dataToSend = messageText.data(using: .utf8)!
        let mtu = 512
        var userMessageIDformat = getBaseID2(id: message.userMessageID) + "-%@(0)"
        let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
        var sequence = 0 // シーケンス番号、０から始まる

        while (restToSend>0) {
            var amountToSend = min(restToSend,mtu-headerLength) // 今回送るデータ長
            print("amountToSend(initial)=", amountToSend)
            print("restToSend=\(restToSend)")
            print("mtu=\(mtu)")
            print("headerLength=\(headerLength)")
            
            //var chunk = dataToSend?.subdata(in: index..<(index + amountToSend)) // 今回送るデータ
            let maxPayload = mtu - headerLength
            guard maxPayload > 0 else {
                print("maxPayload <= 0 error")
                return -1
            }
            guard let chunk = nextUTF8Chunk(from: dataToSend, start: index, maxLength: maxPayload) else {
                print("Failed to split UTF-8 safely at index \(index)")
                break
            }
            amountToSend = chunk.count
            print("amountToSend(actual)=", amountToSend)

            
            var userMessageID : String = ""
            if (index + amountToSend < dataToSend.count) {
                print("sequence=",sequence)
                userMessageID = String(format: userMessageIDformat, String(sequence))
            } else {
                print("sequence=",sequence)
                print("last")
                userMessageID = String(format: userMessageIDformat, String(sequence)+"L")
            }
            print("userMessageID=", userMessageID)
            // print("debugMessageFlag:",self.debugMessageFlag) // メッセージ長さが変わってしまうので、とりあえずここでは使わない
            
            /*
             guard let data = chunk else {
                print("chunk is nil")
                //return
                return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "chunk is nil"])
            }
             */
            let data = chunk

            print("chunk count =", data.count)
            print("chunk hex =", data.map { String(format: "%02X", $0) }.joined(separator: " "))

            if let text = String(data: data, encoding: .utf8) {
                print("decoded text =", text)
            } else {
                print("UTF-8 decode failed")
            }
            // 以下で落ちるので、デバッグ用ロジック（上）を入れる
            var UserMessageTextString = String(data:chunk ?? Data(), encoding: .utf8)! // encodeした送るテキスト
            print(UserMessageTextString)

            let IDparts = userMessageID.split(separator: "-")
            let date = String(IDparts[0])
            //let groupName = "DEBUGofficial"
            
            let userMessageItem = UserMessageItem(userMessageID: userMessageID, userMessageText: UserMessageTextString)

            userMessage.userMessageList.append(userMessageItem)
            
            // message.txt に追加
            let path = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask)[0].appendingPathComponent(userMessage.uploadfname)
            do {
                try userMessage.appendUserMessage(
                    message: userMessageItem,
                    to: path
                )
            } catch {
                print("append error:", error)
                markAndStop("insertMessageToApp error \(error)")
            }

            /*
            try self.db.insert(
                userMessageID: userMessageID,
                message: UserMessageTextString,
                userID: userID,
                date: dateISO,
                groupName: groupName
            )
             */
            
            print("(before)index=\(index)")
            print("amountToSend=\(amountToSend)")
            index = index + amountToSend
            print("(after)index=\(index)")
//            print("message.count = \(message.count)")
            print("(before) restToSend = \(restToSend)")
//            print("message.count = \(message.count)")
            print("dataToSend!.count = \(dataToSend.count)")
            restToSend = dataToSend.count - index // ここはなぜか UserMessageTextString だとだめ
            print("(after) restToSend = \(restToSend)")

            sequence = sequence + 1
            
        }

        // end
      
        // 以下はオリジナル
        //userMessage.userMessageList.append(userMessageItem)
        // message.txt に追加
        /*
        let path = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent(userMessage.uploadfname)
        do {
            try userMessage.appendUserMessage(
                message: userMessageItem,
                to: path
            )
        } catch {
            print("append error:", error)
            markAndStop("insertMessageToApp error \(error)")
        }
         */
        return sequence
    }
    
    func getMessageFromApp(userMessageID: String) -> UserMessageItem? {
        for userMessageItem in userMessage.userMessageList {
            print(userMessageItem.userMessageID)
            if userMessageItem.userMessageID == userMessageID {
                return userMessageItem
            }
        }
        return nil
    }

    //@MainActor
    func getMessageFromStore(userMessageID: String) -> [Message] {
        let out = server.getMessageFromStore(userMessageID: userMessageID)
        return out
    }

    func getBaseID(id: String) -> String {

        if let index = id.firstIndex(of: "(") {
            let prefix = String(id[..<index])
            print(prefix)   // XXX-0L
            return prefix
        } else {
            return id
        }
    }
    
    func getBaseID2(id: String) -> String {

        if let index = id.lastIndex(of: "-") {
            let prefix = String(id[..<index])
            print(prefix)   // XXX     -0L(0) を削除
            return prefix
        } else {
            return id
        }
    }
    
//    func markAndStop(_ label: String = "reached target") -> Never {
    func markAndStop(_ label: String = "reached target") {
        UserDefaults.standard.set(Date().description, forKey: "debug_reached_time")
        UserDefaults.standard.set(label, forKey: "debug_reached_label")
        UserDefaults.standard.synchronize()

        // stop しない
        //fatalError("DEBUG STOP: \(label)")
    }
    
}


// ------------------------------
// SwiftUI App (demo UI)
// ------------------------------
/*
@main
struct LocalBBSServerApp: App {
    var body: some Scene {
        WindowGroup {
            ServerControlView()
        }
    }
}
*/

// userMessageが２ヶ所あるけど、とりあえず両方ないと動かないのでそのままにしておく
struct ServerControlView: View {
    @StateObject private var server : WebServerManager
    @EnvironmentObject var userMessage : UserMessage
    @StateObject private var syncManager: SyncManager

    init(userMessage: UserMessage) {
        let serverInstance = WebServerManager()
        _server = StateObject(wrappedValue: serverInstance)

        _syncManager = StateObject(
            wrappedValue: SyncManager(
                userMessage: userMessage,
                server: serverInstance
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Server Status").font(.headline)
            Text(server.status).font(.footnote).multilineTextAlignment(.center)

            HStack {
                Button("Start :8080") { server.start(port: 8080) }
                Button("Stop") { server.stop() }
            }
            Button("Sync Once") {
                syncManager.syncOnce()
            }
            Button("Start Sync Period") {
                syncManager.startSyncTimer()
            }

            Button("Stop Sync Period") {
                syncManager.stopSyncTimer()
            }
            Text(userMessage.uploadfname)
        }
        .padding()
    }
}
