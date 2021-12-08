//
//  ThreeCsView.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/08/09.
//

import SwiftUI


struct AlertBar: View {
    var i: Int
    var width: Int
    var height:CGFloat = 30.0
    
    init(i: Int, width: Int) {
        self.i = i
        self.width = width
    }
    var body: some View {
            ZStack (alignment: .trailing) {
                HStack(spacing: 0) {
                    if self.i == 1 {
                        Text("")
                            .frame(width: CGFloat(self.width) , height: self.height)
                            .background(Color.blue)
                    } else if self.i == 2 {
                        Text("")
                            .frame(width: CGFloat(self.width), height: self.height)
                            .background(Color.yellow)
                    } else {
                        Text("")
                            .frame(width: CGFloat(self.width), height: self.height)
                            .background(Color.red)
                    }
                }
                Rectangle()
                    .foregroundColor(.white)
                    .frame(width:CGFloat(CGFloat(self.width)*CGFloat(3-self.i))/3, height: self.height)
        }
    }
}


struct ThreeCsView: View {
    @EnvironmentObject var devices : Devices

    var body: some View {
        NavigationView {
            ScrollView(.vertical,showsIndicators: true) {
                VStack {
                    /*
                     Text("Three Cs View")
                     .font(.title)
                     //.multilineTextAlignment(.center)
                     .padding()
                     */
                    VStack {
                        HStack() {
                            Text("Information")
                                .font(.title2)
                                .offset(x: 10)
                            Spacer()
                        }
                        
                        HStack() {
                            Text("Num of Devices : ")
                            let count = devices.devicelist.count
                            Text(String(format: "%d",count))
                        }
                        
                        HStack() {
                            Text("Num of iPhone : ")
                            let count = devices.countiPhone()
                            Text(String(format: "%d",count))
                        }
                        //.padding()
                    }
                    HStack() {
                        
                        Text("Crowded")
                            .font(.title2)
                            .offset(x: 10)
                        Spacer()
                    }
                    .padding(.top)
                    HStack() {
                        Text("Close Devices : ")
                        Text(String(format: "%d,%d", devices.closeDeviceCount,devices.closeDeviceScore))
                    }
                    .alert(isPresented: $devices.showAlert) {  // ③アラートの表示条件設定
                        Alert(title: Text("Close alert"))     // ④アラートの定義
                    }
                    
                    GeometryReader { bodyView in
                        // AlertBarだと、変数をうまくわたせないので直接書いてみた
                        //                AlertBar(i:$devices.closeDevceScore, width:Int(bodyView.size.width))
                        ZStack (alignment: .trailing) {
                            HStack(spacing: 0) {
                                if devices.closeDeviceScore == 1 {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width) , height: 30)
                                        .background(Color.blue)
                                } else if devices.closeDeviceScore == 2 {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width), height: 30)
                                        .background(Color.yellow)
                                } else {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width), height: 30)
                                        .background(Color.red)
                                }
                            }
                            Rectangle()
                                .foregroundColor(.white)
                                .frame(width:CGFloat(CGFloat(bodyView.size.width)*CGFloat(3-devices.closeDeviceScore))/3, height: 30)
                        }
                    }
                    .padding(.horizontal)
                    HStack() {
                        Text("Close-contact")
                            .font(.title2)
                            .offset(x: 10)
                        Spacer()
                    }
                    .padding(.top)
                    HStack() {
                        Text("Close and Long Devices : ")
                        Text(String(format: "%d,%d", devices.closeLongDeviceCount, devices.closeLongDeviceScore))
                        
                        
                    }
                    .alert(isPresented: $devices.showLongAlert) {  // ③アラートの表示条件設定
                        Alert(title: Text("Close and Long alert"))     // ④アラートの定義
                    }
                    GeometryReader { bodyView in
                        //                AlertBar(i:3, width:Int(bodyView.size.width))
                        ZStack (alignment: .trailing) {
                            HStack(spacing: 0) {
                                if devices.closeLongDeviceScore == 1 {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width) , height: 30)
                                        .background(Color.blue)
                                } else if devices.closeLongDeviceScore == 2 {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width), height: 30)
                                        .background(Color.yellow)
                                } else {
                                    Text("")
                                        .frame(width: CGFloat(bodyView.size.width), height: 30)
                                        .background(Color.red)
                                }
                            }
                            Rectangle()
                                .foregroundColor(.white)
                                .frame(width:CGFloat(CGFloat(bodyView.size.width)*CGFloat(3-devices.closeLongDeviceScore))/3, height: 30)
                        }
                    }
                    .padding(.horizontal)
                    
                    //Spacer()
                    HStack() {
                        Text("Closed spaces")
                            .font(.title2)
                            .offset(x: 10)
                        Spacer()
                    }
                    .padding(.top)
                    //HStack {
                    Text("Not implemented yet... ")
                    //    Text(String(format: ""))
                    //}
                    /*
                     GeometryReader { bodyView in
                     AlertBar(i:0, width:Int(bodyView.size.width))
                     }
                     .padding(.horizontal)
                     */
                    GeometryReader { bodyView in
                        Text("")
                            .frame(width: CGFloat(bodyView.size.width*0.9), height: 30)
                            .background(Color(red:0.7, green:0.7, blue:0.7, opacity:1.0))
                            .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitle("3Cs alarm", displayMode: .inline)
            .navigationBarItems(
                trailing:
                    NavigationLink( destination: AlarmSettingView()) {
                        Text("AlarmSetting")
                        
                    }
            )

        }
    }
}

/*
func closeDevice(devicelist:[DeviceItem])->Int {
    var ccount = 0
    for device in devicelist {
        let rssi = device.rssi ?? (-100)
        if Int(truncating: rssi) > -50 {
            ccount = ccount + 1
        }
    }
    
    return ccount
}

func closeAndLongDevice(devicelist:[DeviceItem])->Int {
    var ccount = 0
    let now = Date()
    for device in devicelist {
        let rssi = device.rssi ?? (-100)
        if Int(truncating: rssi) > -50 {
            // 最初の検出から 900 秒以上たっていて、
            // 最後の検出から 300 秒以上たっていない
            if (now.timeIntervalSince1970 - device.lastDate.timeIntervalSince1970 < 300)
                && (now.timeIntervalSince1970 - device.firstDate.timeIntervalSince1970 > 900) {
                ccount = ccount + 1
            }
        }
    }
    
    return ccount
}
 */

struct ThreeCsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            /// 以下の行を追加
            ForEach(["iPhone SE (2nd generation)", "iPhone 6s Plus", "iPad Pro (9.7-inch)"], id: \.self) { deviceName in
                ThreeCsView()
                    .environmentObject(Devices())
            }
        }
    }
}
