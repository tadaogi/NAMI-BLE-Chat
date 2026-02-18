//
//  WiFiView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2024/04/01.
//

import SwiftUI
import NetworkExtension
import CoreLocation
var WiFiMessageTestTimer: Timer = Timer()

struct WiFiView: View {
    @State private var viewDidLoad = false

    @EnvironmentObject var user: User
    @State var res = ""

    @ObservedObject var networkState = WiFicheck()
    
    @State var WiFi_message_interval: Int = 60
    @State var WiFibuttonText = "tmp"
    @EnvironmentObject var userMessage: UserMessage
    @EnvironmentObject var wifi: WiFi
    
    @FocusState var focus:Bool

    var body: some View {
        ScrollView([.vertical, .horizontal],showsIndicators: true) {
            VStack() {
                Text("WiFi Setting")
                Button("keyboard close"){
                    self.focus = false
                }
                HStack(){
                    Text("EdgeMode")
                    Toggle(isOn: $user.EdgeMode) {
                        EmptyView()
                    }
                }
                
                Text("SSID:")
                    
                TextField("ssid", text: $user.ssid, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(TextAlignment.trailing)
                    .focused(self.$focus)
                Spacer().frame(height: 20)
                Text("PASS:")
                TextField("pass", text: $user.pass, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(TextAlignment.trailing)
                    .focused(self.$focus)
                Spacer().frame(height: 20)

                Button(action: {
                
                    user.myip = networkState.printAddresses()
                    if user.EdgeMode {
                        wifi.edgeIP = user.myip
                    }
                }) {
                    Text("Get My IP address")
                }
                Text(user.myip)
                
                Spacer().frame(height: 20)
                Button(action: {
                    setwifiparams()
                }) {
                    Text("Set Params")
                }
                
                HStack {
                    Text("WiFi Message Interval")
                    Spacer()
                    TextField("", value: $WiFi_message_interval, formatter: NumberFormatter(),
                              onCommit: {
                        print("WiFi_message_interval")
                        print(WiFi_message_interval)
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                        .multilineTextAlignment(TextAlignment.trailing)
                        .focused(self.$focus)
                }
                Button (action: {
                    print("action")
                    if ( user.WiFiMessageFlag == false ) {
                        startWiFiMessage()
                        WiFibuttonText = "Stop"
                        user.WiFiMessageFlag = true
                    } else {
                        stopWiFiMessage()
                        WiFibuttonText = "Start"
                        user.WiFiMessageFlag = false
                    }
                }) {
                    Text(WiFibuttonText)
                    // テキストのサイズを指定
                        .frame(width: 160, height: 40, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )}

            }
            
        }
        // 2
        .onAppear {
            print("onAppear in WiFiView")
            if viewDidLoad == false {
                // 3
                viewDidLoad = true
                // 4
                // Perform any viewDidLoad logic here.
                print("viewDidLoad")
                startLocationManager()
            }
            user.EdgeMode = (UserDefaults.standard.bool(forKey: "EdgeMode"))

            user.ssid = (UserDefaults.standard.string(forKey: "ssid") ?? "debugSSID")
            user.pass = (UserDefaults.standard.string(forKey: "pass") ?? "debugPASS")
            user.myip = networkState.printAddresses()
            if user.EdgeMode {
                wifi.edgeIP = user.myip
            }

            if user.WiFiMessageFlag {
                WiFibuttonText = "Stop"
            } else {
                WiFibuttonText = "Start"
            }

        }
        .onDisappear {
            print("onDisapper in WiFiView")
        }

    }
    
    func startLocationManager() {
        // とりあえずこれだけやれば良いらしい
        // https://zenn.dev/usk2000/articles/9e890e160d2cb4
        CLLocationManager().requestWhenInUseAuthorization()
    }

    func setwifiparams() {
        print("setwifiparams")
        
        UserDefaults.standard.set(user.EdgeMode, forKey: "EdgeMode")

        if user.EdgeMode {
            UserDefaults.standard.set(user.ssid, forKey: "ssid")
            UserDefaults.standard.set(user.pass, forKey: "pass")

        }
        
        if user.EdgeMode {
            wifi.edgeIP = user.myip
        }

    }
    
    func startWiFiMessage() {
        // MessageCommand = "command,wifi,<SSID>,<PASS>,<edgeIP>"
        print("startWiFiMessage")
        WiFiMessageTestTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(WiFi_message_interval), repeats: true, block: {(timer) in
            print("startWiFiMessageTimer")
            let wifimsg = "command,wifi,\(user.ssid),\(user.pass),\(user.myip)"
            print(wifimsg)
            userMessage.addItem(userMessageText: wifimsg)
        })

    }
    
    func stopWiFiMessage() {
        print("stopMessage")
        WiFiMessageTestTimer.invalidate()
    }
    /*
    func testNetwork() {
        print("testNetwork called. Nothing for now.")
    }
    
    func XXXconnect() {
        print("connect")
        print(user.ssid)
        print(user.pass)
        // https://qiita.com/Howasuto/items/0538f7b3795a9470b5d9
        // Important
        
        // To use the NEHotspotConfigurationManager class, you must enable the Hotspot Configuration capability in Xcode. For more information, see Hotspot Configuration Entitlement.
        //インスタンスの生成
        // originalはshared()だったけど、エラーになるので修正
        let manager = NEHotspotConfigurationManager.shared
        //仮のSSIDを代入
        //ssid = "GR-MT300N-V2-d2a"
        //仮のPASSWORDを代入
        let password = user.pass
        //後ほど利用するisWEPの値としてtureを代入
        let isWEP = false // trueでエラーだったのでとりあえずfalse
        //変数にWifiスポットの設定を代入
        let hotspotConfiguration = NEHotspotConfiguration(ssid: user.ssid, passphrase: password, isWEP: isWEP)
        //上記で記述したWifi設定に対して制限をかける。
        //hotspotConfiguration.joinOnce = false // trueを変更
        //ここでも有効期限として制限をかける。
        //hotspotConfiguration.lifeTimeInDays = 30 // 1を変更

        //ダイアログを出現させる。
        // error は、apply が成功したかかどうかで、接続とは関係ない
        manager.apply(hotspotConfiguration) { (error) in
            if let error = error {
                print(error)
                if (error.localizedDescription == "already associated.") {
                    res = "associated"
                } else {
                    res = "error"
                }
            } else {
                // 接続失敗は、apply自体は成功しているので、こちらに来る
                print("success")
                res = "success"
            }
        }
    }
     */
}

#Preview {
    WiFiView()
        .environmentObject(User())
        .environmentObject(UserMessage(store: MessageStore()))
}

