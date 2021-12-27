//
//  SettingView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI

struct SettingView: View {
    @EnvironmentObject var user: User
    @EnvironmentObject var log : Log
    @State var uploadfname : String
    
    var body: some View {
        ScrollView([.vertical, .horizontal],showsIndicators: true) {
            VStack {
                HStack() {
                    Text("Central Mode")
                    Toggle(isOn: $user.CentralMode) {
                        EmptyView()
                    }
                    Text("Connect")
                    Toggle(isOn: $user.ConnectMode) {
                        EmptyView()
                    }
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                }
                HStack() {
                    Text("Peripheral Mode")
                    Toggle(isOn: $user.PeripheralMode) {
                        EmptyView()
                    }
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                }
                HStack() {
                    Text("iPhone only")
                    Toggle(isOn: $user.iPhoneMode) {
                        EmptyView()
                    }
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                }
                HStack() {
                    Text("Auto Mode")
                    Toggle(isOn: $user.AutoMode) {
                        EmptyView()
                    }
                    Text("Debug Log")
                    Toggle(isOn: $user.debugLogMode) {
                        EmptyView()
                    }
                    Rectangle()
                        .fill(Color.white)
                        .frame(minWidth: 0.0, maxWidth: .infinity)
                        .frame(height: 0)
                }
                HStack {
                    Text("MyID")
                    Spacer()
                    TextField("", text: $user.myID,
                              onCommit: {
                        print("onCommit")
                        print(user.myID)
                        UserDefaults.standard.set(user.myID, forKey: "myID")
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("TimerInterval")
                    Spacer()
                    TextField("", text: $user.timerInterval,
                              onCommit: {
                        print("onCommit")
                        print(user.timerInterval)
                        UserDefaults.standard.set(user.timerInterval, forKey: "timerInterval")
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("ObsoluteInterval")
                    Spacer()
                    TextField("", text: $user.obsoleteInterval,
                              onCommit: {
                        print("onCommit")
                        print(user.obsoleteInterval)
                        UserDefaults.standard.set(user.obsoleteInterval, forKey: "obsoleteInterval")
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack {
                    Button (action: {
                        self.log.upload(fname: uploadfname)
                    }) {
                        Text("UploadLog")
                        // テキストのサイズを指定
                            .frame(width: 160, height: 40, alignment: .center)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.yellow, lineWidth: 2)
                            )}
                    
                    Button (action: {
                        self.log.writeToFile(fname: uploadfname)
                    }) {
                        Text("WriteToFile")
                        // テキストのサイズを指定
                            .frame(width: 140, height: 40, alignment: .center)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.yellow, lineWidth: 2)
                            )}
                }
                
                TextField("file name",
                          text: $uploadfname,
                          onCommit: {
                    print("uploadfname:\(uploadfname)")
                })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button (action: {
                    self.log.rmlocal(fname: "NAMI.log")
                }) {
                    Text("ClearLog")
                    // テキストのサイズを指定
                        .frame(width: 160, height: 40, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )}
            }
            Text("NAMI BLE Chat (ver.\(versiontext))")
                .padding(20)
            Text("NAMI BLE Chat (ver.\(versiontext))")
                .padding(.bottom, 20)
        }.padding(5)
            .onAppear(perform: {
                let now = Date() // 現在日時の取得
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "ja_JP") // ロケールの設定
                dateFormatter.dateFormat = "yyyyMMddHHmmssSSS"
                let logfname = dateFormatter.string(from: now)+"-"+user.myID+".log" // -> 20210120195717234.log
                print(logfname)
                uploadfname = logfname
                user.ConnectMode = ConnectMode
                user.iPhoneMode = iPhoneMode
                user.debugLogMode = debugLogMode

                self.log.addItem(logText: "enterSetting, INFO, 0000, , \(user.timerInterval), \(user.obsoleteInterval)")
                
            })
            .onDisappear(perform: {
                print("onDisappear called in SettingView")
                UserDefaults.standard.set(user.myID, forKey: "myID")
                UserDefaults.standard.set(user.timerInterval, forKey: "timerInterval")
                UserDefaults.standard.set(user.obsoleteInterval, forKey: "obsoluteInterval")
                UserDefaults.standard.set(user.iPhoneMode, forKey: "iPhoneMode")
                UserDefaults.standard.set(user.debugLogMode, forKey: "debugLogMode")
                ConnectMode = user.ConnectMode
                iPhoneMode = user.iPhoneMode
                debugLogMode = user.debugLogMode
                
                self.log.addItem(logText: "exitSetting, INFO, 0000, , \(user.timerInterval), \(user.obsoleteInterval)")
                
            })
    }
}

struct SettingView_Previews: PreviewProvider {
    static var user = User()
    
    static var previews: some View {
        SettingView( uploadfname: "202107041425000.log")
            .environmentObject(user)
            .environmentObject(Log())
    }
}
