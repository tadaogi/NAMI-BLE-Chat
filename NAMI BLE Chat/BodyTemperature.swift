//
//  BodyTemperature.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2026/02/06.
//

//
//  BLETemperatureApp.swift
//  BLETemperature
//
//  Created by 荻野正 on 2026/02/04.
//

import SwiftUI
import SwiftUI
import CoreBluetooth
import Combine   // ← これが重要

/*
@main
struct BLETemperatureApp: App {
    var body: some Scene {
        WindowGroup {
            BodyTemperatureView()
        }
    }
}
*/

// 以下はエラーになるけど、使っていないのでコメントアウトする
/*
struct BodyTemperatureView: View {
    @EnvironmentObject var userMessage: UserMessage
    @StateObject private var vm = BodyTemperatureViewModel(userMessage: userMessage)

    var body: some View {
        VStack(spacing: 16) {
            Text("BLE BodyTemperature")
                .font(.title2)

            Text(vm.status)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Temp: \(vm.tempText)")
            }
            .font(.title3)

            HStack(spacing: 12) {
                Button("Start Scan") { vm.start() }
                Button("Stop") { vm.stop() }
            }
        }
        .padding()
    }
}
*/

struct TempJsonRecord: Codable {
    let temp: Double
    let datetime: String

    enum CodingKeys: String, CodingKey {
        case temp = "TEMP"
        case datetime = "DATETIME"
    }
}

final class BodyTemperatureViewModel: NSObject, ObservableObject {
    // MARK: - Published UI
    @Published var status: String = "Idle"
    @Published var tempText: String = "-"

    // MARK: - CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    // GATT UUIDs (16-bit)
    // 標準 Health Thermometer の UUID
    let healthThermometerServiceCBUUID = CBUUID(string: "1809")
    let temperatureMeasurementCBUUID = CBUUID(string: "2A1C")
    
    @Published var historyRefreshToken = UUID() // ← 追加

