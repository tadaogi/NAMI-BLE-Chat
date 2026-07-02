//
//  Crypt.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2026/07/02.
//
// 暗号化、復号化
// CryptTest3をベースにする。

import SwiftUI
import CryptoKit
import Security

struct Payload: Codable {
    let nonce: String
    let ciphertext: String
}

struct CryptView: View {
    @StateObject private var crypt = NAMICrypt()
    
    @State private var inputText: String = "送るメッセージ"
    @State private var encryptedData: Data?
    @State private var decryptedText: String = ""
    @State private var serverPublicKey: String = "QQ8kDNYV2KFyj9Tm0dxaaXIvUNEXBp+GVCyveOd+/gc="
    @State private var encryptedText: String = ""
//    @State private var screenMessage: String = ""
    
    @State private var inputJSON: String = ""
    @State private var decrypted_message: String = ""
    
    var payload: [String: String] =
    ["nonce":"",
     "ciphertext":"",
    ]
    //var serverPublicKeyBase64 = "RXG6n6rPlY+RwCRZvoKCpkZtqQxNx5bc6xQju5OYCmw="
    
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("暗号化、復号化のデバッグ用")
                HStack() {
                    Text("鍵の初期化結果:")
                    Text(crypt.screenMessage)
                }

                
                
                
                TextField("入力テキスト", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                /*
                 Button("鍵生成") {
                 generateKey()
                 }
                 
                 Button("AES-GCMで暗号化") {
                 encrypt()
                 }
                 
                 Button("復号") {
                 decrypt()
                 }
                 
                 Text("暗号データ(Base64)")
                 Text(encryptedData?.base64EncodedString() ?? "")
                 .font(.footnote)
                 
                 Text("復号結果")
                 Text(decryptedText)
                 */
                /*
                 Text("公開鍵と共通鍵を使った例")
                 Text(screenMessage)
                 */
                 Text("サーバの公開鍵")
                TextField("サーバの公開鍵（base64)", text: $crypt.serverPublicKeyBase64, axis: .vertical)
                
                
                 Button("暗号化実行") {
                     encryptedText = crypt.encrypt(inputText: inputText)
                 }
                 Text("暗号化後")
                 Text(encryptedText)
                 .textSelection(.enabled) // コピー可能にする
                 Button("コピー") {
                 UIPasteboard.general.string = encryptedText
                 }
                /*
                 Button("暗号の共有") {
                 share(encryptedText)
                 }
                 
                 Button("Delete Key") {
                 deleteClientPrivateKey()
                 }
                 
                 TextEditor(text: $inputJSON)
                 .frame(height: 160)
                 .border(.gray)
                 .padding()
                 Button("復号") {
                 decrypted_message = ""
                 run2()
                 }
                 Text(decrypted_message)
                 */
                
            }
            .padding()
        }
    }
}

class NAMICrypt: ObservableObject {

    private var clientPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    
    @Published var serverPublicKeyBase64: String = "QQ8kDNYV2KFyj9Tm0dxaaXIvUNEXBp+GVCyveOd+/gc="

//    private var serverPublicKey: Curve25519.KeyAgreement.PublicKey?
    
    @Published var screenMessage: String = ""
    @Published var inputText: String = ""

    // 鍵の初期化を呼ぶ
    init() {
        print("NAMICrypt.init() is called")
        try? setupIfNeeded()
    }

    func setupIfNeeded() throws {
        guard clientPrivateKey == nil else { return }
        clientPrivateKey = getPrivateKey()
    }
    
    func getPrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        let clientPrivateKey: Curve25519.KeyAgreement.PrivateKey

        do {
            if let key = try loadPrivateKey() {
                
                print("既存鍵を使用")
                screenMessage = "use saved key"
                clientPrivateKey = key
                
            } else {
                
                print("新しい鍵を生成")
                screenMessage = "make new key"
                let key = Curve25519.KeyAgreement.PrivateKey()
                
                try savePrivateKey(key)
                
                clientPrivateKey = key
            }
        } catch {
            print("getPrivateKey error \(error)")
            return Curve25519.KeyAgreement.PrivateKey()
        }
        return clientPrivateKey
    }
    
    func savePrivateKey(_ key: Curve25519.KeyAgreement.PrivateKey) throws {

        let keyData = key.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "NAMI",
            kSecAttrAccount as String: "ClientPrivateKey",
            kSecValueData as String: keyData
        ]

        // すでに存在する場合は削除
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain",
                          code: Int(status),
                          userInfo: nil)
        }
    }
    
    func loadPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey? {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "NAMI",
            kSecAttrAccount as String: "ClientPrivateKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?

        let status = SecItemCopyMatching(query as CFDictionary,
                                         &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain",
                          code: Int(status),
                          userInfo: nil)
        }

        guard let data = result as? Data else {
            return nil
        }

        return try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: data
        )
    }
        
    func  encrypt(inputText: String) -> String {
        //let serverPublicKeyBase64 = serverPublicKey
        // "F+5ku7+wV+o2EGwr+n4GiG1m/9QhvjUGQ+S2S/dpfWU=" // 家のMacで作ったキー

        do {
            let payload = try encryptToServer(
                message: inputText,
                serverPublicKeyBase64: serverPublicKeyBase64
            )

            print(payload)
            
            
                let data = try JSONSerialization.data(withJSONObject: payload)
                let jsonString = String(data: data, encoding: .utf8)!

                print(jsonString)
                
            return jsonString
        } catch {
            print("encrypt error:", error)
            return "encrypt error: \(error)"
        }
    }
    
    func deriveAESKey(sharedSecret: SharedSecret) -> SymmetricKey {
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("NAMI-BLE-CHAT-v1".utf8),
            outputByteCount: 32
        )
    }

    func encryptToServer(message: String, serverPublicKeyBase64: String) throws -> [String: String] {
        // Macサーバーの公開鍵をBase64から復元
        guard let serverPublicKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
            throw NSError(domain: "Crypto", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid server public key base64"
            ])
        }

        let serverPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: serverPublicKeyData
        )

        // 動作確認用のクライアント鍵
        let clientPrivateKey: Curve25519.KeyAgreement.PrivateKey = getPrivateKey()
        print("PrivateKey \(clientPrivateKey.rawRepresentation.base64EncodedString())")

//        let clientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientPublicKey = clientPrivateKey.publicKey
        
        // X25519で共有秘密を作る
        let sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(
            with: serverPublicKey
        )

        // Python側と同じHKDF
        let aesKey = deriveAESKey(sharedSecret: sharedSecret)

        // AES-GCMで暗号化
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(
            Data(message.utf8),
            using: aesKey,
            nonce: nonce
        )

        print(sealedBox)
        // Python cryptography の AESGCM.encrypt は ciphertext + tag を返す
        // Swift CryptoKit では ciphertext と tag が分かれているので連結する
        let ciphertextAndTag = sealedBox.ciphertext + sealedBox.tag

        return [
            "clientPublicKey": clientPublicKey.rawRepresentation.base64EncodedString(),
            "nonce": Data(nonce).base64EncodedString(),
            "ciphertext": ciphertextAndTag.base64EncodedString()
        ]
    }


    
    func decrypt() {
        print("NAMICrypto.decrypt not implemented")
    }
}
