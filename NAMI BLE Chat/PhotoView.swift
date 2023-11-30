//
//  PhotoView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2023/11/11.
//
// URLtestのContentView.swiftの処理をコピー

import SwiftUI
import Foundation
import Network
import PhotosUI
import AVKit

struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
        //FileRepresentation(contentType: .item) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let filename = received.file.lastPathComponent
//            let copy = URL.documentsDirectory.appending(path: "movie.mp4")
            let copy = URL.documentsDirectory.appending(path: "upload.mp4")
            print("Movie")
        
            if FileManager.default.fileExists(atPath: copy.path()) {
                try FileManager.default.removeItem(at: copy)
            }
            print("received \(received)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

func URLtest() {
    print("URLtest")
    let url = URL(string: "http://localhost:8010")!  //URLを生成
    let request = URLRequest(url: url)               //Requestを生成
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        guard let data = data else { return }
        do {
            //print(response ?? 9999)
            let contents =  String(data:data,encoding: .ascii)
            print(contents ?? "contents")
            let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
            print(object)
        } catch let error {
            print(error)
        }
    }
    task.resume()

}

func obsolete_POSTtest(filename: String, uiImage: UIImage) -> String? {
    print("POSTtest")
    var retString:String = ""
    
    // boundaryを作る
    let boundary = "----------" + UUID().uuidString
    print(boundary)
    // bocyを作る
    let username = "user00"
    //let filename = "sample.png"
    /*
    guard let image = UIImage(named: filename) else {
        print("image is nil")
        return
    }
     */
    let image = uiImage
    guard let imageData = image.jpegData(compressionQuality: 1) else {
        print("imageData is nil")
        return nil
    }
    var httpBody1 = "--\(boundary)\r\n"
    httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
    httpBody1 += "\r\n"
    httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
    httpBody1 += "--\(boundary)\r\n"
    httpBody1 += "Content-Disposition: form-data; name=\"file\";"
    httpBody1 += "filename=\"\(filename)\"\r\n"
    httpBody1 += "\r\n"
//    httpBody1 += "--\(boundary)\r\n"
//    httpBody1 += "\r\n"
    
    var httpBody = Data()
    httpBody.append(httpBody1.data(using: .utf8)!)
    httpBody.append(imageData)
    
    var httpBody2 = "\r\n"
    httpBody2 += "--\(boundary)--\r\n"

    httpBody.append(httpBody2.data(using: .utf8)!)
    let url = URL(string: "http://localhost:8010/registfile")!  //URLを生成
    var request = URLRequest(url: url)               //Requestを生成
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
    request.httpBody = httpBody
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
        guard let data = data else { return }
        do {
            //print(response ?? 9999)
            let contents =  String(data:data,encoding: .ascii)
            print(contents ?? "contents")
            let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
            print(object)
            guard let obj = object as? [String: Any],
                  let fname = obj["filename"] as? String else {
                      return
                  }
            print(fname)
            retString = fname
        } catch let error {
            print(error)
            retString = ""
        }
    }
    task.resume()

    return retString
}

struct PhotoView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var uiImage: UIImage?
    @State private var ciImage: CIImage?
    @State private var filename:String = ""
    @State private var dummyresult:String = ""
    @State private var inputmessage = ""
    @EnvironmentObject var userMessage : UserMessage
    @State private var sendmsg:String = ""
    @State private var fileIDlink:String = ""
    @Binding var edgeIP: String
    @EnvironmentObject var fileID: FileID
    @EnvironmentObject var user: User
    @State private var active = false

    @State private var movie: Movie?

    enum LoadState {
        case unknown, loading, loaded /*(Movie)*/, failed
    }
    @State private var loadState = LoadState.unknown

    var body: some View {
        Text("Send Message with Photo")
        // URLTestからコピペ
        HStack {
            Text("edge")
            TextField("",text: $edgeIP)
                .overlay(
                    RoundedRectangle(cornerSize: CGSize(width: 8.0, height: 8.0))
                    .stroke(Color.orange, lineWidth: 4.0)
                    .padding(-8.0)
            )
            .padding(16.0)
        }
        HStack {
            PhotosPicker("Select Photo", selection: $selectedPhoto, photoLibrary: .shared())
                .onChange(of: selectedPhoto) {
                    print("onChange")
                    print(selectedPhoto?.itemIdentifier as Any)
                    if let selectedPhoto = selectedPhoto, let localID = selectedPhoto.itemIdentifier {
                        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
                        if let asset = result.firstObject {
                            print("Got " + asset.debugDescription)
                            
                            let resources = PHAssetResource.assetResources(for: asset)
                            if let resource = resources.first {
                                filename = resource.originalFilename
                                print(filename)
                            }
                        }
                    }
                    Task { await loadImageFromSelectedPhoto(photo: selectedPhoto) }
                    
                }
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width:50, height:50)
            }
        }
        
        // videoがloadされたら、ビデオを表示する
        switch loadState {
        case .unknown:
            EmptyView()
        case .loading:
            ProgressView()
            //case .loaded(let movie):
        case .loaded:
            
            VideoPlayer(player: AVPlayer(url: movie!.url))
                .scaledToFit()
                .frame(width: 300, height: 300)
            
            Text("loaded")
        case .failed:
            Text("Import failed")
        }
        
        Button(action:{
            if filename != "" {
                POSTMain(filename: filename, uiImage: uiImage)
            }
        }) {
            Text("post main")
        }

