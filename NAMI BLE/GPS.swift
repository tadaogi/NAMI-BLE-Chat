//
//  GPS.swift
//  NAMI BLE
//
//  Created by Tadashi Ogino on 2021/07/08.
//

import Foundation
import CoreLocation


class GPS: NSObject, CLLocationManagerDelegate{
    
    var locationManager: CLLocationManager!
    var timer: Timer? = nil
    
    override init(){
        super.init()
        print("GPS.init()")
        
        locationManager = CLLocationManager()
        
        locationManager.requestWhenInUseAuthorization()
        
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true; // バックグランドモードで使用する場合YESにする必要がある
        locationManager.desiredAccuracy = kCLLocationAccuracyBest; // 位置情報取得の精度
        
        //locationManager.startUpdatingLocation() // 連続で返ってくる
        //locationManager.requestLocation() // １回だけ返ってくる
        
        timerStart(timerInterval: 60) // 60秒に1回呼ばれる

    }
    
    func locationManager(_ manager: CLLocationManager,
                didUpdateLocations locations: [CLLocation]) {
        print("didUpdateLocations")
        
        if let glog = GlobalVar.shared.gLog {
            glog.addItem(logText: "didUpdateLocations")
            print("didUpdateLocations with glob != nil")
        } else {
            print("didUpdateLocations with glog = nil")
        }
        // 最初のデータ
        let location = locations.first
 
        // 緯度
        let latitude = location?.coordinate.latitude
        // 経度
        let longitude = location?.coordinate.longitude
 
        print("latitude: \(latitude!)")
        print("longitude: \(longitude!)")
        
        if let glog = GlobalVar.shared.gLog {
            glog.addItem(logText: "didUpdateLocations, GPS, 0000, , \(latitude!), \(longitude!)")
        }
        //locationManager.stopUpdatingLocation() // 何故か繰り返しになってしまうので止める -> １回になった。なぜか不明

    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError: \(error)")
        
        if let glog = GlobalVar.shared.gLog {
            glog.addItem(logText: "didUpdateLocations(error), GPS, 0000, , -1, -1, \(error)")
        }

    }
    
    
    func timerStart (timerInterval: Int) {
        print("GPS.timerStart()")
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timerInterval ), repeats: true, block: { [self]_ in
            print("GPS timer called")
            locationManager.requestLocation() // １回だけ返ってくる
        })
    }
    
    func timerStop () {
        print("GPS.timerStop()")
        timer?.invalidate()
    }
}
