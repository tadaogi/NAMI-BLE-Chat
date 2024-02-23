//
//  ContentView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI
import CoreBluetooth

class User: ObservableObject {
    @Published var AutoMode = false
    @Published var Ptime = 300
    @Published var Ctime = 300
    @Published var RandomMode = true
    @Published var CentralMode = true
    @Published var ConnectMode = true
    @Published var PeripheralMode = false
    @Published var iPhoneMode = false
    @Published var debugLogMode = true
    @Published var myID = "tmp"
    @Published var timerInterval = "30" // <- 300
    @Published var obsoleteInterval = "900" // <-600
    @Published var rssi1m = -60
    @Published var rssi3m = -70
    @Published var testMessageFlag = false

    init() {
        self.myID = UserDefaults.standard.object(forKey: "myID") as? String ?? "tadashi"
        self.timerInterval = UserDefaults.standard.object(forKey: "timerInterval") as? String ?? "30"
        self.obsoleteInterval = UserDefaults.standard.object(forKey: "obsoleteInterval") as? String ?? "900"
        self.iPhoneMode = UserDefaults.standard.object(forKey: "iPhoneMode") as? Bool ?? true
        self.rssi1m = UserDefaults.standard.object(forKey: "rssi1m") as? Int ?? -60
        self.rssi3m = UserDefaults.standard.object(forKey: "rssi3m") as? Int ?? -70
        self.AutoMode = UserDefaults.standard.object(forKey: "AutoMode") as? Bool ?? true
        self.RandomMode = UserDefaults.standard.object(forKey: "RandomMode") as? Bool ?? true
        self.Ptime = UserDefaults.standard.object(forKey: "Ptime") as? Int ?? 300
        self.Ctime = UserDefaults.standard.object(forKey: "Ctime") as? Int ?? 300

    }
}

struct ContentView: View {
    @EnvironmentObject var log : Log
    @EnvironmentObject var devices : Devices

    @ObservedObject var bleCentral = BLECentral()
    @ObservedObject var blePeripheral = BLEPeripheral()
    @EnvironmentObject var user : User
    //@EnvironmentObject var myID : String
    //@ObservedObject var user: User = User()
    //@EnvironmentObject var log : Log

    @EnvironmentObject var userMessage : UserMessage

    @State var buttontext = "Start"
    @State var runflag = false
//    var devicetext = ""
    var gps = GPS()
    @State var autoCPflag = false
    
    @EnvironmentObject var fileID: FileID
    
    @EnvironmentObject var wifi: WiFi
    
    init() {
        //print("ContentView init is called")
        //print(self.log)
        //self.bleCentral.myinit(message: self.message)
        // ここでは失敗する。早すぎるみたい。
        
    }
    
