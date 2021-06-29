//
//  SettingView.swift
//  BLEcommTest0
//
//  Created by Tadashi Ogino on 2021/01/16.
//

import SwiftUI

struct SettingView: View {
    @EnvironmentObject var user: User
    
    var body: some View {
        
        VStack {
            HStack {
                Text("Central Mode")
                Spacer()
                Toggle(isOn: $user.CentralMode) {
                    EmptyView()
                }
            }
            HStack {
                Text("Peripheral Mode")
                Spacer()
                Toggle(isOn: $user.PeripheralMode) {
                    EmptyView()
                }
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
        }.padding(5)
        .onDisappear(perform: {
            print("onDisappear called in SettingView")
            UserDefaults.standard.set(user.myID, forKey: "myID")
        })
    }
}

struct SettingView_Previews: PreviewProvider {
    static var user = User()
    
    static var previews: some View {
        SettingView()
            .environmentObject(user)
    }
}
