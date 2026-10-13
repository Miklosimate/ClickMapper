import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var model: Diagnostic
    @ObservedObject var mapper: Mapper
    var openMapper: () -> Void
    var quit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ClickMapper").font(.title2.bold())
                        Label(model.connected ? "Controller connected" : "Waiting for controller", systemImage: model.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .font(.caption).foregroundStyle(model.connected ? Color.green : Color.secondary)
                    }
                    Spacer()
                    Button(mapper.enabled ? "Pause output" : "Enable output") {
                        if mapper.enabled { mapper.enabled = false } else { mapper.enable() }
                    }.buttonStyle(.borderedProminent)
                }
                HStack(spacing: 8) {
                    compactPod(left: true)
                    compactPod(left: false)
                }.frame(maxWidth: .infinity)
                HStack {
                    Text("Live input · \(mapper.pressed.isEmpty ? "press any pod button" : mapper.pressed.sorted().joined(separator: ", "))")
                    Spacer()
                    Button("Edit \(mapper.selected.uppercased())…", action: openMapper)
                }.font(.caption)
                Text("Schematic positions use your learned mappings. Output goes to the foreground app.")
                    .font(.caption2).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Controllers").font(.headline)
                    if model.scanning { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(model.scanning ? "Stop scan" : "Find devices") { if model.scanning { model.stopScan() } else { model.scan() } }
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.devices.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right").font(.title2)
                                Text("Wake both pods and choose Find devices.")
                                Text("Only Zwift Click devices appear here.").foregroundStyle(.secondary)
                            }.font(.caption).frame(maxWidth: .infinity).padding(18)
                        }
                        ForEach(model.devices) { device in
                            HStack(spacing: 10) {
                                Image(systemName: model.activeID == device.id ? "checkmark.circle.fill" : "gamecontroller")
                                    .foregroundStyle(model.activeID == device.id ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.callout.bold())
                                    Text("\(device.id.uuidString.prefix(8))\(model.preferredID == device.id.uuidString ? " · Auto-connect device" : "")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(device.lastSeen == nil ? "Saved device · wake to connect" : "\(device.rssi) dBm · \(signal(device.rssi))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.activeID == device.id {
                                    Button(model.connected ? "Disconnect" : "Cancel") { model.disconnect() }
                                } else {
                                    Button(model.activeID == nil ? "Connect" : "Switch") { model.selectDevice(device.id) }
                                }
                            }.padding(10).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.frame(height: 145)
                Toggle("Automatically reconnect", isOn: $model.autoConnect).font(.callout)
                if model.autoConnectPaused && model.autoConnect {
                    HStack {
                        Text("Paused after manual disconnect").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Resume") { model.resumeAutoConnect() }
                    }
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Divider()
                Text(mapper.permissionStatus).font(.caption2).foregroundStyle(.secondary)
                Text(mapper.outputStatus).font(.caption2).lineLimit(2).textSelection(.enabled)
                HStack {
                    Button("Open mapper…", action: openMapper)
                    Button("Permissions…") { mapper.requestPermission() }
                    Spacer()
                    Button("Quit", action: quit)
                }
            }.padding(16)
        }.frame(width: 500, height: 700).background(Color(nsColor: .windowBackgroundColor))
    }
    private func compactPod(left: Bool) -> some View {
        MapperView(mapper: mapper).pod(left: left)
            .scaleEffect(0.66).frame(width: 150, height: 205)
    }
    private func signal(_ rssi: Int) -> String {
        if rssi >= -60 { return "Strong signal" }
        if rssi >= -80 { return "Fair signal" }
        return "Weak signal"
    }
}
