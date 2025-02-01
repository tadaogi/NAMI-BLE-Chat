//
//  MyView.swift
//  NAMIMessageTest
//
//  Created by Tadashi Ogino on 2024/07/15.
//

import SwiftUI
import UniformTypeIdentifiers

// 表示の時に、アスペクト比を保存する方法
// PhotoShow にあるので、コメントアウト
/*
extension View {
    public func framedAspectRatio(_ aspect: CGFloat? = nil, contentMode: ContentMode) -> some View where Self == Image {
        self.resizable()
            .fixedAspectRatio(contentMode: contentMode)
            .allowsHitTesting(false)
    }

    public func fixedAspectRatio(_ aspect: CGFloat? = nil, contentMode: ContentMode) -> some View {
//        self.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            self.frame(minWidth: 0, maxWidth: 300, minHeight: 0, maxHeight: 300)
            .aspectRatio(aspect, contentMode: contentMode)
            .clipped()
    }
}
*/

struct MyMessage: View {
    var message: String
    
//    @State var filename = "test.jpg"
//    @EnvironmentObject var user : User
    @EnvironmentObject var fileID: FileID
    @Binding var active : Bool
    
    var body: some View {
        let premessage = "premessage"
        let postmessage = message
        HStack {
            if message != "" {
                Text(getPremessage(message: message))
                let filename = getFilename(message: message)
                if filename != "" {
                    Button {
                        print("button " + filename + String(active))
                        print("FileID clicked \(filename)")
                        fileID.name = filename
                        active.toggle()
                    } label: {
                        Thumbnail(filename: filename, width: 64)
                    }
                }
                Text(getPostmessage(message: message))
            } else {
                // 何も表示しない。高さも０
            }
        }
        // for debug
        /*
        HStack {
            
            let img = Image("debugW64-1.0")
            
            let str = "abc" + "\(img)" + "def"
            Text("abd \(img) def")
        }
        */
    }
    
    func getPremessage(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.1)
        } else {
            return message
        }
    }
    func getFilename(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.2)
        } else {
            return ""
        }
    }
    func getPostmessage(message: String) -> String {
        let reg = /(.*)\[Link\]\((.*)\)(.*)/
        if let match=message.firstMatch(of: reg) {
            return String(match.3)
        } else {
            return ""
        }
    }

}

struct Thumbnail: View {
    // 渡される引数の定義
    var filename: String
    var width: Double
    
    @State var fileexist = false

    var body: some View {
        //Text("This is custom View")
        //Text(filename)
        let thumbnailfilename = MakeThumbnailFilename(filename: filename)
        //Text(thumbnailfilename)
        
        if thumbnailfilename != "" {
            
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let thumbnailURL = documentsURL.appendingPathComponent(thumbnailfilename)
            /*
             let thumbnailfile = fileURL.deletingPathExtension().absoluteString + "-thumbnail.jpg"
             let thumbnailURL = URL(string: thumbnailfile)!
             let path = fileURL.path
             */
            if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                
                if thumbnailURL.pathExtension != "" {
                    if UTType(filenameExtension: thumbnailURL.pathExtension)!.conforms(to: .image) {
                        AsyncImage(url: thumbnailURL) { image  in
                            
                            //                        image.framedAspectRatio(contentMode: .fit)
                            let w = calcwidth(urlfile: thumbnailURL)
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: w)
                            
                        } placeholder: {
                            ProgressView()
                        }
                        //Text(filename)
                        
                    } else if UTType(filenameExtension: thumbnailURL.pathExtension)!.conforms(to: .movie) {
                        Text("movie")
                        
                    } else {
                        Image("UnKnown256")
                            .resizable()
                            .frame(width:64, height:64)
                    }
                } else {
                    Image("NoImage256")
                        .resizable()
                        .frame(width:64, height:64)
                }
            } else {
                //            Image(systemName: "text.bubble")
                Image("NoImage256")
                    .resizable()
                    .frame(width:64, height:64)
                
                //Text("not exist")
            }
        } else {
            Image(systemName: "text.bubble")
                .resizable()
                .frame(width:64, height:64)

        }

    }
    func calcwidth(urlfile: URL) -> Double {
        let att = try! FileManager.default.attributesOfItem(atPath: urlfile.path)
        let uiimage = UIImage(named: urlfile.path)
        let width = uiimage?.size.width
        let height = uiimage?.size.height

        print(height)
        print(width)
        
        return width!
        /*
        if (height!/width! < 1.0) {
            return height!
        } else {
            return width!
        }
        */
    }
    func MakeThumbnailFilename(filename: String) -> String {
        let reg = /^(?<fname>.*)\.[^\.]*$/
        let match = filename.firstMatch(of: reg)
        if let match = match {
            let thumbnailfname = match.fname + "-thumbnail.jpg"
            return String(thumbnailfname)
        } else {
            return ""
//            return filename + "-thumbnail.jpg"
        }
    }
}

/*
struct DebugContentView: View {
    @Binding var active : Bool

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Image("NoImage256")
                .resizable()
                .frame(width:64, height:64)
            MyMessage(message: "[tadashi] [Link](test.jpg) this is test message", active: $active)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading], 5)

            MyMessage(message: "Test1.jpg", active: $active)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading], 5)
            MyMessage(message: "", active: $active)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading], 5)

        }
        .padding()
    }
}

#Preview {
    @State var active = false
    DebugContentView(active: $active)
}
 */
