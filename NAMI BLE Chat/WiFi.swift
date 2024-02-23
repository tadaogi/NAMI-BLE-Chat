//
//  WiFi.swift
//  LoopTest
//
//  Created by Tadashi Ogino on 2024/02/19.
//  Copied from LoopTest on 2024/2/22

import Foundation
import Dispatch
import NetworkExtension

class NamiTask {
    static var taskCount = 0
    var taskID:String
    var taskType:String
    var taskArgs:[String]
    
    init(args: [String]) {
        taskID = "T"+String(format: "%04d",NamiTask.taskCount)
        NamiTask.taskCount = NamiTask.taskCount + 1
        if NamiTask.taskCount > 10000 {
            NamiTask.taskCount = 0 // とりあえずデバッグ用なので重なってもOK
        }
        taskType = args[0]
        taskArgs = args
    }
}

public class WiFi: ObservableObject {
    var wifistatus = false
    // var taskList:[String] = []
    var namitaskList:[NamiTask] = []
    var mainsemaphore = DispatchSemaphore(value: 0)
    var loopstatus = false
    @Published var message = "wifimessage\n"
    let TaskListLock = NSLock()
    @Published var edgeIP = "0.0.0.0 (in WiFi)"
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)
    @Published var isConnected = false // 使わないので後で消しても良い
    
    var log : Log!
    
    // もともと init() だったけど、logの設定の前に呼ばれるので変更した
    // start() から呼ばれる
    func monitor_start() {
        monitor.start(queue: queue)

        monitor.pathUpdateHandler = { path in
            print("network changed")
            print(path)
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    self.isConnected = true
                    //self.printAddresses()
                }
                self.printAddresses()
                self.testNetwork()
                self.signal()
            } else {
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }
    
    func setlog(log: Log) {
        print("wifi.setlog")
        self.log = log
    }
    
    // https://forums.developer.apple.com/forums/thread/109355
    func printAddresses() {
        var addrList : UnsafeMutablePointer<ifaddrs>?
        guard
            getifaddrs(&addrList) == 0,
            let firstAddr = addrList
        else { return }
        defer { freeifaddrs(addrList) }
        for cursor in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interfaceName = String(cString: cursor.pointee.ifa_name)
            let addrStr: String
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if
                let addr = cursor.pointee.ifa_addr,
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0,
                hostname[0] != 0
            {
                addrStr = String(cString: hostname)
                //print(addr.pointee.sa_family)
            } else {
                addrStr = "?"
            }
            if cursor.pointee.ifa_addr.pointee.sa_family == 2 {
                if interfaceName == "en0" {
                    print(interfaceName, addrStr)
                }
            }
        }
        return
    }
    
    func testNetwork() {
        NEHotspotNetwork.fetchCurrent(completionHandler: { (network) in
            if let unwrappedNetwork = network {
                let networkSSID = unwrappedNetwork.ssid
                print("SSID: \(networkSSID) ")
                self.log.addItem(logText: "SSID:\(networkSSID)")
            } else {
                print("No available network")
            }
        })
    }
    // 待ちに入っている main loop の処理を進める
    func signal() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.mainsemaphore.signal()
        }
    }
    
    // 画面に表示されているメッセージを更新するので、main とする必要がある。
    func addmessage(msg: String) {
        DispatchQueue.main.async {
            self.message = self.message + msg + "\n"
        }
    }
    
    // mainのloopを開始する
    // stop 出来ないか試したが、非同期の処理が終わるのを待たないといけないので
    // 難しそうなのでとりあえずやめた。普通は stop しなくて良いはず。
    func start() -> Bool {
        self.message = self.message + "start\n"
        if self.loopstatus != true {
            self.loopstatus = true // loopは１回だけ起動される。厳密にはLockしないといけないけど、まあいいか。
            DispatchQueue.global().async {
                //let TaskListLock = NSLock()
                print("DispatchQueue in start")
            
                while self.loopstatus {
                    print("when condition is OK, do task, else wait")
                    
                    // taskがあるかどうかのチェック
                    // 最初試しにif文としたが、本来はwhile文なので書き換える。
                    // 戻せるようにif文は残しておく
                    while self.namitaskList.count != 0 {
                        defer {
                            self.TaskListLock.unlock()
                        }
                        self.TaskListLock.lock() // この thread は１つしかないので、lockしなくても良い
                        // と思ったけど、append の処理とのバッティングがあるので、そこでlockする必要がある。
                        
                        print("namitaskList exists \(self.namitaskList.count)")
                        self.addmessage(msg: "namitaskList exists")
                        // タスクがあるので、URLを叩く
                        // タスクがある間ループで続ける
                        // もし timeout等のエラーになったら抜ける
                        // URLを叩くのは非同期にする必要があると思う。（すでに別スレッドだからしなくても良いかも）
                        //let statuscode = self.URLtest()
                        let nextTask = self.namitaskList[0]
                        if nextTask.taskType == "download" {
                            let fname = nextTask.taskArgs[1]
                            print(fname)
                            let statuscode = self.ActualURLRequest(fname: fname)
                            print("statuscode=",statuscode)
                            
                            if statuscode == 200 {
                                self.namitaskList.removeFirst()
                                print("after removeFirst \(self.namitaskList.count)")
                                self.TaskListLock.unlock()
                            } else {
                                print("URL error \(statuscode)") // Timeoutはここに来るのか？
                                break
                            }
                        } else {
                            print("taskType unknown \(nextTask.taskType)")
                            self.namitaskList.removeFirst()
                            
                            self.TaskListLock.unlock()

                        }
                        
                    }
                    print("No Task to Do") // uploadに失敗したときも、ここに来る
                    self.addmessage(msg: "No Task to Do")

                    /*
                    if self.taskList != [] {
                        print("taskList exists")
                        self.addmessage(msg: "taskList exists")
                        // タスクがあるので、URLを叩く
                        // タスクがある間ループで続ける
                        // もし timeout等のエラーになったら抜ける
                        // URLを叩くのは非同期にする必要があると思う。（すでに別スレッドだからしなくても良いかも）
                        let statuscode = self.URLtest()
                        print("statuscode=",statuscode)
                    } else {
                        print("No task")
                        self.addmessage(msg: "No taskList")

                        // このまま抜けて、待ちに行く
                    }
                     */
                    // timeout を入れているのは、ロジックがおかしくなっても止まらないように。
                    switch self.mainsemaphore.wait(timeout: .now() + 10.0) {
                    case .success:
                        print("success")
                        self.addmessage(msg: "success")
                        
                    case .timedOut:
                        print("timedOut")
                        self.addmessage(msg: "timedOut")
                    }
                }
            }
        } else {
            // stop させたら、上のthreadの終了がおわるまで待たないといけにけど、それが出来なので stop はしない
            //self.loopstatus = false
        }
        self.monitor_start()
        return self.loopstatus
    }
    
    func setStatus(status: Bool) {
        print("WiFi.setStatus:", status)
        wifistatus = status
        if status==true {
            self.signal()
        }
    }
    /*
    func addTask(task: String) {
        print("addTask")
        TaskListLock.lock()
        taskList.append(task)
        TaskListLock.unlock()
        print("taskList:",taskList)
        signal()
    }
    */
    func addNamiTask(namitask: NamiTask) {
        print("addNamiTask")
        TaskListLock.lock()
        namitaskList.append(namitask)
        TaskListLock.unlock()
        print("taskList:",namitaskList)
        signal()
    }
    // これは何故必要なのか？
    func setedgeIP(edgeIP: String) {
        self.edgeIP = edgeIP
        print(self.edgeIP)
        self.addmessage(msg: "setedgeIP:"+self.edgeIP)
        
        // 本当は wifi が接続されたら
        //signal()
    }
    
    func edgeCheck()->Bool {
        return true
    }
    // https://qiita.com/TakadaTentaro/items/f9fcb6ad50d8c695e3e0 を参考
    /// セマフォ
    var URLsemaphore = DispatchSemaphore(value: 0)
    var rescode0 = 0
    
    func URLtest()-> Int {
        print("URLtest")
        
        let url = URL(string: "http://"+edgeIP)!  //URLを生成
        let request = URLRequest(url: url)               //Requestを生成
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            do {
                defer {
                    self.URLsemaphore.signal()
                }
                
                if let error = error {
                    print("request failure: \(error)")
                    let nsError = error as NSError
                    self.addmessage(msg: "request failure: \(nsError.code)")
                    return
                }
                guard let data = data else { return }
                //do {
                
                if let response = response as? HTTPURLResponse {
                    print("response.statusCode = \(response.statusCode)")
                    self.rescode0 = response.statusCode
                }
                let contents =  String(data:data,encoding: .ascii)
                print(contents ?? "contents")
                //    let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
                //    print(object)
                //} catch let error {
                //    print(error)
                //}
            }
        }
        task.resume()
        // requestCompleteHandler内でsemaphore.signal()が呼び出されるまで待機する
        URLsemaphore.wait()
        print("request completed")
        return rescode0
    }
    
    func connect(ssid: String, password: String, edgeIP: String) {
        //インスタンスの生成
        let manager = NEHotspotConfigurationManager.shared
        //仮のSSIDを代入
        //let ssid = "BUFFALO-E1CA3B"
        //仮のPASSWORDを代入
        //let password = "ogipass123"
        //後ほど利用するisWEPの値としてtureを代入
        let isWEP = false
        //変数にWifiスポットの設定を代入
        let hotspotConfiguration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: isWEP)
        //上記で記述したWifi設定に対して制限をかける。
        //hotspotConfiguration.joinOnce = true
        //ここでも有効期限として制限をかける。
        //hotspotConfiguration.lifeTimeInDays = 1

        //ダイアログを出現させる。
        manager.apply(hotspotConfiguration) { (error) in
          if let error = error {
             print(error)
          } else {
             print("success")
          }
        }
        print("edgeIP is not set now")
    }
    
    func fileRequest(fname: String) {
        print("WiFi:fileRequest to ")
        print(edgeIP)
        
        let namitask = NamiTask(args: ["download",fname])
        print(namitask.taskID)
        print(namitask.taskType)
        print(namitask.taskArgs)
        
        addNamiTask(namitask: namitask)

    }
    
    // PhotoShowのfileRequest からコピーして修正
    // 本当にリクエストを投げるロジック
    
    func ActualURLRequest(fname: String)->Int {
        print("WiFi: ActualURLRequest fname:\(fname) edgeIP:\(edgeIP) ")
        
        let url = URL(string: "http://"+edgeIP+":8010/getfile/"+fname)!  //URLを生成
        print(url)
        let request = URLRequest(url: url)               //Requestを生成
        
        // エラーのために、scodeを０にしておく
        self.rescode0 = 0
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            do {
                defer {
                    self.URLsemaphore.signal()
                }
            
                if let error = error {
                    print("request failure: \(error)")
                    let nsError = error as NSError
                    self.addmessage(msg: "request failure: \(nsError.code)")
                    self.rescode0 = nsError.code
                    return
                }

                guard let data = data else { return }
            
                if let response = response as? HTTPURLResponse {
                    print("response.statusCode = \(response.statusCode)")
                    self.rescode0 = response.statusCode
                }

                //print(response ?? 9999)
                //let contents =  String(data:data,encoding: .ascii)
                //print(contents ?? "contents")
                let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]  // DataをJsonに変換
                //print(object)
                let datastr = object["data"] as! String
                // base64のデータが表示されるのでやめておく
                //print(datastr)
                let restoreData = Data(base64Encoded: datastr)
                self.SaveToDocData(filename: fname, data: restoreData!)
            } catch let error {
                print(error)
            }
        }
        task.resume()
        
        // requestCompleteHandler内でsemaphore.signal()が呼び出されるまで待機する
        URLsemaphore.wait()
        print("request completed")
        return rescode0

    }
    
    func SaveToDocData(filename: String, data: Data) {
        print("WiFi:SaveToDoc called")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            print("SaveToDoc Done")
        } catch {
            print("SaveToDoc error")
        }
    }
}
