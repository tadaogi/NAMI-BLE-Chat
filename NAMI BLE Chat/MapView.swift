//
//  MapView.swift
//  NAMI BLE Chat
//
//  Created by Tadashi Ogino on 2024/07/23.
//
//
//  MapView.swift
//  NAMIMessageTest
//
//  Created by Tadashi Ogino on 2024/07/18.
//

// https://qiita.com/takatein/items/df07b81b4c0545accc43

import SwiftUI
import MapKit

class Params: ObservableObject {
    @Published var showmap = false
    @Published var msgDataList : [MsgData] = []
}

struct MsgData : Identifiable {
    var id = UUID()
    var pos : CLLocationCoordinate2D
    var userMessageText : String
    var userName : String
    var dateTime : String
    
    init() {
        pos = CLLocationCoordinate2D(latitude:0, longitude:0)
        userMessageText = "initial for debug"
        userName = "dummyName for debug"
        dateTime = "2024-01-01 00:00:00"
    }
    
    init(pos:CLLocationCoordinate2D, userMessageText:String, userName:String, dateTime:String) {
        self.pos = pos
        self.userMessageText = userMessageText
        self.userName = userName
        self.dateTime = dateTime

    }
}

struct MapView: View {
    @EnvironmentObject var params: Params
    @EnvironmentObject var userMessage : UserMessage

/*
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
 */
    // 明星大学
    @State private var cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.64488, longitude: 139.40846),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    @State private var markerPos = CLLocationCoordinate2D(latitude: 35.64488, longitude: 139.40846)
    @State private var markerPos2 = CLLocationCoordinate2D(latitude: 35.64488, longitude: 139.40846)
    @State private var items = [1,2]

    //@State var msgDataList : [MsgData] = []:
    
    @State var showMsgDialog = false
    @State var dialogMessage = "initial value"
    @State var userMessageText = "debug message"
    @State var tapMsgData = MsgData()
    
  
    var body: some View {
        /*
        Button("test") {
            var newMsgData = MsgData(pos: CLLocationCoordinate2D(latitude: 35.6885, longitude: 139.6917))
            params.msgDataList.append(newMsgData)
            print(params.msgDataList)
        }
        .frame(height: 20)
        */
        ZStack {
            Map (position: $cameraPosition) {
                //            Marker("marker", systemImage: "text.bubble", coordinate: markerPos)
                // systemImageは、SF Symbols をインストールしてから使う
                
                /*
                 Annotation("Annotation",
                 coordinate: markerPos2, anchor: .bottom) {
                 VStack {
                 Image(systemName: "flag.2.crossed")
                 .onTapGesture {
                 print("image")
                 }
                 }
                 .foregroundColor(.blue)
                 .padding()
                 .background(in: .capsule)
                 .onTapGesture {
                 print("onTap")
                 
                 }
                 }
                 */
                
                ForEach(params.msgDataList) { msgData in
                    //Marker("marker", systemImage: "text.bubble", coordinate: msgData.pos)
                    Annotation("",
                               coordinate: msgData.pos, anchor: .bottom) {
                        VStack {
                            ZStack {
                                let filename = getFilename(message: msgData.userMessageText)
                                if filename != "" {
                                    // 角が円の四角形
                                    
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white)
                                        .frame(width:70, height: 70)
                                    
                                    Thumbnail(filename: getFilename(message: msgData.userMessageText), width: 64)
                                    //.resizable() // Thumbnailに width を渡すようにした
                                    //.scaledToFit()
                                    //.frame(width: 40)
                                        .onTapGesture {
                                            tap(msgData: msgData)
                                        }

                                } else {
                                    // messageに画像がない場合の表示
                                    /*
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white)
                                        .frame(width:36, height: 36)
                                    */
                                    Image(systemName: "text.bubble.fill")
                                        .resizable()
                                        
                                        .frame(width: 32, height: 32)
                                        .foregroundColor(.blue)
                                        
                                        .onTapGesture {
                                            tap(msgData: msgData)
                                        }

                                }
                                
                                /*
                                Image("enoshimaStation")
                                //Image(systemName: "text.bubble.fill")
                                //.foregroundColor(.white)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40)
                                    .foregroundColor(.red)
                                 */
                                 /*
                                    .onTapGesture {
                                        setDialogMessage(msg: msgData.userMessageText)
                                        print(msgData.userMessageText)
                                        showMsgDialog = true
                                        params.showmap = true
                                        userMessageText = msgData.userMessageText

                                    }
                                */
                            }
                        }
                        .foregroundColor(.blue)
                        .padding()
                        //.background(in: .capsule)
                        // ここは動かない
                        .onTapGesture {
                            print("onTap")
                            showMsgDialog = true
                        }
                    }
                    
                }
                
            }
            
            //.mapControlVisibility(.hidden)
            .mapControlVisibility(.visible)

            //Image("samplemaxlen")
            /*
            Image("enoshimaStation")
                .resizable()
                .scaleToFit() // 縦横比を保存
                .frame(width:32, height:32)
            */
            if params.showmap {
                /*
                HStack(alignment: .center) {
                    VStack(alignment: .center) {
                        Text("XXXXXXXXXXX")
                    }
                }
                */
                 
                GeometryReader { proxy in
                    let dialogWidth = proxy.size.width * 0.9
                    let dialogHeight = proxy.size.height * 0.9

                    // ここにダラダラ書くより、DummyView()にいれるほうが良い
                    //VStack(alignment: .center) {
                        
                        //Spacer()
                        //HStack(alignment: .center) {
                            //Text("0000")
                            //Spacer()
                            //ZStack {
                            //    Rectangle()
                            //        .fill(Color.red)
                            //        .frame(width: dialogWidth,
                            //               height: dialogHeight)

                                // これだけでOK
                    SingleMessageView(userMessageData: tapMsgData)
                            //}
                            //Spacer()
                        //}
                        //Spacer()
                    //}
                    /*
                    VStack {
                        Spacer()
                        HStack(alignment: .center) {
                            //Text("0000")
                            Spacer()
                            ZStack() {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: dialogWidth,
                                           height: dialogHeight)
                                VStack {
                                    Text(dialogMessage)
                                    
                                    Button("close") {
                                        showMsgDialog = false
                                    }
                                }
                            }
                            //VStack(alignment: .center) {
                            //    Text("abcdefg")
                            //}
                            Spacer()
                            //Text("9999")
                        }
                        Spacer()
                    }
                    */
                    /*
                    ZStack() {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: dialogWidth, height: 20)
                            VStack {
                                Text(dialogMessage)
                                //DummyView()
                                Button("close") {
                                    showMsgDialog = false
                                }
                            }
                        }
                     */

                    
                }

            }
        } // ZStack
        .onAppear{
            makeMsgDataList()
        }
         
    }
    
    func tap(msgData: MsgData) {
        // いらないと思うのでコメントアウトする
        // setDialogMessage(msg: msgData.userMessageText)
        print(msgData.userMessageText)
        showMsgDialog = true
        params.showmap = true
        userMessageText = msgData.userMessageText
        tapMsgData = msgData

    }
    // debug用
    func getPos(filename: String)-> CLLocationCoordinate2D? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        var message = "no GPS data"
        
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            if let dict = imageProperties as? [String: Any] {
                print(Array(dict.keys))
                print(dict)
                if dict.keys.contains("{GPS}") {
                    print(dict["{GPS}"]!)
                    print(type(of: dict["{GPS}"]))
                    let data = dict["{GPS}"] as? NSMutableDictionary
                    print(data as Any)
                    print(data!["Latitude"])
                    var dlat:Double = data!["Latitude"] as! Double
                    print(dlat)
                    if data!["LatitudeRef"] as! String == "S" {
                        dlat = -dlat
                        print(dlat)
                    }
                    let slatitude = String(format: "%f", dlat)
                    print(slatitude)
                    print(data!["Longitude"])
                    var dlon:Double = data!["Longitude"] as! Double
                    print(dlon)
                    if data!["LongitudeRef"] as! String == "W" {
                        dlon = -dlon
                        print(dlon)
                    }

                    let slongitude = String(format: "%f", dlon)
                    print(slongitude)
                    print(slatitude+","+slongitude)
                    message = slatitude+","+slongitude
                    let pos = CLLocationCoordinate2D(latitude: dlat, longitude: dlon)
                    return pos
                }
            }
        }
        
        return nil
    }

    func getPosFromMessage(userMessageText: String)-> CLLocationCoordinate2D? {
        // for debug
        // 明星大学 35.64488, 139.40846
        var dlat = 35.64488
        var dlon = 139.40846
        let reg = /\[GPS,(?<latitude>[0-9.\-]*),(?<longitude>[0-9.\-]*)\]/
        if let match=userMessageText.firstMatch(of: reg) {
            print(match.0)
            print(match.latitude)
            print(match.longitude)
            dlat = Double(match.latitude) ?? dlat
            dlon = Double(match.longitude) ?? dlon
            
            let pos = CLLocationCoordinate2D(latitude: dlat, longitude: dlon)
            return pos
        }
        return nil
    }

    func getUserFromMessageID(userMessageID: String) -> String {
        // "20210101235900000-0001-tadashi" // 合っているのかな？違ったら直す
        // "20240723100346.220-dc2a-tadashi-0L(0)"
        var username = "unknown"
//        let reg = /[0-9]*-[0-9]*-(?<username>[a-zA-Z]*)/
        let reg = /[^-]*-[^-]*-(?<username>[a-zA-Z0-9]*)/
        if let match=userMessageID.firstMatch(of: reg) {
            print(match.0)
            print(match.username)
            username = String(match.username)
        }

        return username
    }

    func getDateTimeFromMessageID(userMessageID: String) -> String {
        var Y = "2024", M = "01", D = "01", H = "00", m = "00", S = "00"
        let reg = /^(?<Y>[0-9]{4})(?<M>[0-9]{2})(?<D>[0-9]{2})(?<H>[0-9]{2})(?<m>[0-9]{2})(?<S>[0-9]{2})/
        if let match=userMessageID.firstMatch(of: reg) {
            print(match.0)
            print(match.Y)
            print(match.M)
            print(match.D)
            print(match.H)
            print(match.m)
            print(match.S)
            Y = String(match.Y)
            M = String(match.M)
            D = String(match.D)
            H = String(match.H)
            m = String(match.m)
            S = String(match.S)
        }
        
        return "\(Y)-\(M)-\(D) \(H):\(m):\(S)"

    }
    
    func getDateTimeFromExif(filename: String)-> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        var message = "no Exif DateTime"
        
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            if let dict = imageProperties as? [String: Any] {
                print(Array(dict.keys))
                print(dict)
                if dict.keys.contains("{Exif}") {
                    print(dict["{Exif}"]!)
                    print(type(of: dict["{Exif}"]))
                    let data = dict["{Exif}"] as? NSMutableDictionary
                    print(data as Any)
                    print(data!["DateTimeOriginal"])
                    let exifDateTime:String = data!["DateTimeOriginal"] as! String
                    print(exifDateTime)
                    var Y = "2024", M = "01", D = "01", H = "00", m = "00", S = "00"
                    let reg = /^(?<Y>[0-9]{4}):(?<M>[0-9]{2}):(?<D>[0-9]{2}) (?<H>[0-9]{2}):(?<m>[0-9]{2}):(?<S>[0-9]{2})/
                    if let match=exifDateTime.firstMatch(of: reg) {
                        print(match.0)
                        print(match.Y)
                        print(match.M)
                        print(match.D)
                        print(match.H)
                        print(match.m)
                        print(match.S)
                        Y = String(match.Y)
                        M = String(match.M)
                        D = String(match.D)
                        H = String(match.H)
                        m = String(match.m)
                        S = String(match.S)
                        message = "\(Y)-\(M)-\(D) \(H):\(m):\(S)"

                        return message

                    }
                }
            }
        }

        return "" // ""なら見つからなかった
    }
    
    func makeMsgDataList() {
        
        params.msgDataList = []
        // 写真が１枚もないとこの場所がセンターになる。明星大学 35.64488, 139.40846
        var initialpos:CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.64488, longitude: 139.40846)
        
        for userMessageItem in self.userMessage.userMessageList {
            print(userMessageItem.userMessageID)
            let userMessageID = userMessageItem.userMessageID
            
            print(userMessageItem.userMessageText)
            let username = getUserFromMessageID(userMessageID: userMessageID)
            var dateTime = getDateTimeFromMessageID(userMessageID: userMessageItem.userMessageID)
            let filename = getFilename(message: userMessageItem.userMessageText)
            if filename != "" {
                print(filename)
                let pos = getPos(filename: filename)
                let dateTimeFromExif = getDateTimeFromExif(filename: filename)
                if dateTimeFromExif != "" {
                    dateTime = dateTimeFromExif
                }
                print(pos)
                if let thispos = pos {
                    var newMsgData = MsgData(pos: thispos, userMessageText: userMessageItem.userMessageText, userName: username, dateTime: dateTime)
                    params.msgDataList.append(newMsgData)
                    initialpos = thispos
                }
            
            } else {
                print("No Link")
                let pos = getPosFromMessage(userMessageText: userMessageItem.userMessageText)
                print(pos)
                if let thispos = pos {
                    var newMsgData = MsgData(pos: thispos, userMessageText: userMessageItem.userMessageText, userName: username, dateTime: dateTime)
                    params.msgDataList.append(newMsgData)
                    initialpos = thispos
                }

            }
        }
        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
            center: initialpos,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))

    }
    
    // MyView からコピペ。本当は共通のライブラリにする必要がある
    
    func getFilename(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.2)
        } else {
            return ""
        }
    }
    
    func setDialogMessage(msg: String) {
        dialogMessage = msg
        savedata() // debug
    }
    
    func savedata() {
        let DocumentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        print("savedata")
        print(DocumentPath)
        
        let image = UIImage(named: "enoshimaStation")
        let orgsize = image?.size
        let maxlen = max(orgsize!.height, orgsize!.width)
        print("width:", 10*orgsize!.width/maxlen, "height:", 10*orgsize!.height/maxlen)
        let scaledImageSize = CGSize(width: 10*orgsize!.width/maxlen, height: 10*orgsize!.height/maxlen)
        let renderer = UIGraphicsImageRenderer(size: scaledImageSize)
        let scaleImage = renderer.image { _ in
            image?.draw(in: CGRect(origin: .zero, size: scaledImageSize))
        }
        
        //let imageView = UIImageView()
        //imageView.image = scaleImage
        
        let jpeg = scaleImage.jpegData(compressionQuality: 1.0)
        do{
          //compressionQualityでクオリティの設定 1?~100
            try jpeg?.write(to:URL(fileURLWithPath: DocumentPath + "/sample.jpg" ) )
        }catch{
            print("error")
          //error
        }
    }
}

#Preview {
    MapView()
}
