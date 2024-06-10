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

// CIImageのresize
// https://qiita.com/john-rocky/items/7ad3898174ee54e5c345
extension CIImage {
    func resize(width: Double) -> CIImage {
        // オリジナル画像のサイズからアスペクト比を計算
        let aspectScale = extent.size.height / extent.size.width
        
        // widthからアスペクト比を元にリサイズ後のサイズを取得
        let resizedSize = CGSize(width: width, height: width * Double(aspectScale))
 
        let selfSize = extent.size
        let transform = CGAffineTransform(scaleX: resizedSize.width / selfSize.width, y: resizedSize.height / selfSize.height)
        return transformed(by: transform)
    }
}

// CGImageのresize
extension CGImage {
    func resize(width: Double) -> CGImage? {
        // オリジナル画像のサイズからアスペクト比を計算
        let aspectScale = self.height / self.width
        
        // widthからアスペクト比を元にリサイズ後のサイズを取得
        let resizedSize = CGSize(width: width, height: width * Double(aspectScale))

        let width: Int = Int(resizedSize.width)
        let height: Int = Int(resizedSize.height)

        let bytesPerPixel = self.bitsPerPixel / self.bitsPerComponent
        let destBytesPerRow = width * bytesPerPixel


        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: self.bitsPerComponent, bytesPerRow: destBytesPerRow, space: colorSpace, bitmapInfo: self.alphaInfo.rawValue) else { return nil }

        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }
}

