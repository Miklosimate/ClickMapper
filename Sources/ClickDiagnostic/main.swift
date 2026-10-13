import AppKit
import SwiftUI
import CoreBluetooth

struct DeviceRow: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date? = nil
}

final class Diagnostic: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [DeviceRow] = []
    @Published var status = "Initializing Bluetooth"
    let mapper = Mapper()
    @Published var log = "ClickMapper ready. Keyboard output starts disabled.\n"
    @Published var activeID: UUID?
    @Published var preferredID = UserDefaults.standard.string(forKey: "preferredController")
    @Published var autoConnect = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "autoConnect")
            autoConnectPaused = false
            if autoConnect { tryAutoConnect() }
        }
    }
    @Published var autoConnectPaused = false
    private var reconnectTimer: Timer?
    private var connectionToken = UUID()
    @Published var connected = false
    @Published var scanning = false
    @Published var notifications = 0
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private var writer: CBCharacteristic?
    private var notifier: CBCharacteristic?
    private var scanTimeout: Timer?
    private var keepalive: Timer?
    private var started: Date?
    private var pressed: Set<String> = []
    private var handshakeStarted = false
    private let notifyID = CBUUID(string: "00000002-19ca-4651-86e5-fa29dcdd09d1")
    private let writeID = CBUUID(string: "00000003-19ca-4651-86e5-fa29dcdd09d1")
    override init() {
        super.init()
        mapper.onOutput = { [weak self] text in self?.record(text) }
        central = CBCentralManager(delegate: self, queue: .main)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.tryAutoConnect() }
    }
    func record(_ value: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log += "[\(time)] \(value)\n"
        if log.count > 100_000 { log = String(log.suffix(80_000)) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "Ready — wake a pod, then Scan"
        case .unauthorized: status = "Bluetooth permission required in System Settings"
        case .poweredOff: status = "Bluetooth is switched off"
        default: status = "Bluetooth unavailable (\(central.state.rawValue))"
        }
        if central.state != .poweredOn { reset(); scanning = false }
        record(status)
        if central.state == .poweredOn { tryAutoConnect() }
    }
    func tryAutoConnect() {
        guard autoConnect, !autoConnectPaused, active == nil, central.state == .poweredOn,
              let saved = preferredID, let id = UUID(uuidString: saved) else { return }
        if peripherals[id] == nil, let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = peripheral
            if !devices.contains(where: { $0.id == id }) {
                devices.append(DeviceRow(id: id, name: peripheral.name ?? "Zwift Click", rssi: 0))
            }
        }
        if peripherals[id] != nil { connect(id) } else if !scanning { scan() }
    }
    func resumeAutoConnect() { autoConnectPaused = false; tryAutoConnect() }
    func scan() {
        guard central.state == .poweredOn else { return }
        scanTimeout?.invalidate()
        scanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        record("Scanning for Zwift Click only. Rows stay in discovery order. Scan stops after 20 seconds.")
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.stopScan() }
    }
    func stopScan() { scanTimeout?.invalidate(); scanTimeout = nil; central.stopScan(); scanning = false }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unnamed device"
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("zwift click") else { return }
        peripherals[peripheral.identifier] = peripheral
        let row = DeviceRow(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: Date())
        if let index = devices.firstIndex(where: { $0.id == row.id }) { devices[index] = row }
        else { devices.append(row) }
        if preferredID == peripheral.identifier.uuidString { tryAutoConnect() }
    }
    func selectDevice(_ id: UUID) {
        guard id != activeID else { return }
        if active != nil { disconnect() }
        autoConnectPaused = false
        connect(id)
    }
    func rememberDevice() {
        guard connected, let activeID else { return }
        preferredID = activeID.uuidString
        UserDefaults.standard.set(preferredID, forKey: "preferredController")
        record("Remembered working controller: \(activeID.uuidString)")
    }
    func connect(_ id: UUID) {
        guard active == nil, let peripheral = peripherals[id] else { return }
        stopScan()
        active = peripheral
        activeID = id
        connectionToken = UUID()
        let token = connectionToken
        peripheral.delegate = self
        status = "Connecting to \(peripheral.name ?? "controller") · \(id.uuidString.prefix(8))"
        record(status)
        central.connect(peripheral)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.active === peripheral, self.connectionToken == token, !self.connected else { return }
            self.record("Connection timed out; will retry if auto-connect is enabled."); self.disconnect(manual: false)
        }
    }
    func disconnect(manual: Bool = true) {
        if manual { autoConnectPaused = true }
        if let active { central.cancelPeripheralConnection(active) }
        reset()
        status = "Disconnected"
    }
    private func reset() {
        connectionToken = UUID()
        mapper.disconnected()
        keepalive?.invalidate(); keepalive = nil
        if !pressed.isEmpty { record("Cleared held buttons: \(pressed.sorted().joined(separator: ", "))") }
        pressed = []; connected = false; active = nil; activeID = nil; writer = nil; notifier = nil
        handshakeStarted = false; started = nil
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active === peripheral else { return }
        connected = true; notifications = 0
        status = "Connected — discovering services"
        record(status); peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard active === peripheral else { return }
        record("Connection failed: \(error?.localizedDescription ?? "unknown")"); reset(); status = "Connection failed"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard active === peripheral else { return }
        record("Disconnected: \(error?.localizedDescription ?? "normal")"); reset(); status = "Disconnected — waiting to reconnect"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active === peripheral else { return }
        if let error { record(error.localizedDescription); return }
        for service in peripheral.services ?? [] {
            record("Service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active === peripheral else { return }
        if let error { record(error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] {
            record("Characteristic \(characteristic.uuid), properties=\(characteristic.properties.rawValue)")
            if characteristic.uuid == writeID { writer = characteristic }
            if characteristic.uuid == notifyID { notifier = characteristic }
            if ["2A19", "2A26"].contains(characteristic.uuid.uuidString), characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
        if writer != nil, let notifier, !notifier.isNotifying, !handshakeStarted {
            handshakeStarted = true
            peripheral.setNotifyValue(true, for: notifier)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard active === peripheral, characteristic.uuid == notifyID else { return }
        if let error { record("Subscription failed: \(error.localizedDescription)"); return }
        guard characteristic.isNotifying else { return }
        record("Trying community V2 handshake; compatibility with this firmware is unverified.")
        let token = connectionToken
        let packets: [[UInt8]] = [[0x52,0x69,0x64,0x65,0x4f,0x6e,0x02,0x03], [0,8,0], [0,8,0x10]]
        for (index, packet) in packets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) { [weak self, weak peripheral] in
                guard let self, let peripheral, self.active === peripheral, self.connectionToken == token else { return }
                self.write(packet)
            }
        }
        started = Date()
        status = "Connected · \(peripheral.identifier.uuidString.prefix(8)) — press buttons on both pods to check input"
        keepalive = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.write([0,8,0x10]) }
    }
    private func write(_ bytes: [UInt8]) {
        guard let active, let writer else { return }
        if writer.properties.contains(.writeWithoutResponse) {
            guard active.canSendWriteWithoutResponse else { record("Write deferred: Bluetooth backpressure"); return }
            active.writeValue(Data(bytes), for: writer, type: .withoutResponse)
        } else if writer.properties.contains(.write) {
            active.writeValue(Data(bytes), for: writer, type: .withResponse)
        } else { record("Expected characteristic is not writable") }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { record("Write failed: \(error.localizedDescription)") }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active === peripheral else { return }
        if let error { record("Read failed: \(error.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == CBUUID(string: "2A19") { record("Battery: \(data.first ?? 0)%"); return }
        if characteristic.uuid == CBUUID(string: "2A26") { record("Firmware: \(String(data: data, encoding: .utf8) ?? "unreadable")"); return }
        guard characteristic.uuid == notifyID else { return }
        notifications += 1
        let bytes = Array(data)
        // Only log recognized state frames; unknown payloads could contain session material.
        guard bytes.count == 7, bytes[0] == 0x23, bytes[1] == 8 else {
            if notifications <= 10 || notifications % 100 == 0 { record("Unrecognized notification (\(data.count) bytes); payload omitted") }
            return
        }
        if preferredID != peripheral.identifier.uuidString { rememberDevice() }
        let names = [0:"left", 1:"up", 2:"right", 3:"down", 4:"a", 5:"b", 6:"y", 8:"z", 9:"minus", 13:"plus"]
        var current: Set<String> = []
        for offset in 0..<4 {
            for bit in 0..<8 where bytes[offset + 2] & (1 << bit) == 0 {
                current.insert(names[offset * 8 + bit] ?? "unknown_\(offset)_\(bit)")
            }
        }
        let elapsed = Int(Date().timeIntervalSince(started ?? Date()))
        for name in current.subtracting(pressed).sorted() { record("+\(elapsed)s DOWN \(name) [candidate ID]") }
        for name in pressed.subtracting(current).sorted() { record("+\(elapsed)s UP   \(name) [candidate ID]") }
        mapper.receive(current)
        pressed = current
    }
}

struct DiagnosticView: View {
    @ObservedObject var model: Diagnostic
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            MapperView(mapper: model.mapper)
            Text(model.status)
            HStack {
                Button(model.scanning ? "Stop Scan" : "Scan") { model.scanning ? model.stopScan() : model.scan() }
                Button("Disconnect") { model.disconnect() }.disabled(model.activeID == nil)
                Button("Remember working device") { model.rememberDevice() }.disabled(!model.connected)
                Text("Notifications: \(model.notifications)").monospacedDigit()
                Spacer()
                Button("Clear Log") { model.log = "" }
            }
            Text("Zwift Click devices only. If just one pod responds, wake both and use Switch on the other device. Once both work, click Remember working device.").font(.caption)
            List(model.devices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(device.name) · \(device.id.uuidString.prefix(8))")
                        if model.preferredID == device.id.uuidString { Text("Remembered working device").font(.caption).foregroundStyle(.green) }
                        Text(device.id.uuidString).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(device.rssi) dBm")
                    if model.activeID == device.id {
                        Text(model.connected ? "Connected" : "Connecting…").foregroundStyle(.green)
                    } else {
                        Button(model.activeID == nil ? "Connect" : "Switch") { model.selectDevice(device.id) }
                    }
                }
            }.frame(height: 150)
            ScrollView {
                Text(model.log).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 140).background(Color(nsColor: .textBackgroundColor))
            Text("Keyboard output requires Accessibility permission. No trainer connection or firmware updates.").font(.caption).foregroundStyle(.secondary)
        }.padding(16)
        }.frame(minWidth: 860, minHeight: 650)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var model: Diagnostic!
    private var statusItem: NSStatusItem!
    private var statusTimer: Timer?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Diagnostic()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 500, height: 700)
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(model: model, mapper: model.mapper, openMapper: { [weak self] in self?.showMapper() }, quit: { NSApp.terminate(nil) }))
        updateStatusIcon()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatusIcon() }
    }
    private func updateStatusIcon() {
        let symbol = model.mapper.enabled ? "keyboard.fill" : "keyboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClickMapper")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "ClickMapper · \(model.connected ? "Connected" : "Disconnected") · Output \(model.mapper.enabled ? "on" : "off")"
    }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    @objc private func showMapper() {
        popover.performClose(nil)
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "ClickMapper"
            window.contentView = NSHostingView(rootView: DiagnosticView(model: model))
            window.center()
        }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMapper(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        model?.disconnect()
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
