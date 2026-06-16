//
//  Sensors.swift
//  NAMI BLE Chat
//
//  Created by 荻野正 on 2026/01/31.
//

//
//  BLEBloodiOSApp.swift
//  BLEBloodiOS
//
//  Created by 荻野正 on 2026/01/31.
//

import SwiftUI
import CoreBluetooth
import Combine   // ← これが重要

enum HistoryType: Hashable {
    case bloodPressure
    case temperature
}

struct BloodPressureView: View {
    @EnvironmentObject var userMessage: UserMessage

    var body: some View {
        BloodPressureInnerView(vm: BloodPressureViewModel(userMessage: userMessage), btvm: BodyTemperatureViewModel(userMessage: userMessage))
    }
}

struct BloodPressureInnerView: View {
    @StateObject var vm: BloodPressureViewModel
//    @StateObject private var vm = BloodPressureViewModel()
    @State private var text: String = "loading..."
    @EnvironmentObject var userMessage: UserMessage
    @StateObject var btvm: BodyTemperatureViewModel
    @State private var historyType: HistoryType = .bloodPressure
    @State private var displaytext: String = ""

    
    init(vm: BloodPressureViewModel, btvm: BodyTemperatureViewModel) {
        _vm = StateObject(wrappedValue: vm)
        _btvm = StateObject(wrappedValue: btvm)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Health Care Data")
                .font(.title3)
            
            Picker("", selection: $historyType) {
                Text("BP").tag(HistoryType.bloodPressure)
                Text("Temp").tag(HistoryType.temperature)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .pickerStyle(.segmented)
            .onChange(of: historyType) { _ in
                loadHistory()
            }
            
            // ★ 現在値表示を切り替える
            currentValueView   // ← ここで表示切り替え
                .font(.title3)
            
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .onAppear {
                loadHistory()
            }
             

        }
        .padding()
    }
    
    @ViewBuilder
    private var currentValueView: some View {
        switch historyType {
        case .bloodPressure:
            Text(vm.status)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Text("SYS: \(vm.systolicText)")
                Text("DIA: \(vm.diastolicText)")
                Text("Pulse: \(vm.pulseText)")
                Text("Timestamp: \(vm.timestampText)")
            }
            HStack(spacing: 12) {
                Button("Get BP Result") { vm.start() }
                //Button("Stop") { vm.stop() } // UI上変なので消してみた
            }

        case .temperature:
            Text(btvm.status)
                .foregroundColor(.secondary)
            Text("Temp: \(btvm.tempText)")
            HStack(spacing: 12) {
                Button("Get Temp Result") { btvm.start() }
            }
        }
    }
    
    func loadHistory() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"

        do {
            switch historyType {

            case .bloodPressure:
                let all = try BPStore.shared.loadAll()
                text = all.map {
                    "\(f.string(from: $0.measuredAt))  SYS \(String(format:"%.0f",$0.systolic))  DIA \(String(format:"%.0f",$0.diastolic))  P \( $0.pulse.map{String(format:"%.0f",$0)} ?? "-" )"
                }.joined(separator: "\n")

            case .temperature:
                let all = try TempStore.shared.loadAll()
                text = all.map {
                    "\(f.string(from: $0.measuredAt))  TEMP \(String(format:"%.1f",$0.temperature)) ℃"
                }.joined(separator: "\n")
            }

        } catch {
            text = "load failed: \(error)"
        }
    }

}

struct BPRecord: Codable, Identifiable {
    let id: String              // UUID文字列など
    let measuredAt: Date        // 測定日時
    let systolic: Double
    let diastolic: Double
    let map: Double
    let pulse: Double?

    // 追加で欲しければ
    let deviceName: String?
    let unit: String            // "mmHg" 固定でもOK
}

struct BPJsonRecord: Codable {
    let systolic: Float
    let diastolic: Float
    let pulse: Float?

    let datetime: String

    enum CodingKeys: String, CodingKey {
        case systolic = "SYS"
        case diastolic = "DIA"
        case pulse = "PULSE"
        case datetime = "DATETIME"
    }
}

@MainActor
final class BloodPressureViewModel: NSObject, ObservableObject {
    // MARK: - Published UI
    @Published var status: String = "Idle"
    @Published var systolicText: String = "-"
    @Published var diastolicText: String = "-"
    @Published var meanArterialText: String = "-"
    @Published var pulseText: String = "-"
    @Published var timestampText: String = "-"

