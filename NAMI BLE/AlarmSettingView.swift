//
//  AlarmSettingView.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/12/06.
//

import SwiftUI

struct AlarmSettingView: View {
    @EnvironmentObject var user: User
    @EnvironmentObject var log : Log
    
    var body: some View {
        ScrollView([.vertical, .horizontal],showsIndicators: true) {
            Text("AlarmSetting")
            VStack {

                HStack {
                    Text("RSSI 1m")
                    Spacer()
                    TextField("", value: $user.rssi1m, formatter: NumberFormatter(),
                              onCommit: {
                        print("onCommit(rssi1m)")
                        print(user.rssi1m)
                        UserDefaults.standard.set(user.rssi1m, forKey: "rssi1m")
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("RSSI 3m")
                    Spacer()
                    TextField("", value: $user.rssi3m,formatter: NumberFormatter(),
                              onCommit: {
                        print("onCommit(rssi3m)")
                        print(user.rssi3m)
                        UserDefaults.standard.set(user.rssi3m, forKey: "rssi3m")
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                
            }
            Text("NAMI BLE (ver.\(versiontext))")
                .padding(20)
            Text("NAMI BLE (ver.\(versiontext))")
                .padding(.bottom, 20)
        }
        .onAppear(perform: {
            print("AlarmSettingView onAppear")
            user.rssi1m = RSSI1mth
            UserDefaults.standard.set(RSSI1mth, forKey: "rssi1m")
            user.rssi3m = RSSI3mth
            UserDefaults.standard.set(RSSI3mth, forKey: "rssi3m")
        })
        .onDisappear(perform: {
            print("AlarmSettingView onDisappear")
            RSSI1mth = user.rssi1m
            RSSI3mth = user.rssi3m
        })
    }
}

struct AlarmSettingView_Previews: PreviewProvider {
    static var user = User()
    
    static var previews: some View {
        AlarmSettingView()
            .environmentObject(user)
            .environmentObject(Log())
    }
}
