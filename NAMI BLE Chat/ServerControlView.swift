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
                //let mtu = 512 // ここは相手が決まっていないので、MTUを知ることが出来ない。なので、決め打ちで512にしておく。
                let mtu = 100
                let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
                var sequence = 0 // シーケンス番号、０から始まる
                var index = 0 // データを、どこから送るか
                var restToSend = message.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
                var dataToSend = message.data(using: .utf8)
                
                let IDparts = userMessageIDformat.split(separator: "-")
                var userMessageID: String = ""
                let date = String(IDparts[0])
                //let groupName = group // ここはあとで修正する
                
                // ここから下が、Splitのロジック
                while (restToSend>0) {
                    var amountToSend = min(restToSend,mtu-headerLength) // 今回送るデータ長
                    print("amountToSend=", amountToSend)
                    print("restToSend=\(restToSend)")
                    print("mtu=\(mtu)")
                    print("headerLength=\(headerLength)")
                    
                    var chunk = dataToSend?.subdata(in: index..<(index + amountToSend)) // 今回送るデータ
                    var userMessageID : String = ""
                    if (index + amountToSend < dataToSend!.count) {
                        print("sequence=",sequence)
                        userMessageID = String(format: userMessageIDformat, String(sequence))
                    } else {
                        print("sequence=",sequence)
                        print("last")
                        userMessageID = String(format: userMessageIDformat, String(sequence)+"L")
                    }
                    print("userMessageID=", userMessageID)
                    // print("debugMessageFlag:",self.debugMessageFlag) // メッセージ長さが変わってしまうので、とりあえずここでは使わない
                    var UserMessageTextString = String(data:chunk ?? Data(), encoding: .utf8)! // encodeした送るテキスト
                    print(UserMessageTextString)

                    let IDparts = userMessageID.split(separator: "-")
                    let date = String(IDparts[0])
                    //let groupName = "DEBUGofficial"
                    try self.db.insert(
                        userMessageID: userMessageID,
                        message: UserMessageTextString,
                        userID: userID,
                        date: date,
                        groupName: groupName
                    )

                    print("(before)index=\(index)")
                    print("amountToSend=\(amountToSend)")
                    index = index + amountToSend
                    print("(after)index=\(index)")
                    print("message.count = \(message.count)")
                    print("(before) restToSend = \(restToSend)")
                    print("message.count = \(message.count)")
                    print("dataToSend!.count = \(dataToSend!.count)")
                    restToSend = dataToSend!.count - index // ここはなぜか UserMessageTextString だとだめ
                    print("(after) restToSend = \(restToSend)")

                    sequence = sequence + 1
                    
                }

                return GCDWebServerDataResponse(jsonObject: ["ok": true, "userMessageID": userMessageID])
            } catch {
                return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "\(error)"])
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

    func getURL() -> String {
        guard let server = self.webServer else { return "not started" }
                
        return( server.serverURL?.absoluteString ?? "")
    }
    
    func stop() {
        webServer?.stop()
        webServer = nil
        status = "stopped"
    }

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
        """
          <option value="official" >official </option>
          <option value="tebiro" >tebiro</option>
          <option value="nishikamakura" >nishikamakkura</option>
        """
    }
    // ブラウザUI（最小）
    private static let ipaddress = "127.0.0.1(dummy)"
//    private static let indexHTML = """
    private func makeIndexHTML(displayURL: String, showOfficial: Bool, showLocal: Bool, showDebug: Bool) -> String {
        // checked を差し込む
        let officialChecked = showOfficial ? "checked" : ""
        let localChecked = showLocal ? "checked" : ""
        
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
function downloadMessages() {
    fetch('/downloadmsg', { method: 'GET' })
        .then(response => {
            if (!response.ok) {
                console.error("download failed");
            }
        })
        .catch(err => console.error(err));
}
</script>
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
<option value="debug">debug</option>
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
document.getElementById("message").addEventListener("keydown", (e)=>{ if(e.key==="Enter") sendRowMessage(); });

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

struct ServerControlView: View {
    @StateObject private var server = WebServerManager()

    var body: some View {
        VStack(spacing: 12) {
            Text("Server Status").font(.headline)
            Text(server.status).font(.footnote).multilineTextAlignment(.center)

            HStack {
                Button("Start :8080") { server.start(port: 8080) }
                Button("Stop") { server.stop() }
            }
        }
        .padding()
    }
}