    private let tempDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy/M/d HH:mm:ss"
        return f
    }()

    let userMessage: UserMessage
    init(userMessage: UserMessage) {
        self.userMessage = userMessage
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func start() {
        guard central.state == .poweredOn else {
            status = "Bluetooth not ready: \(central.state.rawValue)"
            return
        }
        status = "Scanning..."
        // 1809 を広告していない機器もあるので、本番では nil scan + 後段フィルタも検討
        central.scanForPeripherals(withServices: [healthThermometerServiceCBUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stop() {
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        central.stopScan()
        status = "Stopped"
    }

    private func resetValues() {
        tempText = "-"
    }
}

// MARK: - CBCentralManagerDelegate
extension BodyTemperatureViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Bluetooth powered on"
        case .poweredOff:
            status = "Bluetooth powered off"
        case .unauthorized:
            status = "Bluetooth unauthorized (check Settings)"
        case .unsupported:
            status = "Bluetooth unsupported"
        case .resetting:
            status = "Bluetooth resetting"
        case .unknown:
            status = "Bluetooth unknown"
        @unknown default:
            status = "Bluetooth state unknown"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        // ここで名前フィルタしたい場合は peripheral.name / adv dataを見る
        status = "Found: \(peripheral.name ?? "(no name)") RSSI \(RSSI)"

        self.peripheral = peripheral
        self.peripheral?.delegate = self

        central.stopScan()
        status = "Connecting..."
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected. Discovering services..."
        resetValues()
        peripheral.discoverServices([healthThermometerServiceCBUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        status = "Connect failed: \(error?.localizedDescription ?? "unknown")"
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        status = "Disconnected: \(error?.localizedDescription ?? "no error")"
    }
}

// MARK: - CBPeripheralDelegate
extension BodyTemperatureViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            status = "Service discovery error: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services else { return }

        for s in services where s.uuid == healthThermometerServiceCBUUID {
            status = "Health Thermometer Service found. Discovering characteristics..."
            peripheral.discoverCharacteristics([temperatureMeasurementCBUUID], for: s)
            return
        }
        status = "Body Temperature Service not found"
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            status = "Characteristic discovery error: \(error.localizedDescription)"
            return
        }
        guard let chars = service.characteristics else { return }

        for c in chars {
            if c.uuid == temperatureMeasurementCBUUID {
                status = "Subscribing BT Measurement (Notify)..."
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            status = "Notify state error: \(error.localizedDescription)"
            return
        }
        status = "Notify enabled for \(characteristic.uuid)"
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        
        if let error = error {
            status = "Update value error: \(error.localizedDescription)"
            return
        }
        guard let data = characteristic.value else { return }
        // hexダンプ
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")

        print("received data=\(hex)")
        if characteristic.uuid == temperatureMeasurementCBUUID,
           let value = characteristic.value {
            // バイト列を温度値に変換
            let temp = parseTemperature2A1C(value)!
            print("体温: \(temp)")
            tempText = String(temp)
            print("体温: \(tempText)")
            
            
            // この時点でデータが揃っている
            // とりあえずそのまま書く

            //self.userMessage.addItemWithGPS(userMessageText: "[TEMPDATA]"+tempText)
            
            // 3) BLE受信（2A1C）した瞬間に保存する
            let rec = TempRecord(
                id: UUID().uuidString,
                measuredAt: Date(),   // 端末時刻
                temperature: temp
            )

            do {
                try TempStore.shared.append(rec)
                print("Temp saved: \(rec)")
                DispatchQueue.main.async {
                    print("token update on main? \(Thread.isMainThread)")
                    self.historyRefreshToken = UUID()
                }
                historyRefreshToken = UUID() // ← 保存後に更新
                // この時点で最近のデータを読む
                let jsonstring = try makeTempJsonLast7Days()
                print("last 7 days: \n\(jsonstring)")
                self.userMessage.addItemWithGPS(userMessageText: "[TEMPDATA]"+jsonstring)

            } catch {
                print("Temp save failed: \(error)")
            }

        }
    }
    
    func makeTempJsonLast7Days() throws -> String {
        // ① repositoryから全件または必要分を取得（例）
        // ここはあなたの実装に合わせてください
        let all: [TempRecord] = try TempStore.shared.loadAll()

        // ② 7日前の境界
        let from = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        // ③ 7日以内だけに絞る（日時が新しい順に並べたい場合）
        let recent = all
            .filter { $0.measuredAt >= from }
            .sorted { $0.measuredAt > $1.measuredAt }

        // ④ JSON用DTOに変換
        let dto: [TempJsonRecord] = recent.map {
            TempJsonRecord(
                temp: $0.temperature,
                datetime: tempDateFormatter.string(from: $0.measuredAt)
            )
        }

        // ⑤ JSONエンコード
        let encoder = JSONEncoder()
        //encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] // 好みで
        encoder.outputFormatting = [.withoutEscapingSlashes] // 好みで
        let data = try encoder.encode(dto)
        return String(decoding: data, as: UTF8.self)
    }

 
    func parseTemperatureData(_ data: Data) -> Double {
            // BLE の値のエンディアン等に合わせて変換（例示）
            var temp: Float = 0
            (data as NSData).getBytes(&temp, length: MemoryLayout<Float>.size)
            return Double(temp)
    }
    
    /// UT-201 BLE Plus などの 2A1C (Health Thermometer Measurement) 用
    /// data例: 04 71 01 00 FF 02
    /// 戻り値: ℃
    func parseTemperature2A1C(_ data: Data) -> Double? {
        guard data.count >= 5 else { return nil }

        let flags = data[0]
        // bit0: unit (0=Celsius, 1=Fahrenheit)
        let unitIsF = (flags & 0x01) != 0

        // temperature is IEEE-11073 FLOAT (4 bytes) at offset 1
        guard let celsius = readIEEE11073Float32LE(data, offset: 1) else { return nil }

        if unitIsF {
            // 念のため：Fで来た場合はCに戻す（UT-201は通常C）
            return (celsius - 32.0) * 5.0 / 9.0
        } else {
            return celsius
        }
    }
    
    func readIEEE11073Float32LE(_ data: Data, offset: Int) -> Double? {
        guard data.count >= offset + 4 else { return nil }

        // mantissa: 24-bit signed (little endian)
        var mantissa: Int32 =
            Int32(data[offset]) |
            (Int32(data[offset + 1]) << 8) |
            (Int32(data[offset + 2]) << 16)

        // sign-extend 24-bit -> 32-bit
        if (mantissa & 0x0080_0000) != 0 {
            mantissa |= Int32(bitPattern: 0xFF00_0000)   // ← ここがポイント
            // あるいは mantissa |= -0x0100_0000 でもOK
        }

        let exponent = Int8(bitPattern: data[offset + 3])
        return Double(mantissa) * pow(10.0, Double(exponent))
    }


}

// セーブ用のデータモデル
import Foundation

struct TempRecord: Codable, Identifiable {
    let id: String              // UUID文字列など
    let measuredAt: Date        // 測定日時
    let temperature: Double

}

/*
 2) 端末保存：JSON Lines で追記する Repository
 保存場所：Documents/bp_records.jsonl
 追記：1レコードをJSONにして末尾に \n を付けて append
 取得：全行を読み、必要なら日付でフィルタ
 */

final class TempStore {
    static let shared = TempStore()
    private init() {}

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("temp_records.json") // jsonlだとiPhoneで見えないので、json に変更した
    }

    /// 追記保存
    func append(_ record: TempRecord) throws {
        print("append TempRecord \(record)")
        let lineData = try encoder.encode(record) + Data([0x0A]) // "\n"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.close()
        } else {
            try lineData.write(to: fileURL, options: .atomic)
        }
    }

    /// 全件読み込み（必要な分だけ filter して使う）
    func loadAll() throws -> [TempRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var out: [TempRecord] = []
        for line in text.split(separator: "\n") {
            if let d = line.data(using: .utf8),
               let r = try? decoder.decode(TempRecord.self, from: d) {
                out.append(r)
            }
        }
        return out.sorted { $0.measuredAt > $1.measuredAt }
    }

    /// 直近N日分だけ
    func loadSince(days: Int) throws -> [TempRecord] {
        let all = try loadAll()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return all.filter { $0.measuredAt >= cutoff }
    }

    /// 古いデータを削る（例：90日より古いものを削除）※必要なら
    func compact(keepDays: Int) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date())!
        let kept = try loadAll().filter { $0.measuredAt >= cutoff }

        // JSONLを書き直し
        var buf = Data()
        for r in kept.sorted(by: { $0.measuredAt < $1.measuredAt }) {
            buf += try encoder.encode(r) + Data([0x0A])
        }
        try buf.write(to: fileURL, options: .atomic)
    }
}