struct PhotoView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var uiImage: UIImage?
    @State private var thumbnailImage: UIImage?
    @State private var thumbnailJpeg: Data?
    
    @State private var ciImage: CIImage?
    @State private var filename:String = ""
    @State private var dummyresult:String = ""
    @State private var inputmessage = ""
    @EnvironmentObject var userMessage : UserMessage
    @State private var sendmsg:String = ""
    @State private var fileIDlink:String = ""
    //@Binding var edgeIP: String
    @EnvironmentObject var wifi: WiFi
    @EnvironmentObject var fileID: FileID
    @EnvironmentObject var user: User
    @State private var active = false
    //@Binding var PhotoSheet: Bool
    @Environment(\.presentationMode) var presentationMode
    
    @State private var movie: Movie?
    
    @State private var TBDfileID = ""

    enum LoadState {
        case unknown, loading, loaded /*(Movie)*/, failed
    }
    @State private var loadState = LoadState.unknown

    var body: some View {
        ScrollView([.vertical],showsIndicators: true) {
            Text("Send Message with Photo")
            // URLTestからコピペ
            HStack {
                Text("edge")
                TextField("",text: $wifi.edgeIP)
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
                        Task {
                            await loadImageFromSelectedPhoto(photo: selectedPhoto)
                            print("photo ready")
                            if let ciImage = ciImage {
                                thumbnailImage = MakeThumbnailFromCIImage(ciImage: ciImage)!
                            }
                        }
                        
                    }
                if let uiImage = uiImage {
                    Image(uiImage: resize(image: uiImage, width: 50))
                    /*
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width:50, height: 50)
                     */
                
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
            
            if let thumbnailImage = thumbnailImage {
                HStack {
                    Text("Thumbnail ")
                    Image(uiImage: thumbnailImage)
                    
                }
            }


            
            Button(action:{
                if filename != "" {
                    POSTMain(filename: filename, uiImage: uiImage)
                } else {
                    print("filename is nil")
                }
            }) {
                Text("post main")
            }
            
            // BLEで画像データを送るためのテスト
            Button(action:{
                // postしないとファイル名は決まらないので
                // ダミーでいれる
                filename = "debug.jpg"
                if filename != "" {
                    BLEsend(filename: filename, uiImage: uiImage)
                } else {
                    print("filename is nil")
                }
            }) {
                Text("BLEsend TEST")
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
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
                print("close in photoview")
            }) {
                Text("Close")
            }
            Button(action: {
                print("rename test")
                RenameMovieFile(FromFilename: "upload.mp4", ToFilename: TBDfileID)
            }) {
                Text("rename test")
            }
                .environment(\.openURL,
                              OpenURLAction { url in
                    print("OpenURLAction with \(url.absoluteString)")
                    fileID.name = url.absoluteString
                    active.toggle()
                    //return .discarded
                    return .handled
                })
                .sheet(isPresented: $active, onDismiss: didDismiss) {
                    //PhotoShow(edgeIP: $wifi.edgeIP)
                    PhotoShow()
                }
        }
    }
    
    // UIImageのresize
    // https://program-life.com/497
    func resize(image: UIImage, width: Double) -> UIImage {
            
        // オリジナル画像のサイズからアスペクト比を計算
        let aspectScale = image.size.height / image.size.width
        
        // widthからアスペクト比を元にリサイズ後のサイズを取得
        let resizedSize = CGSize(width: width, height: width * Double(aspectScale))
        
        // リサイズ後のUIImageを生成して返却
        UIGraphicsBeginImageContext(resizedSize)
        image.draw(in: CGRect(x: 0, y: 0, width: resizedSize.width, height: resizedSize.height))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage!
    }
    
    func didDismiss() {
        print("didDismiss")
    }
    
    // 動作確認用 本体はwifi.swiftへ移動
    /*
    func obsolute_uploadtest(fileName: String) {
        print("uploadtest")
        //let fileName = "DSCF0085.JPG"
        let fileNameWithoutExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
         
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)

        // 読み込んだJPEGファイルをそのままアップロード
        //let imageData = try! Data(contentsOf: Bundle.main.url(forResource: fileNameWithoutExt, withExtension: ext)!)
        print(fileURL)
        let imageData = try! Data(contentsOf: (fileURL))
        
        // POSTtestから流用
        // boundaryを作る
        let boundary = "----------" + UUID().uuidString
        print(boundary)

        
        var httpBody1 = "--\(boundary)\r\n"
        httpBody1 += "Content-Disposition: form-data; name=\"file\";"
        httpBody1 += "filename=\"\(fileName)\"\r\n"
        httpBody1 += "\r\n"
  
        var httpBody = Data()
        httpBody.append(httpBody1.data(using: .utf8)!)
        httpBody.append(imageData)
        var httpBody2 = "\r\n"
        httpBody2 += "--\(boundary)--\r\n"

        httpBody.append(httpBody2.data(using: .utf8)!)
        let url = URL(string: "http://127.0.0.1:8010/registfileUwithID")!
        print(url)

        //URLを生成
        var request = URLRequest(url: url)               //Requestを生成
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = httpBody
        request.timeoutInterval = 1.0 // for debug

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
            if let error = error {
                print("request failure: \(error)")
                let nsError = error as NSError
                print(nsError)
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                    print("timeout in uploadtest")
                }
                return
            }
            guard let data = data else { return }
            print(response ?? 9999)
            print("success in uploadtest")
        }
        task.resume()
    }
     */

    private func loadImageFromSelectedPhoto(photo: PhotosPickerItem?) async {
        // 写真の次にビデオを選んだときのために nil にしておく。逆も同じ。
        self.uiImage = nil
        self.ciImage = nil
        self.thumbnailImage = nil
        self.thumbnailJpeg = nil
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
                        
                        self.thumbnailImage = MakeThumbnailFromVideo()
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
    
    
    func BLEsend(filename: String, uiImage: UIImage??) {
        print("BLEsend")
        if self.uiImage != nil {
            print("photo")
            BLEsendPhoto(filename: filename)
        } else {
            print("BLEsend movie (not implemented yet)")
            BLEsendVideo()
        }
    }
    
    // POSTtest2を参照
    func BLEsendVideo() {
        /// ①DocumentsフォルダURL取得
        guard let dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("フォルダURL取得エラー")
        }
        
        /// ②対象のファイルURL取得
        let fileURL = dirURL.appendingPathComponent("upload.mp4")
        print(fileURL)
        // https://qiita.com/1997/items/d0bcb3d9d5209bbe3db0
        // https://mixltd.jp/blog/ios_get_movie_thumbnail/
        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // サムネイル生成
//        let avAsset = AVAsset(url: url)
//        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
//        let duration = asset.duration
        //let duration = try? asset.load(.duration)
        let seconds = 0.0 // 5秒で指定
//        let time = CMTime(seconds: seconds, preferredTimescale: duration.timescale)
        let time = CMTime(seconds: seconds, preferredTimescale: 60)
        let capturedImage = try! generator.copyCGImage(at: time, actualTime: nil)
        let thumbnailimage = UIImage(cgImage: capturedImage)
        DispatchQueue.main.async {
            // 取得したimageを表示
            self.thumbnailImage = resize(image:thumbnailimage, width: 32) // これは意味ない
            self.ciImage = CIImage(cgImage: capturedImage).resize(width: 32)
            // BLEsendPhotoの中で使う
            
            // imageをBLEで送る
            let filename = "thumbnail.jpg"
            BLEsendPhoto(filename: filename)

            
        }
        
    }
    
    // POSTtestをコピー
    // 実は uiImage は使っていない
    func BLEsendPhoto(filename: String) {
        print("BLEsendPhoto")
        
        // GPS情報(Exif情報)を残すため
        guard let imageData = CIContext().jpegRepresentation(
            of: ciImage!,
            colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [:]) else {
            print("imageData is nil")
            return
        }
        
        // jpegファイルのサイズを確認するためにローカルファイルに書き込む
        // ここは来ない？
        SaveImageFile(filename: "debug-video-thumbnail.jpg", imageData: imageData)

        
        BLEsendImage(filename: filename, imageData: imageData)
    }
    
    func BLEsendImage(filename: String, imageData: Data) {
        
        /*
        guard let imageData = CIContext().jpegRepresentation(
        of: ciImage!,
                colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                options: [:]) else {
                print("imageData is nil")
            return
        }
         */
        print("imageData.count=",imageData.count)
        
        // base64 encode する。
        let base64String = imageData.base64EncodedString(options: [])
        print(base64String.count)

        // ヘッダを追加する
        let writeString = String(format:"[base64,fname=%@]",filename)+base64String
        self.userMessage.addItem(userMessageText: writeString)

        // debugのために、ファイルに出力する
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = "base64output"
        var fileURL = documentsURL.appendingPathComponent(path)
        print(fileURL)

        do {
            // テキストの書き込みを実行
            try writeString.write(to:fileURL, atomically: true, encoding: .utf8)
            print("debug write 成功\nopen", path)

        } catch {
            //　テストの書き込みに失敗
            print("debug write 失敗:", error )
        }
        
        // デバッグ用にdecodeしてファイルに出力
        let decodebase64String = Data(base64Encoded: base64String)
        let decodepath = filename // JPEGになっている
        let decodefileURL = documentsURL.appendingPathComponent(decodepath)

        do {
            // テキストの書き込みを実行
            try decodebase64String?.write(to: decodefileURL)
            print("decode write 成功2\nopen", path)

        } catch {
            //　テストの書き込みに失敗
            print("decode write 失敗2:", error )
        }
        
    }

    
    // POSTMain
    func POSTMain(filename: String, uiImage: UIImage??){
        print("POSTMain")
        if self.uiImage != nil {
            print("photo")
            POSTtest(filename: filename, uiImage: self.uiImage)
        } else {
            print("movie")
            POSTtest2()
        }
        // print(self.fileIDlink) // ここではまだfileIDlinkは設定されていない
    }
    
    func MakeThumbnailFromVideo() -> UIImage {
        /// ①DocumentsフォルダURL取得
        guard let dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("フォルダURL取得エラー")
        }
        
        /// ②対象のファイルURL取得
        let fileURL = dirURL.appendingPathComponent("upload.mp4")
        print(fileURL)
        // https://qiita.com/1997/items/d0bcb3d9d5209bbe3db0
        // https://mixltd.jp/blog/ios_get_movie_thumbnail/
        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // サムネイル生成
