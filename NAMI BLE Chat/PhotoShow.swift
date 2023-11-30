//
//  PhotoShow.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2023/11/15.
//

import SwiftUI

class FileID: ObservableObject {
    @Published var name: String = "initial"
}

struct PhotoShow: View {
    @EnvironmentObject private var fileID: FileID
    @Binding var edgeIP: String
    
    var body: some View {
        Text("PhotoShow")
        Text("FileID:\(fileID.name)")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileID.name)

        //Text(fileURL.path)
        let fname = fileID.name
        let checkfile = checkFile(fname: fname)
//        if FileManager.default.fileExists(atPath: fileURL.path) {
        if checkfile {
            AsyncImage(url: fileURL) { image  in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
        } else {
            Text("file not found")
        }

    }
    
    func checkFile(fname: String) -> Bool {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileID.name)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return true
        } else {
            // ファイルが存在しない時は、そのファイルをリクエストしてから
            // false を返す
            fileRequest(fname: fname)
            return false
        }
    }
    
    func fileRequest(fname: String) {
        print("fileRequest to ")
        print(edgeIP)
        
        let url = URL(string: "http://"+edgeIP+":8010/getfile/"+fname)!  //URLを生成
        let request = URLRequest(url: url)               //Requestを生成
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            guard let data = data else { return }
            do {
                //print(response ?? 9999)
                let contents =  String(data:data,encoding: .ascii)
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
    PhotoShow(edgeIP: .constant("#Preview"))
}