/*
        Button(action:{
            if filename != "" , let uiImage = uiImage {
                POSTtest(filename: filename, uiImage: uiImage)
            }
        }) {
            Text("post")
        }
 */
        Text(dummyresult)
        ScrollView(.vertical,showsIndicators: true) {
            
            TextField("your message",
                      text: $inputmessage,
                      onCommit: {
//                sendmsg = inputmessage + fileIDlink
                print("onCommit:\(sendmsg)")
            })
        }.background(Color("lightBackground"))
            .foregroundColor(Color.black)
            .frame(height:50)
        Button (action: {
            sendmsg = inputmessage + fileIDlink
            print("Button:\(inputmessage),\(sendmsg)")
            // 何故か inputmessage だと、うまくいかない。dispmsgだとうまくいく
            if sendmsg != "" {
                print("SEND: \(sendmsg)")
                self.userMessage.addItem(userMessageText: sendmsg)
                inputmessage = ""
                
            }
        }) {
            Text("SEND")
        }
        Text(.init(sendmsg))
            .environment(\.openURL,
                          OpenURLAction { url in
                print("OpenURLAction with \(url.absoluteString)")
                fileID.name = url.absoluteString
                active.toggle()
                //return .discarded
                return .handled
            })
            .sheet(isPresented: $active, onDismiss: didDismiss) {
                PhotoShow(edgeIP: $edgeIP)
            }
    }
    
    func didDismiss() {
        print("didDismiss")
    }

    private func loadImageFromSelectedPhoto(photo: PhotosPickerItem?) async {
        // 写真の次にビデオを選んだときのために nil にしておく。逆も同じ。
        self.uiImage = nil
        self.loadState = .unknown
        self.movie = nil
        // VideoTestからコピペ
        // .videoは音声なし。.movieはどっちも含むらしい
        // https://fromatom.hatenablog.com/entry/2022/08/09/010206
        if ((photo!.supportedContentTypes.contains(where: { type in type.isSubtype(of: .movie)}))){
            print("audio visual")
//            print(photo?.supportedContentTypes)
            Task {
                do {
                    loadState = .loading
                    

//                                    if let movie = try await selectedItem?.loadTransferable(type: Movie.self) {
                    if let movie = try await photo?.loadTransferable(type: Movie.self) {
                        print("movie is not nil")
                        self.movie = movie
                        print("self.movie is \(self.movie!.url.absoluteString)")

                        loadState = .loaded /*(movie)*/
                    } else {
                        print("movie is nil")
                        loadState = .failed
                    }
                } catch {
                    loadState = .failed
                }
            }
        } else if ((photo!.supportedContentTypes.contains(where: { type in type.isSubtype(of: .image)}))){
            print("image")
            //            print(photo?.supportedContentTypes)
            if let data = try? await photo?.loadTransferable(type: Data.self) {
                print("uiImage is not nil")
                self.uiImage = UIImage(data: data)
                self.ciImage = CIImage(data: data)

                print("get uiImage")
                if self.uiImage == nil {
                    print("but uiImage is nil")
                }
                
                
            } else {
                print("uiImage is nil")
            }
        }
    }
    /* old */
    /*
    private func loadImageFromSelectedPhoto(photo: PhotosPickerItem?) async {
        if let data = try? await photo?.loadTransferable(type: Data.self) {
                self.uiImage = UIImage(data: data)
                self.ciImage = CIImage(data: data)
        }
    }
     */
    
    func POSTMain(filename: String, uiImage: UIImage??){
        print("POSTMain")
        if self.uiImage != nil {
            print("photo")
            POSTtest(filename: filename, uiImage: self.uiImage)
        } else {
            print("movie")
            POSTtest2()
        }
    }
    
    func POSTtest2() {
            print("POSTtest2")
            
    //        let videoClipPath = url.absoluteString
    //        let videoClipName = url.lastPathComponent
    //        print(videoClipName)
            /// ①DocumentsフォルダURL取得
            guard let dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("フォルダURL取得エラー")
            }
            
            /// ②対象のファイルURL取得
            let fileURL = dirURL.appendingPathComponent("upload.mp4")
            
            guard let fileContents = try? Data(contentsOf: fileURL) else {
                print("ファイル読み込みエラー")
                return
            }

            // boundaryを作る
            let boundary = "----------" + UUID().uuidString
            print(boundary)
            // bocyを作る
            // for debug
            //let username:String = user.myID
            let username="usr00"
            print(username)
            // GPS情報(Exif情報)を残すために上を下に変更する
            /*
            guard let imageData = CIContext().jpegRepresentation(
                of: ciImage!,
                colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                options: [:]) else {
                print("imageData is nil")
                return
                }
             */
            /*
            let image = self.uiImage
            if image == nil {
                print("image is nil")
                return
            }
            guard let imageData = image!.jpegData(compressionQuality: 1) else {
                print("imageData is nil")
                return
            }
            */

            var httpBody1 = "--\(boundary)\r\n"
            httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
            httpBody1 += "--\(boundary)\r\n"
            httpBody1 += "Content-Disposition: form-data; name=\"file\";"
            httpBody1 += "filename=\"\(self.filename)\"\r\n"
            httpBody1 += "\r\n"
    //        httpBody1 += "--\(boundary)\r\n"
    //        httpBody1 += "\r\n"
    // 上の２行がファイルに含まれてしまう
            
            var httpBody = Data()
            httpBody.append(httpBody1.data(using: .utf8)!)
    //        httpBody.append(imageData)
            httpBody.append(fileContents)
            
            var httpBody2 = "\r\n"
            httpBody2 += "--\(boundary)--\r\n"

            httpBody.append(httpBody2.data(using: .utf8)!)
            let url = URL(string: "http://"+edgeIP+":8010/registfile")!
            print(url)
            //URLを生成
            var request = URLRequest(url: url)               //Requestを生成
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = httpBody
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
                guard let data = data else { return }
                do {
                    //print(response ?? 9999)
                    let contents =  String(data:data,encoding: .ascii)
                    print(contents ?? "contents")
                    let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
                    print(object)
                    guard let obj = object as? [String: Any],
                          let fname = obj["filename"] as? String else {
                              return
                          }
                    print(fname)
    // for debug
                    fileIDlink = " [Link](\(fname))"
                    dummyresult = fname
                    fileIDlink = " [Link](\(fname))"
                    // 動画の場合は、セーブしない（とりあえず）
                    // 本当は rename するのが良いと思われる
                    /*
                    SaveToDoc(filename: fname, uiImage: uiImage)
                     */

                } catch let error {
                    print(error)
                }
            }
            task.resume()
        }

                
        func POSTtest(filename: String, uiImage: UIImage??) {
            print("POSTtest")
            
            // boundaryを作る
            let boundary = "----------" + UUID().uuidString
            print(boundary)
            // bocyを作る
            // for debug
            //let username:String = user.myID
            let username="usr0"
            print(username)
            // GPS情報(Exif情報)を残すために上を下に変更する
            guard let imageData = CIContext().jpegRepresentation(
                of: ciImage!,
                colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                options: [:]) else {
                print("imageData is nil")
                return
                }
            
            var httpBody1 = "--\(boundary)\r\n"
            httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
            httpBody1 += "--\(boundary)\r\n"
            httpBody1 += "Content-Disposition: form-data; name=\"file\";"
            httpBody1 += "filename=\"\(filename)\"\r\n"
            httpBody1 += "\r\n"
    //        httpBody1 += "--\(boundary)\r\n"
    //        httpBody1 += "\r\n"
    // 上の２行がファイルに含まれてしまう
            
            var httpBody = Data()
            httpBody.append(httpBody1.data(using: .utf8)!)
            httpBody.append(imageData)
            
            var httpBody2 = "\r\n"
            httpBody2 += "--\(boundary)--\r\n"

            httpBody.append(httpBody2.data(using: .utf8)!)
            let url = URL(string: "http://"+edgeIP+":8010/registfile")!
            print(url)
            //URLを生成
            var request = URLRequest(url: url)               //Requestを生成
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = httpBody
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
                guard let data = data else { return }
                do {
                    //print(response ?? 9999)
                    let contents =  String(data:data,encoding: .ascii)
                    print(contents ?? "contents")
                    let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
                    print(object)
                    guard let obj = object as? [String: Any],
                          let fname = obj["filename"] as? String else {
                              return
                          }
                    print(fname)
                    dummyresult = fname
                    fileIDlink = " [Link](\(fname))"
                    sendmsg = fileIDlink
                    SaveToDoc(filename: fname, uiImage: uiImage!!)

                } catch let error {
                    print(error)
                }
            }
            task.resume()
        }