//        let avAsset = AVAsset(url: url)
//        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
//        let duration = asset.duration
        //let duration = try? asset.load(.duration)
        let seconds = 0.0 // 5秒で指定
//        let time = CMTime(seconds: seconds, preferredTimescale: duration.timescale)
        let time = CMTime(seconds: seconds, preferredTimescale: 60)
        let capturedImage = try! generator.copyCGImage(at: time, actualTime: nil)
        let thumbnailimage = resize(image: UIImage(cgImage: capturedImage), width: 32)
        
        // videoからexifのあるjpegができるかの実験
        // ciimage経由を試す → 失敗
        //let ciImage = CIImage(cgImage: capturedImage)
        //MakeThumbnailFromCIImage(ciImage: ciImage)
        // MakeThumbnailFromCIImageの中で、debug-thumnail.jpg にセーブされる。
        
        // videoのGPS情報を得る
        // ReadFilesで確認したやり方をコピー
        
        let video = AVURLAsset(url: fileURL)
        let metadata = video.metadata
        var latitude:Double = 0.0
        var longitude:Double = 0.0
        var altitude:Double = 0.0
        for item in metadata {
            print(item)
            print(item.identifier)
            if item.identifier?.rawValue ?? "dummy" == "mdta/com.apple.quicktime.location.ISO6709" {
                print(item.value)
                let value = item.value as! String
                print(type(of: value))
                print(value)
                
                // 緯度、経度、高度に分ける
                let regex = /(?<latitude>[+-][\d\.]*)(?<longitude>[+-][\d\.]*)(?<altitude>[+-][\d\.]*)/
                let matches = value.firstMatch(of: regex)
                if matches != nil {
                    latitude = Double(matches!.latitude)!
                    longitude = Double(matches!.longitude)!
                    altitude = Double(matches!.altitude)!
                    print(matches!.0)
                    print(matches!.latitude)
                    print(matches!.longitude)
                }
                
                // メタデータを書く
                
                var properties:[String:Any] = ["":""]
                print(properties)
                var exif:[String: Any] = ["":""]
                properties["{Exif}"] = exif;
                let gpsData = NSMutableDictionary()

                let altitudeRef = Int(altitude < 0.0 ? 1 : 0)
                let latitudeRef = latitude<0 ? "S" : "N"
                let longitudeRef = longitude<0 ? "W" : "E"

                // GPS metadata
                gpsData[(kCGImagePropertyGPSLatitude as String)] = abs(latitude)
                gpsData[(kCGImagePropertyGPSLongitude as String)] = abs(longitude)
                gpsData[(kCGImagePropertyGPSLatitudeRef as String)] = latitudeRef
                gpsData[(kCGImagePropertyGPSLongitudeRef as String)] = longitudeRef
                gpsData[(kCGImagePropertyGPSAltitude as String)] = abs(altitude)
                gpsData[(kCGImagePropertyGPSAltitudeRef as String)] = altitudeRef
                gpsData[(kCGImagePropertyGPSVersion as String)] = "2.2.0.0"

                properties[ kCGImagePropertyGPSDictionary as String ] = gpsData
                
                
                // この時点では fileID が決まっていない
               let dummyfileURL = dirURL.appendingPathComponent("video-thumbnail.jpg")

               let thumbnailCGIImage = capturedImage.resize(width: 32)!
               
               // thumbnailimageを上で作ってある
               if let destination = CGImageDestinationCreateWithURL(dummyfileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                  // 先ほどのmetadaをCGImageに反映する
                  CGImageDestinationAddImage(destination, thumbnailCGIImage, properties as CFDictionary)
                  // 指定したURLに書き込み
                  CGImageDestinationFinalize(destination)

                   // 書いたデータを読む
                   do {
                       let jpegdata = try Data(contentsOf: dummyfileURL)
                       print(jpegdata.count)
                       self.thumbnailJpeg = jpegdata
                   } catch {
                       print("read jpeg error in MakeThumbnailFromCide")
                   }
                   
               }

            }
        }
        
        
        return thumbnailimage
        
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
            let username:String = user.myID
            //let username="usr00"
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
        /*
            httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
        */
            httpBody1 += "Content-Disposition: form-data; name=\"fileInfoU\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"UUID\":\"\(user.UUID)\","
            httpBody1 += "\"userID\":\"\(username)\"}\r\n"
        
        
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
        let url = URL(string: "http://"+wifi.edgeIP+":8010/registfileU")!
            print(url)
            //URLを生成
            var request = URLRequest(url: url)               //Requestを生成
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = httpBody
            request.timeoutInterval = 1.0 // for debug
        
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
                if let error = error {
                    print("request failure: \(error)")
                    let nsError = error as NSError
                    print(nsError)
                    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                        print("timeout in POSTtest2")
                        // TBDのfileIDを作成する
                        TBDfileID = user.UUID + "-edgeTBD-" + username + "-" + filename
                        dummyresult = "Timeout: use \(TBDfileID)"
                        fileIDlink = " [Link](\(TBDfileID))"
                        sendmsg = fileIDlink
//                        SaveToDoc(filename: TBDfileID, uiImage: uiImage!!)
                        RenameMovieFile(FromFilename: "upload.mp4", ToFilename: TBDfileID)
                        
                        wifi.fileuploadWithID(fname: TBDfileID)

                    }
                    
                    // thumbnailをBLEで送る
                    SendThumbnailBLE(filename: TBDfileID)
                    // 置き換え
                    /*
                    let reg = /^(?<fname>.*)\.[^\.]*$/
                    let match = TBDfileID.firstMatch(of: reg)
                    if let match = match {
                        let thumbnailfname = match.fname + "-thumb.jpg"
                        print(TBDfileID)
                        print(thumbnailfname)
                        let thumbnailJpeg = self.thumbnailImage?.jpegData(compressionQuality: 0.9) // 0.9が適当か不明
                        print(thumbnailJpeg?.count)
                        if let thumbnaiJpeg = thumbnailJpeg {
                            BLEsendImage(filename: String(thumbnailfname), imageData: thumbnailJpeg!)
                        } else {
                            print("thumbnailImage is nil error")
                        }
                    }
                    */

                    return
                }
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
                    
                    // thumbnailをBLEで送る
                    SendThumbnailBLE(filename: fname)
                    // 置き換え
                    /*
                    let reg = /^(?<fname>.*)\.[^\.]*$/
                    let match = fname.firstMatch(of: reg)
                    if let match = match {
                        let thumbnailfname = match.fname + "-thumb.jpg"
                        print(fname)
                        print(thumbnailfname)
                        let thumbnailJpeg = self.thumbnailImage?.jpegData(compressionQuality: 0.9) // 0.9が適当か不明
                        print(thumbnailJpeg?.count)
                        if let thumbnaiJpeg = thumbnailJpeg {
                            BLEsendImage(filename: String(thumbnailfname), imageData: thumbnailJpeg!)
                        } else {
                            print("thumbnailImage is nil error")
                        }
                    }
                     */

                } catch let error {
                    print("error in POSTtest2")
                    print(error)
                }
            }
            task.resume()
        }

    func SendThumbnailBLE(filename: String) {
        // thumbnailをBLEで送る
        let reg = /^(?<fname>.*)\.[^\.]*$/
        let match = filename.firstMatch(of: reg)
        if let match = match {
            let thumbnailfname = match.fname + "-thumb.jpg"
            print(filename)
            print(thumbnailfname)
            //            let thumbnailJpeg = self.thumbnailImage?.jpegData(compressionQuality: 0.9) // 0.9が適当か不明
            let thumbnailJpeg = self.thumbnailJpeg
            print(thumbnailJpeg?.count ?? "thumbnail count is unknown in SendThumbnailBLE")
            
            // jpegファイルのサイズを確認するためにローカルファイルに書き込む
            // videoのときだけか？
            SaveImageFile(filename: "debug-video-thumbnail.jpg", imageData: thumbnailJpeg!)

            
            if thumbnailJpeg != nil {
                BLEsendImage(filename: String(thumbnailfname), imageData: thumbnailJpeg!)
            } else {
                print("thumbnailImage is nil error in SendThumbnailBLE")
            }
        }

    }
                
    func MakeThumbnailFromCIImage(ciImage: CIImage) -> UIImage? {
        let smallciImage = ciImage.resize(width: 32.0)
        guard let imageData = CIContext().jpegRepresentation(
            of: smallciImage,
            colorSpace: smallciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [:]) else {
            print("imageData is nil(MakeThumbnail")
            return nil
            }
        // option で、
        // [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        // な感じで quality を指定できるはず
        
        // 実際にBLEで送るように jpeg を残しておく。
        self.thumbnailJpeg = imageData
        // jpegファイルのサイズを確認するためにローカルファイルに書き込む
        SaveImageFile(filename: "debug-thumnail.jpg", imageData: imageData)
        
        return UIImage(data: imageData)
        
    }
        func POSTtest(filename: String, uiImage: UIImage??) {
            print("POSTtest")
            
            // boundaryを作る
            let boundary = "----------" + UUID().uuidString
            print(boundary)
            // bocyを作る
            // for debug
            let username:String = user.myID
            //let username="usr0"
            print(username)
            // GPS情報(Exif情報)を残すために上を下に変更する
            guard let imageData = CIContext().jpegRepresentation(
                of: ciImage!,
                colorSpace: ciImage?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                options: [:]) else {
                print("imageData is nil")
                return
                }
            
            
            // jpegファイルのサイズを確認するためにローカルファイルに書き込む
            SaveImageFile(filename: "debug.jpg", imageData: imageData)
            
            var httpBody1 = "--\(boundary)\r\n"
            // registfileからregistfileUへの修正
            /*
            httpBody1 += "Content-Disposition: form-data; name=\"userInfo\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"userID\":\"\(username)\"}\r\n"
             */
            httpBody1 += "Content-Disposition: form-data; name=\"fileInfoU\"\r\n"
            httpBody1 += "\r\n"
            httpBody1 += "{\"UUID\":\"\(user.UUID)\","
            httpBody1 += "\"userID\":\"\(username)\"}\r\n"

            
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
            
            // registfileからregistfileUへの修正
            let url = URL(string: "http://"+wifi.edgeIP+":8010/registfileU")!
            print(url)
            //URLを生成
            var request = URLRequest(url: url)               //Requestを生成
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(httpBody.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = httpBody
            request.timeoutInterval = 1.0 // for debug

            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in  //非同期で通信を行う
                if let error = error {
                    print("request failure: \(error)")
                    let nsError = error as NSError
                    print(nsError)
                    // 接続先がいて、fastAPIが動いていないと Timeout にならないので、修正する
                    //                    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                    if nsError.domain == NSURLErrorDomain {
                        print("timeout in POSTtest")
                        // TBDのfileIDを作成する
                        TBDfileID = user.UUID + "-edgeTBD-" + username + "-" + filename
                        dummyresult = "Error: use \(TBDfileID)"
                        fileIDlink = " [Link](\(TBDfileID))"
                        sendmsg = fileIDlink
                        SaveToDoc(filename: TBDfileID, uiImage: uiImage!!)
                        
                        wifi.fileuploadWithID(fname: TBDfileID)

                    }
                    
                    // thumbnailをBLEで送る
                    SendThumbnailBLE(filename: TBDfileID)
                    // 置き換え
                    /*
                    let reg = /^(?<fname>.*)\.[^\.]*$/
                    let match = TBDfileID.firstMatch(of: reg)
                    if let match = match {
                        let thumbnailfname = match.fname + "-thumb.jpg"
                        print(TBDfileID)
                        print(thumbnailfname)
                        let thumbnailJpeg = self.thumbnailImage?.jpegData(compressionQuality: 0.9) // 0.9が適当か不明
                        print(thumbnailJpeg?.count)
                        if let thumbnaiJpeg = thumbnailJpeg {
                            BLEsendImage(filename: String(thumbnailfname), imageData: thumbnailJpeg!)
                        } else {
                            print("thumbnailImage is nil error")
                        }
                    }
                     */
                    return
                }
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
                    
                    // thumbnailをBLEで送る
                    SendThumbnailBLE(filename: fname)

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
    
    func SaveImageFile(filename: String, imageData: Data) {
        print("SaveImageFile called")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)
        print(fileURL)
        do {
            try imageData.write(to: fileURL)
            print("SaveImageFile Done")
        } catch {
            print("SaveImageFile error")
        }
    }
    
    
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
    
    func RenameMovieFile(FromFilename: String, ToFilename: String) {
        print("RenameMovieFile")
        print("SaveToDoc called")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let FromfileURL = documentsURL.appendingPathComponent(FromFilename)
        let TofileURL = documentsURL.appendingPathComponent(ToFilename)

        do{
            try FileManager.default.moveItem(at: FromfileURL, to: TofileURL)
        }catch{
            print("RenameMovieFile error \(error)")
        }
    }

    
}


#Preview {
    PhotoView()
}