    func Date2String(date: Date)->String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HmsS")
        return(formatter.string(from: date))
    }
    
    func state2String(state: CBPeripheralState)->String {
        switch state {
        case CBPeripheralState.connected :
            return "connected"
        case CBPeripheralState.connecting :
            return "connecting"
        case CBPeripheralState.disconnected :
            return "disconnected"
        case CBPeripheralState.disconnecting :
            return "disconnecting"
        @unknown default:
            return "unknown state"
        }
    }

    func CtoP(log: Log, devices: Devices, userMessage: UserMessage) {
        if runflag {
            print("CtoP")
            //log.addItem(logText: "CtoP")
            bleCentral.stopCentral()
            user.CentralMode = false
            blePeripheral.startPeripheral(log: log, userMessage: userMessage)
            user.PeripheralMode = true
            blePeripheral.peripheralMode = true
            
            let randomInt = Int.random(in: 5..<8)
            var randomwaitTime:Double = 0.0
            if user.RandomMode {
                randomwaitTime = Double(60 * randomInt)
            }
            let waitPTime:Double = Double(user.Ptime) + randomwaitTime
            log.addItem(logText: "CtoP (\(Int(waitPTime)))")

            DispatchQueue.main.asyncAfter(deadline: .now()+waitPTime) {
                PtoC(log: log, devices: devices, userMessage: userMessage)
            }
        } else {
            print("Stop in CtoP")
            log.addItem(logText: "Stop in CtoP")        }
    }
    
    func PtoC(log: Log, devices: Devices, userMessage: UserMessage) {
        if runflag {
            print("PtoC")
            log.addItem(logText: "PtoC")
            blePeripheral.stopPeripheral(log: log)
            user.PeripheralMode = false
            blePeripheral.peripheralMode = false
            bleCentral.startCentral(log: log, devices: devices, user: user)
            user.CentralMode = true
            
            let randomInt = Int.random(in: 0..<5)
            var randomwaitTime:Double = 0.0
            if user.RandomMode {
                randomwaitTime = Double(60 * randomInt)
            }
            let waitCTime:Double = Double(user.Ctime) + randomwaitTime
            log.addItem(logText: "PtoC (\(Int(waitCTime)))")

            DispatchQueue.main.asyncAfter(deadline: .now()+waitCTime) {
                CtoP(log: log, devices: devices, userMessage: userMessage)
            }
        } else {
            print("Stop in PtoC")
            log.addItem(logText: "stop in PtoC")
        }
    }
    
    func autoCPrun (log: Log, devices: Devices, userMessage: UserMessage) {
        runflag = true
        ConnectMode = true // ConnectModeはいつでもtrueで良いような気がする
        PtoC(log: log, devices: devices, userMessage: userMessage) // or startC
    }
    
    func autoCPstop () {
        runflag = false
    }
    
    var body: some View {
//        let dummy = "2021/01/16 06:58:00.000: some a a a a a messages comes here\n"
        
        NavigationView {

        VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Button (action: {
                        if (runflag == false) {
                            // 先にやっておく
                            bleCentral.myinit(userMessage: self.userMessage)
                            blePeripheral.myinit(userMessage: self.userMessage)
                            devices.myinit(userMessage: self.userMessage)
                            
                            userMessage.initBLE(bleCentral: self.bleCentral, blePeripheral: self.blePeripheral)
                            
                            userMessage.initWiFi(wifi: self.wifi)
                            
                            if (user.AutoMode) {
                                autoCPrun(log: log, devices: devices, userMessage: userMessage)
                            } else
                            if (user.CentralMode) {
                                bleCentral.startCentralManager(log: self.log, devices: self.devices, user: self.user)
                                
                                // startCentralManager に移行したので、コメントアウト
                                /*
                                log.timerStart(bleCentral: bleCentral, timerIntervalString: self.user.timerInterval)
                                
                                bleCentral.state = BLECentralState.running
                                */
                            } else
                            if (user.PeripheralMode) {
                                blePeripheral.startPeripheralManager(log: self.log, userMessage: self.userMessage)
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"startButton,")
                            buttontext = "running"
                            runflag = true
                            gps.timerStart(timerInterval: 60)
                            
                            self.log.addItem(logText: "wifi debug")
                            wifi.setlog(log: self.log)
                            let wifires = wifi.start()
                            self.log.addItem(logText: "wifi start: \(wifires)")
                            
                            //何故か、なくても動く。駄目かな？ないと駄目
                            // 上に移動
                            /*
                            bleCentral.myinit(userMessage: self.userMessage)
                            blePeripheral.myinit(userMessage: self.userMessage)
                            
                            userMessage.initBLE(bleCentral: self.bleCentral, blePeripheral: self.blePeripheral)
                             */
                            
                            //log.timerFunc(bleCentral: bleCentral)
                            
                        } else {
                            if (user.AutoMode) {
                                autoCPstop()
                            } else
                            if (user.CentralMode) {
                                bleCentral.stopCentralManager()
                                //log.timerStop()
                                // stopCentralに移行
                            } else
                            if (user.PeripheralMode) {
                                blePeripheral.stopPeripheralManager(log: log)
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"stopButton,")
                            buttontext = "Start(again)"
                            runflag = false
                            
                            gps.timerStop()
                         }
                    }) {
                        Text(buttontext)
                    }
                    Spacer()
                }
                .font(.title)
                //Text("CentralMode:\(String(user.CentralMode))")
                Text("Devices")
                    .font(.headline)
                
                ScrollView(.vertical,showsIndicators: true) {
                    // これがないと、最初に書いたテキストの幅に固定されてしまう
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)

                    ForEach(self.devices.devicelist, id: \.code) { deviceitem in
                        
                        // iPhoneだけ表示するために、HStackを取ってみる。
                        //HStack {
                            
                            let deviceText = "\(deviceitem.deviceName), \(deviceitem.uuidString),\(deviceitem.real_rssi0),\(deviceitem.real_rssi1),\(deviceitem.real_rssi2),\(deviceitem.average_rssi), \(Date2String(date: deviceitem.firstDate)), \(Date2String(date: deviceitem.lastDate)), \(state2String(state: deviceitem.state))"
                        if iPhoneMode {
                            if deviceText.contains("iPhone") {
                                Text(deviceText).padding([.leading],10)
                                Spacer()
                            }
                        } else {
                            Text(deviceText).padding([.leading],10)
                            Spacer()
                        }
                            //Text(deviceitem.deviceName).padding([.leading],10)
                            //Text(deviceitem.uuidString)
                            //Text(String(describing: deviceitem.rssi))
                            
                            //Spacer()
                        //}
                    }
                    
                }.background(Color("lightBackground"))
                .foregroundColor(Color.black)

                Text("Log Messages")
                    .font(.headline)
                ScrollView(.vertical,showsIndicators: true) {
                    // これがないと、最初に書いたテキストの幅に固定されてしまう
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                    if debugLogMode {
                        ForEach(self.log.loglist, id: \.code) { logitem in
                            HStack {
                                Text(logitem.logtext)
                                    .padding([.leading], 15)
                                Spacer()
                            }
                        }
                    }
                    //Text(dummy)
                }.background(Color("lightBackground"))
                .foregroundColor(Color.black)
            Text("A:\(String(user.AutoMode))(\(user.Ctime),\(user.Ptime)),C:\(String(user.CentralMode)),P:\(String(user.PeripheralMode)),ID:\(user.myID),T:\(user.timerInterval),O:\(user.obsoleteInterval)")
            }
            .padding(5)
            .navigationBarTitle("Debug", displayMode: .inline)
            .navigationBarItems(
                trailing:
                    NavigationLink( destination: SettingView( uploadfname: "dummy.log")) {
                        Text("setting")
                        
                    }
            )
        }
        // 以下の行で、iPad と iPhone と同じ表示になる
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: {
            UserDefaults.standard.set(user.myID, forKey: "myID")
            UserDefaults.standard.set(user.timerInterval, forKey: "timerInterval")
            UserDefaults.standard.set(user.obsoleteInterval, forKey: "obsoleteInterval")
            UserDefaults.standard.set(user.iPhoneMode, forKey: "iPhoneMode")
            UIApplication.shared.isIdleTimerDisabled = true
        })
        .onDisappear(perform: {
            UIApplication.shared.isIdleTimerDisabled = false }
        )
    }
}

struct ContentView_Previews: PreviewProvider {

    static var user = User()
    
    static var previews: some View {
        Group {
            /// 以下の行を追加
            ForEach(["iPhone SE (2nd generation)", "iPhone 6s Plus", "iPad Pro (9.7-inch)"], id: \.self) { deviceName in
                ContentView()
                    .environmentObject(user)
                    .environmentObject(Log())
                    .environmentObject(Devices())
                    .environmentObject(FileID())
                    // .environmentObject(UserMessage())
                    /// 以下の2行を追加
                    .previewDevice(PreviewDevice(rawValue: deviceName))
                    .previewDisplayName(deviceName)
            }
        }
    }
}