// old
    /*
    func POSTtest(filename: String, uiImage: UIImage) {
        print("POSTtest")
        
        // boundaryを作る
        let boundary = "----------" + UUID().uuidString
        print(boundary)
        // bocyを作る
        let username:String = user.myID
        print(username)
        //let filename = "sample.png"
        /*
        guard let image = UIImage(named: filename) else {
            print("image is nil")
            return
        }
         */
        /*
        let image = uiImage
        guard let imageData = image.jpegData(compressionQuality: 1) else {
            print("imageData is nil")
            return
        }
         */
        // GPS情報(Exif情報)を残すために上を下に変更する
        guard let imageData = CIContext().jpegRepresentation(
            of: ciImage!,
            colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [:]) else {
            print("imageData is nil")
            return
            }
        
        var httpBody1 = "--\(boundary)\r\n"
        httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
        httpBody1 += "\r\n"
        httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
        httpBody1 += "--\(boundary)\r\n"
        httpBody1 += "Content-Disposition: form-data; name=\"file\";"
        httpBody1 += "filename=\"\(filename)\"\r\n"
        httpBody1 += "\r\n"
//        httpBody1 += "--\(boundary)\r\n"
//        httpBody1 += "\r\n"
// 上の２行がファイルに含まれてしまう
        
        var httpBody = Data()
        httpBody.append(httpBody1.data(using: .utf8)!)
        httpBody.append(imageData)
        
        var httpBody2 = "\r\n"
        httpBody2 += "--\(boundary)--\r\n"

        httpBody.append(httpBody2.data(using: .utf8)!)
        let url = URL(string: "http://"+edgeIP+":8010/registfile")!
        print(url)
        //URLを生成
        var request = URLRequest(url: url)               //Requestを生成
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = httpBody
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            guard let data = data else { return }
            do {
                //print(response ?? 9999)
                let contents =  String(data:data,encoding: .ascii)
                print(contents ?? "contents")
                let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)  // DataをJsonに変換
                print(object)
                guard let obj = object as? [String: Any],
                      let fname = obj["filename"] as? String else {
                          return
                      }
                print(fname)
                dummyresult = fname
                fileIDlink = " [Link](\(fname))"
                
                SaveToDoc(filename: fname, uiImage: uiImage)

            } catch let error {
                print(error)
            }
        }
        task.resume()
    }
     */
    
    func SaveToDoc(filename: String, uiImage: UIImage) {
        print("SaveToDoc called")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard let imageData = CIContext().jpegRepresentation(
            of: ciImage!,
            colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [:]) else {
            print("imageData is nil")
            return
            }
        do {
            try imageData.write(to: fileURL)
            print("SaveToDoc Done")
        } catch {
            print("SaveToDoc error")
        }
    }

    
}


#Preview {
    PhotoView( edgeIP: .constant("#Preview"))
}

