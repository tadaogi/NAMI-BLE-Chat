//
//  PhotoShow.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2023/11/15.
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit

class FileID: ObservableObject {
    @Published var name: String = "initial"
}

struct PhotoShow: View {
    @EnvironmentObject private var fileID: FileID
    //@Binding var edgeIP: String
    @EnvironmentObject var wifi: WiFi
    @State var checkfile = false
    
    var body: some View {
        Text("PhotoShow")
        Text("FileID:\(fileID.name)")
            .onAppear {
                print("PhotoShow onAppear")
                let fname = fileID.name
                self.checkfile = checkFile(fname: fname)
                // ここなら１回しか呼ばれないので、こっちに移す
            }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileID.name)

        //Text(fileURL.path)
        //let fname = fileID.name
        // checkfile が２回呼ばれるののデバッグで、上のonAppearに移してみる
        //let checkfile = checkFile(fname: fname)
//        if FileManager.default.fileExists(atPath: fileURL.path) {
        if checkfile {
            if UTType(filenameExtension: fileURL.pathExtension)!.conforms(to: .image) {
                AsyncImage(url: fileURL) { image  in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
            } else if UTType(filenameExtension: fileURL.pathExtension)!.conforms(to: .movie) {
                Text("movie")
                VideoPlayer(player: AVPlayer(url: fileURL))
                    .scaledToFit()
                    .frame(width: 300, height: 300)
            } else {
                Text("unknown type")
            }

// old
            /*
            AsyncImage(url: fileURL) { image  in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
             */
        } else {
            Text("file not found")
        }

    }
    
    func checkFile(fname: String) -> Bool {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileID.name)

        print("checkFile \(fname)")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("checkFile true")
            return true
        } else {
            // ファイルが存在しない時は、そのファイルをリクエストしてから
            // false を返す
            // fileRequest(fname: fname)
            // ロジックを WiFi に移す
            wifi.fileRequest(fname: fname)
            print("checkFile false")
            return false
        }
    }
    
    func fileRequest(fname: String) {
        print("fileRequest to ")
        print(wifi.edgeIP)
        
        let url = URL(string: "http://"+wifi.edgeIP+":8010/getfile/"+fname)!  //URLを生成
        let request = URLRequest(url: url)               //Requestを生成
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            guard let data = data else { return }
            do {
                //print(response ?? 9999)
                //let contents =  String(data:data,encoding: .ascii)
                //print(contents ?? "contents")
                let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]  // DataをJsonに変換
                //print(object)
                let datastr = object["data"] as! String
                print(datastr)
                let restoreData = Data(base64Encoded: datastr)
                SaveToDocData(filename: fname, data: restoreData!)
            } catch let error {
                print(error)
            }
        }
        task.resume()

    }
    
    func SaveToDocData(filename: String, data: Data) {
        print("SaveToDoc called")
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

#Preview {
    PhotoShow()
}