    // MARK: - CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    // GATT UUIDs (16-bit)
    private let bloodPressureService = CBUUID(string: "1810")
    private let bpMeasurementChar   = CBUUID(string: "2A35")
    private let intermediateCuffPressureChar = CBUUID(string: "2A36") // 任意（対応機器のみ）
    private let pulseRateChar       = CBUUID(string: "2A37") // HR service側の可能性もあるので参考

    private var bpFeatureCount = 0
    
    @Published var historyRefreshToken = UUID() // ← 追加
    
    private let BPDateFormatter: DateFormatter = {
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

        // 1810 を広告していない機器もあるので、本番では nil scan + 後段フィルタも検討
        central.scanForPeripherals(withServices: [bloodPressureService], options: [
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
        systolicText = "-"
        diastolicText = "-"
        meanArterialText = "-"
        pulseText = "-"
        timestampText = "-"
    }
}

// MARK: - CBCentralManagerDelegate
extension BloodPressureViewModel: CBCentralManagerDelegate {
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
        peripheral.discoverServices([bloodPressureService])
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
extension BloodPressureViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("didDiscoverServices in BloodPressureViewModel")

        if let error = error {
            status = "Service discovery error: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services else { return }

        for s in services where s.uuid == bloodPressureService {
            status = "Blood Pressure Service found. Discovering characteristics..."
            peripheral.discoverCharacteristics([bpMeasurementChar, intermediateCuffPressureChar], for: s)
            return
        }
        status = "Blood Pressure Service not found"
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        print("didDiscoverCharacteristicsFor in BloodPressureViewModel")
        if let error = error {
            status = "Characteristic discovery error: \(error.localizedDescription)"
            return
        }
        guard let chars = service.characteristics else { return }

        for c in chars {
            if c.uuid == bpMeasurementChar {
                status = "Subscribing BP Measurement (Notify)..."
                peripheral.setNotifyValue(true, for: c)
            }
            // 2A36 など他も必要ならここで notify/read
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("didUpdateNotificastionStateFor in BloodPressureViewModel")
        if let error = error {
            status = "Notify state error: \(error.localizedDescription)"
            return
        }
        status = "Notify enabled for \(characteristic.uuid)"
    }

    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("didUpdateValueFor in BloodPressureViewModel")

        if let error = error {
            status = "Update value error: \(error.localizedDescription)"
            return
        }
        guard let data = characteristic.value else { return }
        // 🔹 2A35 をカウント
        if characteristic.uuid == CBUUID(string: "2A35") {
            bpFeatureCount += 1

            // hexダンプ
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")

            print("2A35 received count=\(bpFeatureCount), bytes=\(data.count), data=\(hex)")
        }
        if characteristic.uuid == bpMeasurementChar {
            if let decoded = BloodPressureMeasurement.decode(data: data) {
                status = "BP received"

                systolicText = format(decoded.systolic)
                diastolicText = format(decoded.diastolic)
                meanArterialText = format(decoded.meanArterialPressure)

                if let pulse = decoded.pulseRate {
                    pulseText = format(pulse)
                } else {
                    pulseText = "-"
                }

                if let ts = decoded.timestamp {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    timestampText = f.string(from: ts)
                } else {
                    timestampText = "-"
                }
                
                // この時点でデータが揃っている
                // とりあえずそのまま書く
                let bpdata = "\(systolicText),\(diastolicText),\(meanArterialText)"
                //self.userMessage.addItemWithGPS(userMessageText: "[BPDATA]"+bpdata)
                
                // 3) BLE受信（2A35）した瞬間に保存する
                let rec = BPRecord(
                    id: UUID().uuidString,
                    measuredAt: decoded.timestamp ?? Date(),   // 血圧計がtimestamp出さない場合は端末時刻
                    systolic: decoded.systolic,
                    diastolic: decoded.diastolic,
                    map: decoded.meanArterialPressure,
                    pulse: decoded.pulseRate,
                    deviceName: peripheral.name,
                    unit: "mmHg"
                )

                do {
                    try BPStore.shared.append(rec)
                    print("BP saved: \(rec.measuredAt)")
                    DispatchQueue.main.async {
                        print("token update on main? \(Thread.isMainThread)")
                        self.historyRefreshToken = UUID()
                    }
                    historyRefreshToken = UUID() // ← 保存後に更新
                    // この時点で最近のデータを読む
                    let jsonstring = try makeBPJsonLast7Days()
                    print("last 7 days: \n\(jsonstring)")
                    self.userMessage.addItemWithGPS(userMessageText: "[BPDATA]"+jsonstring)

                } catch {
                    print("BP save failed: \(error)")
                }

                
            } else {
                status = "BP decode failed (\(data.count) bytes)"
            }
        }
    }

    
    func makeBPJsonLast7Days() throws -> String {
        // ① repositoryから全件または必要分を取得（例）
        // ここはあなたの実装に合わせてください
        let all: [BPRecord] = try BPStore.shared.loadAll()

        // ② 7日前の境界
        let from = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        // ③ 7日以内だけに絞る（日時が新しい順に並べたい場合）
        let recent = all
            .filter { $0.measuredAt >= from }
            .sorted { $0.measuredAt > $1.measuredAt }

        // ④ JSON用DTOに変換
        let systolic: Float
        let diastolic: Float
        let pulse: Float?

        let dto: [BPJsonRecord] = recent.map {
            BPJsonRecord(
                systolic : Float($0.systolic),
                diastolic: Float($0.diastolic),
                pulse: Float($0.pulse ?? 0.0),
                datetime: BPDateFormatter.string(from: $0.measuredAt)
            )
        }

        // ⑤ JSONエンコード
        let encoder = JSONEncoder()
        //encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] // 好みで
        encoder.outputFormatting = [.withoutEscapingSlashes] // 好みで
        let data = try encoder.encode(dto)
        return String(decoding: data, as: UTF8.self)
    }

    private func format(_ v: Double) -> String {
        // mmHgが一般的（単位がkPaの場合もあるので flags を見て切替可能）
        String(format: "%.1f", v)
    }
}

// MARK: - Blood Pressure Measurement decoder (0x2A35)
struct BloodPressureMeasurement {
    let systolic: Double
    let diastolic: Double
    let meanArterialPressure: Double
    let timestamp: Date?
    let pulseRate: Double?

    /// GATT仕様：Flags(1) + [SFLOAT x3] + (timestamp?) + (pulseRate SFLOAT?) ...
    static func decode(data: Data) -> BloodPressureMeasurement? {
        var idx = 0

        func readUInt8() -> UInt8? {
            guard idx + 1 <= data.count else { return nil }
            let v = data[idx]
            idx += 1
            return v
        }

        func readUInt16LE() -> UInt16? {
            guard idx + 2 <= data.count else { return nil }
            let v = UInt16(data[idx]) | (UInt16(data[idx+1]) << 8)
            idx += 2
            return v
        }

        func readSFloat() -> Double? {
            guard let raw = readUInt16LE() else { return nil }

            // 12-bit mantissa (signed)
            var mant = Int(raw & 0x0FFF)
            if (mant & 0x0800) != 0 {        // negative
                mant -= 0x1000              // sign-extend: subtract 2^12
            }

            // 4-bit exponent (signed)
            var exp = Int((raw >> 12) & 0x000F)
            if (exp & 0x0008) != 0 {        // negative
                exp -= 0x0010              // sign-extend: subtract 2^4
            }

            // IEEE-11073 special values (optional: handle if you want)
            // 0x07FF = NaN, 0x07FE = +INF, 0x0802 = -INF, 0x0800 = NRes, etc.
            // 実運用で必要ならここで判定して nil にするなど。

            return Double(mant) * pow(10.0, Double(exp))
        }
        
        guard let flags = readUInt8() else { return nil }

        let unitIsKPa = (flags & 0x01) != 0
        let hasTimestamp = (flags & 0x02) != 0
        let hasPulseRate = (flags & 0x04) != 0

        guard
            let sys = readSFloat(),
            let dia = readSFloat(),
            let map = readSFloat()
        else { return nil }

        var timestamp: Date? = nil
        if hasTimestamp {
            // Date Time: year(2) month(1) day(1) hour(1) min(1) sec(1)
            guard
                let year = readUInt16LE(),
                let month = readUInt8(),
                let day = readUInt8(),
                let hour = readUInt8(),
                let minute = readUInt8(),
                let second = readUInt8()
            else { return nil }

            var comps = DateComponents()
            comps.calendar = Calendar(identifier: .gregorian)
            comps.timeZone = TimeZone.current
            comps.year = Int(year)
            comps.month = Int(month)
            comps.day = Int(day)
            comps.hour = Int(hour)
            comps.minute = Int(minute)
            comps.second = Int(second)
            
            let candidate = comps.date

            // ✅ ここで「壊れているtimestamp」を弾いて、受信時刻にフォールバック
            // 例: 1970-01-01 付近 or 2000年より前は無効扱い、など
            if let dt = candidate,
               dt.timeIntervalSince1970 >= 946684800 { // 2000-01-01 00:00:00 UTC
                timestamp = dt
            } else {
                timestamp = Date()
            }
            
            //timestamp = comps.date
        }

        var pulse: Double? = nil
        if hasPulseRate {
            pulse = readSFloat()
        }

        // 単位がkPaならmmHgへ変換（1 kPa ≒ 7.50062 mmHg）
        if unitIsKPa {
            let factor = 7.50062
            return BloodPressureMeasurement(
                systolic: sys * factor,
                diastolic: dia * factor,
                meanArterialPressure: map * factor,
                timestamp: timestamp,
                pulseRate: pulse
            )
        } else {
            return BloodPressureMeasurement(
                systolic: sys,
                diastolic: dia,
                meanArterialPressure: map,
                timestamp: timestamp,
                pulseRate: pulse
            )
        }
    }
}


// セーブ用のデータモデル
import Foundation

// 上にあった
/*
struct BPRecord: Codable, Identifiable {
    let id: String              // UUID文字列など
    let measuredAt: Date        // 測定日時
    let systolic: Double
    let diastolic: Double
    let map: Double
    let pulse: Double?

    // 追加で欲しければ
    let deviceName: String?
    let unit: String            // "mmHg" 固定でもOK
}
*/

/*
 2) 端末保存：JSON Lines で追記する Repository
 保存場所：Documents/bp_records.jsonl
 追記：1レコードをJSONにして末尾に \n を付けて append
 取得：全行を読み、必要なら日付でフィルタ
 */

final class BPStore {
    static let shared = BPStore()
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
        return dir.appendingPathComponent("bp_records.json")
    }

    /// 追記保存
    func append(_ record: BPRecord) throws {
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
    func loadAll() throws -> [BPRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var out: [BPRecord] = []
        for line in text.split(separator: "\n") {
            if let d = line.data(using: .utf8),
               let r = try? decoder.decode(BPRecord.self, from: d) {
                out.append(r)
            }
        }
        return out.sorted { $0.measuredAt > $1.measuredAt }
    }

    /// 直近N日分だけ
    func loadSince(days: Int) throws -> [BPRecord] {
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

// 4) 端末側で「テキストで見る」最小UI（SwiftUI）

import SwiftUI

struct BPHistoryView: View {
    @ObservedObject var vm: BloodPressureViewModel
    @State private var text: String = "loading..."
    
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .onAppear {
            print("onAppear in BPHistoryView")
            reloadHistory()
        }
        .onReceive(vm.$historyRefreshToken) { _ in   // ← ここが確実
            print("onReceive in BPHistoryView")
            reloadHistory()
        }
        .onChange(of: vm.historyRefreshToken) {
            print("onChange in BPHistoryView")

            reloadHistory()
        }
        /*
        .onAppear {
            do {
                let all = try BPStore.shared.loadAll()
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                text = all.map {
                    "\(f.string(from: $0.measuredAt))  SYS \(String(format:"%.1f",$0.systolic))  DIA \(String(format:"%.1f",$0.diastolic))  P \( $0.pulse.map{String(format:"%.1f",$0)} ?? "-" )"
                }.joined(separator: "\n")
            } catch {
                text = "load failed: \(error)"
            }
        }
         */
    }
    
    private func reloadHistory() {
        print("reloadHistory is called")
        do {
            let all = try BPStore.shared.loadAll()
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            text = all.map {
                "\(f.string(from: $0.measuredAt))  SYS \(String(format:"%.1f",$0.systolic))  DIA \(String(format:"%.1f",$0.diastolic))  P \( $0.pulse.map{String(format:"%.1f",$0)} ?? "-" )"
            }.joined(separator: "\n")
        } catch {
            text = "load failed: \(error)"
        }
    }
}

