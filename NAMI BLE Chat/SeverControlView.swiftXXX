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
    let id: String
    let ts: Int64          // epoch millis
    let user: String
    let text: String
}

struct PostBody: Codable {
    let user: String
    let text: String
}

struct MessagesResponse: Codable {
    let messages: [Message]
}

// ------------------------------
// SQLite (no external deps)
// ------------------------------
final class MessageDB {
    private var db: OpaquePointer?

    init() throws {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("messages.sqlite3")

        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "sqlite3_open failed"])
        }

        let sql = """
        CREATE TABLE IF NOT EXISTS messages(
          id   TEXT PRIMARY KEY,
          ts   INTEGER NOT NULL,
          user TEXT NOT NULL,
          text TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts);
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: "sqlite3_exec failed"])
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func insert(id: String, ts: Int64, user: String, text: String) throws {
        let sql = "INSERT OR REPLACE INTO messages(id, ts, user, text) VALUES(?,?,?,?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "sqlite", code: 3, userInfo: [NSLocalizedDescriptionKey: "prepare failed"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, ts)
        sqlite3_bind_text(stmt, 3, (user as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (text as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "sqlite", code: 4, userInfo: [NSLocalizedDescriptionKey: "insert failed"])
        }
    }

    func list(limit: Int, after: Int64?) throws -> [Message] {
        // after があれば ts > after で取得
        let sql: String
        if after != nil {
            sql = "SELECT id, ts, user, text FROM messages WHERE ts > ? ORDER BY ts ASC LIMIT ?;"
        } else {
            sql = "SELECT id, ts, user, text FROM messages ORDER BY ts DESC LIMIT ?;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "sqlite", code: 5, userInfo: [NSLocalizedDescriptionKey: "prepare failed"])
        }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let after {
            sqlite3_bind_int64(stmt, idx, after); idx += 1
        }
        sqlite3_bind_int(stmt, idx, Int32(limit))

        var out: [Message] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let ts = sqlite3_column_int64(stmt, 1)
            let user = String(cString: sqlite3_column_text(stmt, 2))
            let text = String(cString: sqlite3_column_text(stmt, 3))
            out.append(Message(id: id, ts: ts, user: user, text: text))
        }

        // after==nil のとき DESC で取ってるので、UI用に ASC に揃える
        if after == nil { out.reverse() }
        return out
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
    }

    func start(port: UInt = 8080) {
        stop()

        let server = GCDWebServer()
        self.webServer = server

        // --- UI (single page) ---
        server.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { _ in
            let html = Self.indexHTML
            return GCDWebServerDataResponse(html: html)
        }

        // --- GET /api/messages?limit=100&after=ts ---
        server.addHandler(forMethod: "GET", path: "/api/messages", request: GCDWebServerRequest.self) { [weak self] req in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }

            let limit = Int((req.query?["limit"] as? String) ?? "100") ?? 100
            let afterStr = req.query?["after"] as? String
            let after = afterStr.flatMap { Int64($0) }

            do {
                let msgs = try self.db.list(limit: max(1, min(limit, 500)), after: after)
                let resp = ["messages": msgs.map { ["id": $0.id, "ts": $0.ts, "user": $0.user, "text": $0.text] }]
                return GCDWebServerDataResponse(jsonObject: resp)
            } catch {
                return GCDWebServerDataResponse(jsonObject: ["error": "\(error)"])
            }
        }

        // --- POST /api/messages {user,text} ---
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

            do {
                let body = try JSONDecoder().decode(PostBody.self, from: dataReq.data)
                let user = body.user.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !user.isEmpty, !text.isEmpty else {
                    return GCDWebServerDataResponse(jsonObject: ["ok": false, "error": "user/text required"])
                }

                let ts = Int64(Date().timeIntervalSince1970 * 1000)
                let id = "\(ts)-\(UUID().uuidString.prefix(8))"
                try self.db.insert(id: id, ts: ts, user: user, text: text)

                return GCDWebServerDataResponse(jsonObject: ["ok": true, "id": id, "ts": ts])
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

    func stop() {
        webServer?.stop()
        webServer = nil
        status = "stopped"
    }

    // ブラウザUI（最小）
    private static let indexHTML = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Local BBS</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; margin: 16px; }
    #log { border: 1px solid #ccc; padding: 12px; height: 55vh; overflow: auto; white-space: pre-wrap; }
    .row { margin-top: 12px; display: flex; gap: 8px; }
    input, button { font-size: 16px; padding: 10px; }
    input { flex: 1; }
    .meta { color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <h2>Local BBS</h2>
  <div class="meta">Same Wi-Fi (iPhone hotspot) network only.</div>

  <div id="log"></div>

  <div class="row">
    <input id="user" placeholder="user" value="NONE"/>
    <input id="text" placeholder="message"/>
    <button id="send">Send</button>
  </div>

<script>
let lastTs = 0;

function esc(s){return (s||"").replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}

async function fetchMessages(){
  const url = "/api/messages?limit=200&after=" + lastTs;
  const res = await fetch(url);
  const js = await res.json();
  const msgs = (js.messages || []);
  if (msgs.length === 0) return;

  const log = document.getElementById("log");
  for (const m of msgs){
    lastTs = Math.max(lastTs, m.ts);
    const t = new Date(m.ts).toLocaleString();
    log.innerHTML += `[${esc(t)}] ${esc(m.user)}: ${esc(m.text)}\\n`;
  }
  log.scrollTop = log.scrollHeight;
}

async function sendMessage(){
  const user = document.getElementById("user").value || "NONE";
  const text = document.getElementById("text").value || "";
  if (text.trim().length === 0) return;

  const res = await fetch("/api/messages", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({user, text})
  });
  const js = await res.json();
  if (!js.ok) alert(js.error || "send failed");
  document.getElementById("text").value = "";
  await fetchMessages();
}

document.getElementById("send").addEventListener("click", sendMessage);
document.getElementById("text").addEventListener("keydown", (e)=>{ if(e.key==="Enter") sendMessage(); });

setInterval(fetchMessages, 1500);
fetchMessages();
</script>
</body>
</html>
"""
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
