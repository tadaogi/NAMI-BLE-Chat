//
//  MovingEdge.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2025/02/01.
//
import SwiftUI

var movingEdgeFlag = false
var userMessage0: UserMessage!
var doneflag = false

// この関数が呼ばれるタイミングと変数が初期化されるタイミングが良くわかっていないので、とりあえず動くようにした 2025/2/6
// Start を押してからでないと、うまく動かない
func movingEdgeInit(userMessage: UserMessage) {
    movingEdgeFlag = UserDefaults.standard.bool(forKey: "movingEdgeFlag")
    print("movingEdgeInit")
    print(movingEdgeFlag)
    userMessage0 = userMessage // なんかおかしい
    if !doneflag {
        userMessage0 = userMessage
        if movingEdgeFlag {
            startAsync()
        }
    }
    // doneflagはなくても良いのではないか？
    // startAsyncは２重起動をチェックしている
    // doneflag = true
}

var timer: Timer!
func startAsync() {
    print("startAsync")
    if timer != nil && timer.isValid {return}

    timer = Timer
        .scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { _ in
            getNewIDs()
        }
    print("after DispatchQueue.global().sync")
}

func stopTimer() {
    if timer == nil {return}

    timer.invalidate()
}

func doNewID(newID: String) {
    print("doNewID(\(newID))")
    getMessage(userMessageID: newID)
    // ここで、UserMessage.addItemを呼ぶが、パラメータが違うので、修正必要
    //userMessage0.addItem(userMessageText: "debug")
    deleteNewID(userMessageID: newID)
}

func getMessage(userMessageID: String) {
    print("getMessage")
    var components = URLComponents(string: "http://127.0.0.1:8888/getMessage")!  //URLを生成
    components.queryItems = [URLQueryItem(name: "userMessageID", value: userMessageID)]
    let url = components.url!
    var request = URLRequest(url: url)               //Requestを生成
    let semaphore  = DispatchSemaphore(value: 1)
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        defer {
            semaphore.signal()
        }
        guard let data = data else { return }
        do {
            print(response)
            print(type(of: data))
            print(data)
            
            let object = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments) as! [String: Any]  // DataをJsonに変換
             
            print(object)
            
            print(object["userMessageID"]!)
//            print(object["group"]!)
            print(object["date"]!)
            print(object["userID"]!)
            print(object["message"]!)
            
            let userMessageID = object["userMessageID"] as! String
            let userMessageText = object["message"] as! String
            
            userMessage0.addItem2(userMessageID: userMessageID, userMessageText: userMessageText)
            
        } catch let error {
            print(error)
        }
    }
    task.resume()
    print("before semaphore.wait() in getMessage")
    semaphore.wait()
    print("after semaphore.wait() in getMessage")
}


func deleteNewID(userMessageID: String) {
    print("deleteNewID")
    /*
    print("Don't delete \(userMessageID) for debug")
    return
    */
    var components = URLComponents(string: "http://127.0.0.1:8888/deleteNewID")!  //URLを生成
    components.queryItems = [URLQueryItem(name: "userMessageID", value: userMessageID)]
    let url = components.url!
    var request = URLRequest(url: url)               //Requestを生成
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let jsonObject: [String: Any] = [
        "userMessageID": userMessageID
    ]
    
    do {
        // JSONデータに変換
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
    
        // JSONデータを文字列に変換
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
            //request.httpBody = jsonString.data(using: .utf8)
            request.httpBody = jsonData

        }
        
        
    } catch {
        print("Error converting to JSON string: \(error.localizedDescription)")
    }

    
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        guard let data = data else { return }
        do {
            print(response)
            print(type(of: data))
            print(data)
            
            let object = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments) as! [String: Any]  // DataをJsonに変換
             
            print(object)
            /*
            print(object["userMessageID"]!)
            print(object["group"]!)
            print(object["date"]!)
            print(object["userID"]!)
            print(object["message"]!)
            */
        } catch let error {
            print(error)
        }
    }
    task.resume()

}


func getNewIDs() {
    print("getNewIDs")
    
    if userMessage0.runflag == false {
        print("runflag false")
        return
    }
    var components = URLComponents(string: "http://127.0.0.1:8888/getNewIDs")!  //URLを生成
    let url = components.url!
    let request = URLRequest(url: url)               //Requestを生成
    
    let semaphore  = DispatchSemaphore(value: 1)
    
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        guard let data = data else { return }
        do {
            defer {
                semaphore.signal()
            }
            
            let object = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments) as! [String: Any]  // DataをJsonに変換
             
            for item in object {
                let newIDs = item.value
                for item2 in newIDs as! [Any] {
                    let item3 = item2 as! [String: Any]
                    let userMessageID = item3["userMessageID"] as! String
                    print(userMessageID)
                    doNewID(newID: userMessageID)
                }
            }
                        
        } catch let error {
            print(error)
        }
    }
    task.resume()

    semaphore.wait()
    
}


func sendMessage(userMessageID:String, userMessageText:String) {
    print("sendMessage")
    
    //let userMessageID = "20250127054542.123-abcd-tadashi-0(0)"
    let IDcomponents = userMessageID.components(separatedBy: "-")
    var dateString:String
    if let tmpString = IDcomponents.first {
        dateString = tmpString
    } else {
        dateString = "20250101235900.123"
    }
    print(dateString)
    
    let userID = IDcomponents[2]
    print(userID)
    
    
    let dateFormatter = DateFormatter()
    // フォーマットを設定（例: "yyyy-MM-dd HH:mm:ss"）
    dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
    
    // ロケールを指定（日本の場合は "ja_JP"）
    dateFormatter.locale = Locale(identifier: "ja_JP")

    // 文字列をDate型に変換
    guard let date = dateFormatter.date(from: dateString) else {
        print("変換失敗: フォーマットが一致しません")
        return
    }
    print(date)
    
    let url = URL(string: "http://127.0.0.1:8888/sendMessage")!  //URLを生成
    var request = URLRequest(url: url)               //Requestを生成
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let jsonObject: [String: Any] = [
        "userMessageID": userMessageID,
        "message": userMessageText,
// groupは不要だとわかった
//        "group": userMessage0.area
    ]
    
    do {
        // JSONデータに変換
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
    
        // JSONデータを文字列に変換
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
            //request.httpBody = jsonString.data(using: .utf8)
            request.httpBody = jsonData

        }
        
        
    } catch {
        print("Error converting to JSON string: \(error.localizedDescription)")
    }

    
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        guard let data = data else { return }
        do {
            print(response)
            print(type(of: data))
            print(data)
/*
            let object = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments) as! [String: [Any]]  // DataをJsonに変換
            print(object)
 */

        } catch let error {
            print(error)
        }
    }
    task.resume()

}
