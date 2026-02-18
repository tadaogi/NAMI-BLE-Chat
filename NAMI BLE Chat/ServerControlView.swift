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
    
    init() {
        do {
            self.db = try MessageDB()
        } catch {
            // 起動時に落とすより、状態表示に出す
            fatalError("DB init failed: \(error)")
        }
        print("WebServerManager init:", ObjectIdentifier(self))
        
    }

    func start(port: UInt = 8080) {
        stop()

        let server = GCDWebServer()
        self.webServer = server
        print("WebServerManager start:", ObjectIdentifier(self))
        print("server instance:", ObjectIdentifier(server))
        // --- UI (single page) ---
        server.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { _ in
            let displayURL = self.getURL()
            let html = self.makeIndexHTML(displayURL: displayURL)

            return GCDWebServerDataResponse(html: html)
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

                
                let userMessageIDformat = mkuserMessageIDformat(userID: userID)
                // spllitの処理が抜けている
                // ＊ 要修正 ＊
                // UserMessage.addItemからコピペして修正
                let mtu = 512 // ここは相手が決まっていないので、MTUを知ることが出来ない。なので、決め打ちで512にしておく。
                //let mtu = 100
                let headerLength = userMessageIDformat.count + 3 // シーケンス番号が３桁までとしておく
                var sequence = 0 // シーケンス番号、０から始まる
                var index = 0 // データを、どこから送るか
                var restToSend = message.data(using: .utf8)!.count - index // 日本語の時に、count だとずれるので、data にして長さを知る
                var dataToSend = message.data(using: .utf8)
                
                let IDparts = userMessageIDformat.split(separator: "-")
                var userMessageID: String = ""
                let date = String(IDparts[0])
                //let groupName = "DEBUGofficial" // ここはあとで修正する
                
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
    
    private func makeIndexHTML(displayURL: String) -> String {
"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="referrer" content="unsafe-url">
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>NAMI BBS</title>
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

      .download-icon {
        position: fixed;
        top: 20px;
        right: 100px;
        font-size: 24px;
        cursor: pointer;
      }

      .container {
            display: flex;
            justify-content: space-between;
            width: 100%;
        }

  </style>
</head>
<body>
    <header>
      <h1 style="line-height: 50px;">NAMI BBS<font size="4"> ( \(displayURL) )</font></h1>
    </header>

    <!-- 歯車アイコン -->
    <a href="{{ url_for('settings') }}" class="settings-icon">
      <i class="fas fa-cog"></i>
    </a>

    <a href="{{ url_for('showQR') }}" class="QR-icon">
      <i class="fa-solid fa-qrcode"></i>
    </a>

    <a href="{{ url_for('downloadmsg') }}" class="download-icon">
      <i class="fa-solid fa-download"></i>
    </a>

    <h3>
      <div class="container">
        <span>
          <label style="padding: 10px;">UserMessages</label>
        </span>
        <span>
          <form action="/redraw" method="GET">
          <input type="checkbox"  name="showOfficial" value="1"
          {% if showOfficialFlag %} checked {% endif %}
            onchange="this.form.submit()">
          <label for="checkbox1">Official</label>
          <input type="checkbox" name="showLocal" value="1" 
          {% if showLocalFlag %} checked {% endif %}
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

      const log = document.getElementById("log");
      for (const m of msgs){
        const id = m.userMessageID;          // ここが一意キーになる前提
        if (!id || seen.has(id)) continue;  // 既に表示済みはスキップ
        seen.add(id);

        const date = m.date;
console.log(m.userID);
        log.innerHTML +=  \
          `<div style="background-color: white; margin: 10px; padding: 10px; border-radius: 0px;">\
<strong>${esc(m.userID)}</strong>\
<strong style="margin-left: 20px;">${esc(m.groupName)}</strong>\
 <small>${formatDate(m.userMessageID)}</small>\
<small style="margin-left: 10px;">${esc(m.userMessageID)}</small>\
<p>${esc(m.message)}</p>\
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

//setInterval(fetchMessages, 1500);
fetchMessages();
</script>
</body>
</html>
"""
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
    // 他の View から使えるように、APPの最初に作成するように変更
    // @StateObject private var server = WebServerManager()
    @EnvironmentObject var server: WebServerManager

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
