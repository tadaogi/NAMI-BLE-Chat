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
    
    init() {
        self.myID = UserDefaults.standard.object(forKey: "myID") as? String ?? "tmp2"
    }
}

struct ContentView: View {
    @EnvironmentObject var log : Log

    @ObservedObject var bleCentral = BLECentral()
    @ObservedObject var blePeripheral = BLEPeripheral()
    @EnvironmentObject var user : User
    //@EnvironmentObject var myID : String
    //@ObservedObject var user: User = User()
    //@EnvironmentObject var log : Log

    @EnvironmentObject var userMessage : UserMessage

    @State var buttontext = "Start"
    @State var runflag = false
    
    init() {
        //print("ContentView init is called")
        //print(self.log)
        //self.bleCentral.myinit(message: self.message)
        // ここでは失敗する。早すぎるみたい。
 
    }
    
    var body: some View {
        let dummy = "2021/01/16 06:58:00.000: some a a a a a messages comes here\n"
        
        NavigationView {

        VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    Button (action: {
                        if (runflag == false) {
                            
                            if (user.CentralMode) {
                                bleCentral.startCentralManager(log: self.log)
                            }
                            if (user.PeripheralMode) {
                                blePeripheral.startPeripheralManager(log: self.log)
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"start button")
                            buttontext = "running"
                            runflag = true
                            
                            //何故か、なくても動く。駄目かな？ないと駄目
                            bleCentral.myinit(userMessage: self.userMessage)
                            blePeripheral.myinit(userMessage: self.userMessage)
                            
                            userMessage.initBLE(bleCentral: self.bleCentral, blePeripheral: self.blePeripheral)
                            
                        } else {
                            if (user.CentralMode) {
                                bleCentral.stopCentralManager()
                            }
                            if (user.PeripheralMode) {
                                blePeripheral.stopPeripheralManager()
                            }
                            blePeripheral.peripheralMode = user.PeripheralMode
                            self.log.addItem(logText:"stop button")
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
                    Text(dummy)
                }.background(Color("lightBackground"))
                .foregroundColor(Color.black)

                Text("Messages")
                    .font(.headline)
                ScrollView(.vertical,showsIndicators: true) {
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
                Text("Central:\(String(user.CentralMode)),Peripheral:\(String(user.PeripheralMode)),myID:\(user.myID)")
            }
            .padding(5)
            .navigationBarTitle("Debug", displayMode: .inline)
            .navigationBarItems(
                trailing:
                    NavigationLink( destination: SettingView()) {
                        Text("setting")
                        
                    }
            )
        }
        .onAppear(perform: {
            UserDefaults.standard.set(user.myID, forKey: "myID")
        })
    }
}

struct ContentView_Previews: PreviewProvider {

    static var user = User()
    
    static var previews: some View {
        ContentView()
            .environmentObject(user)
            .environmentObject(Log())
            .environmentObject(UserMessage())
    }
}
