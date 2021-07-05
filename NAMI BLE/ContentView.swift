//
//  ContentView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI

class User: ObservableObject {
    @Published var CentralMode = true
    @Published var PeripheralMode = false
    @Published var myID = "tmp"
    @Published var timerInterval = "300"
    
    init() {
        self.myID = UserDefaults.standard.object(forKey: "myID") as? String ?? "tmp2"
        self.timerInterval = UserDefaults.standard.object(forKey: "timerInterval") as? String ?? "300"
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

    
    init() {
        //print("ContentView init is called")
        //print(self.log)
        //self.bleCentral.myinit(message: self.message)
        // ここでは失敗する。早すぎるみたい。
        
    }
    
    var body: some View {
//        let dummy = "2021/01/16 06:58:00.000: some a a a a a messages comes here\n"
        
        NavigationView {

        VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Button (action: {
                        if (runflag == false) {
                            
                            if (user.CentralMode) {
                                bleCentral.startCentralManager(log: self.log, devices: self.devices)
                                
                                log.timerStart(bleCentral: bleCentral, timerIntervalString: self.user.timerInterval)

                            }
                            if (user.PeripheralMode) {
                                blePeripheral.startPeripheralManager(log: self.log)
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"startButton,")
                            buttontext = "running"
                            runflag = true
                            
                            //何故か、なくても動く。駄目かな？ないと駄目
                            bleCentral.myinit(userMessage: self.userMessage)
                            blePeripheral.myinit(userMessage: self.userMessage)
                            
                            userMessage.initBLE(bleCentral: self.bleCentral, blePeripheral: self.blePeripheral)
                            
                            //log.timerFunc(bleCentral: bleCentral)
                            
                        } else {
                            if (user.CentralMode) {
                                bleCentral.stopCentralManager()
                                log.timerStop()
                            }
                            if (user.PeripheralMode) {
                                blePeripheral.stopPeripheralManager()
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"stopButton,")
                            buttontext = "Start(again)"
                            runflag = false
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
                    //Text(dummy)
                    
                    ForEach(self.devices.devicelist, id: \.code) { deviceitem in
                        HStack {
                            Text(deviceitem.deviceName).padding([.leading],10)
                            Text(deviceitem.uuidString)
                            Text(String(describing: deviceitem.rssi))
                            
                            Spacer()
                        }
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
                    ForEach(self.log.loglist, id: \.code) { logitem in
                        HStack {
                            Text(logitem.logtext)
                                .padding([.leading], 15)
                            Spacer()
                        }
                    }
                    //Text(dummy)
                }.background(Color("lightBackground"))
                .foregroundColor(Color.black)
            Text("Central:\(String(user.CentralMode)),Peripheral:\(String(user.PeripheralMode)),myID:\(user.myID),TimerInterval:\(user.timerInterval)")
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
                    .environmentObject(UserMessage())
                    /// 以下の2行を追加
                    .previewDevice(PreviewDevice(rawValue: deviceName))
                    .previewDisplayName(deviceName)
            }
        }
    }
}
