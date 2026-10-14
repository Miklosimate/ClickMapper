import AppKit
import SwiftUI
import ApplicationServices

struct KeyBinding: Codable, Equatable {
    var code: UInt16 = 0
    var label = "Unassigned"
    var modifiers: UInt64 = 0
    var mode = "Tap"
    var assigned = false
    var longPress: String? = nil
    var scrollSpeed: Int? = nil
    var displayLabel: String {
        guard assigned else { return "—" }
        let flags: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        return flags.filter { modifiers & $0.0.rawValue != 0 }.map { $0.1 }.joined() + label
    }
}

enum KeyboardEvents {
    static func make(code: UInt16, down: Bool, modifiers: UInt64, repeating: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: down) else { return nil }
        var flags = CGEventFlags(rawValue: modifiers)
        // Arrow keys are navigation/function keys, not ordinary printable keys.
        let arrows: [UInt16: UniChar] = [123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700]
        if var character = arrows[code] {
            flags.formUnion([.maskNumericPad, .maskSecondaryFn])
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: down && repeating ? 1 : 0)
        return event
    }
}

final class Mapper: ObservableObject {
    static let slots = ["left", "up", "right", "down", "minus", "a", "b", "y", "z", "plus"]
    @Published var bindings: [String: KeyBinding] = [:]
    @Published var sources: [String: String] = [:]
    @Published var selected = "plus"
    @Published var learning = false
    @Published var recording = false
    @Published var enabled = false { didSet { if !enabled { releaseAll() } } }
    @Published var pressed: Set<String> = []
    @Published var recentPresses: Set<String> = []
    private var flashGeneration: [String: UUID] = [:]
    @Published var message = "Output is off. Choose a button to edit its mapping."
    private let defaults: UserDefaults
    private let outputContext: () -> Bool
    private let postingAccess: () -> Bool
    private var held: [String: KeyBinding] = [:]
    private var repeating: [String: Timer] = [:]
    private var monitor: Any?
    private var focusObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    @Published var outputStatus = "No keyboard output attempted yet."
    @Published var testPending = false
    @Published var permissionStatus = "Checking permissions…"
    var onOutput: ((String) -> Void)?
    private var testWork: DispatchWorkItem?
    var emit: (UInt16, Bool, UInt64, Bool) -> Void = { _, _, _, _ in }
    func report(_ text: String) { outputStatus = text; onOutput?("Keyboard: " + text) }
    var blockedReason: String {
        if !enabled { return "Output disabled." }
        if learning || recording { return "Learning or shortcut recording is active." }
        if !CGPreflightPostEventAccess() { return "macOS has not granted keyboard-posting permission to this running build. Quit and re-add the app in Accessibility settings." }
        guard let app = NSWorkspace.shared.frontmostApplication else { return "No foreground app detected." }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return "ClickMapper is in front. Click inside a TextEdit document to test." }
        return "Output unavailable for \(app.localizedName ?? "the foreground app")."
    }
    func scheduleTest() {
        testWork?.cancel()
        guard allowed || (enabled && CGPreflightPostEventAccess()) else { report(blockedReason); return }
        testPending = true
        report("Test in 3 seconds: click inside a TextEdit document. Sends one I key using the current output rules.")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.testPending = false
            guard self.allowed else { self.report(self.blockedReason); return }
            self.tap(KeyBinding(code: 34, label: "I", assigned: true))
        }
        testWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    init(defaults: UserDefaults = .standard, outputContext: @escaping () -> Bool = Mapper.isOutputContextAllowed,
         postingAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() }) {
        self.defaults = defaults
        self.outputContext = outputContext
        self.postingAccess = postingAccess
        emit = { [weak self] code, down, flags, repeating in
            guard let event = KeyboardEvents.make(code: code, down: down, modifiers: flags, repeating: repeating) else {
                self?.report("Failed to create keyboard event."); return
            }
            event.post(tap: .cghidEventTap)
            if down {
                let target = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown app"
                self?.report("Posted key code \(code) to \(target). macOS does not confirm delivery.")
            }
        }
        sources = defaults.dictionary(forKey: "sources.v1") as? [String: String] ?? Dictionary(uniqueKeysWithValues: Self.slots.map { ($0, $0) })
        if let data = defaults.data(forKey: "bindings.v1"), let saved = try? JSONDecoder().decode([String: KeyBinding].self, from: data) { bindings = saved }
        else {
            bindings = Dictionary(uniqueKeysWithValues: Self.slots.map { ($0, KeyBinding()) })
            navigationPreset()
        }
        // Migrate the retired wheel-scrolling configuration to repeating arrow keys.
        for (slot, var binding) in bindings where binding.longPress != nil {
            let arrows: [String: (UInt16, String)] = ["Scroll up": (126, "↑"), "Scroll down": (125, "↓"), "Scroll left": (123, "←"), "Scroll right": (124, "→")]
            if let arrow = arrows[binding.longPress ?? ""] {
                binding.code = arrow.0; binding.label = arrow.1; binding.assigned = true; binding.mode = "Repeat"
            }
            binding.longPress = nil; binding.scrollSpeed = nil
            bindings[slot] = binding
        }
        save()
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseAll() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.enabled = false }
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshPermissions()
            guard self.enabled, !self.postingAccess() else { return }
            self.enabled = false; self.message = "Keyboard-posting permission is required."; self.report(self.message)
        }
    }
    deinit {
        testWork?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        permissionTimer?.invalidate()
        releaseAll()
    }
    func save() {
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "bindings.v1") }
        defaults.set(sources, forKey: "sources.v1")
    }
    func preset() {
        releaseAll()
        bindings = Dictionary(uniqueKeysWithValues: Self.slots.map { ($0, KeyBinding()) })
        bindings["plus"] = KeyBinding(code: 34, label: "I", assigned: true)
        bindings["minus"] = KeyBinding(code: 40, label: "K", assigned: true)
        save()
    }
    func update(_ binding: KeyBinding) { releaseAll(); bindings[selected] = binding; save() }
    func refreshPermissions() {
        permissionStatus = "Accessibility: \(AXIsProcessTrusted() ? "granted" : "denied") · Keyboard posting: \(CGPreflightPostEventAccess() ? "granted" : "denied")"
    }
    func requestPermission() {
        _ = CGRequestPostEventAccess()
        refreshPermissions()
        report(permissionStatus)
        if !CGPreflightPostEventAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    func enable() {
        refreshPermissions()
        guard CGPreflightPostEventAccess() else {
            message = "macOS denies keyboard posting for this running app. Use Grant permission; Enable output only checks the result."
            report(permissionStatus + " · App: " + Bundle.main.bundlePath)
            return
        }
        enabled = true; message = "Output armed. Switch to your target app."
        report(permissionStatus)
    }
    static func isOutputContextAllowed() -> Bool {
        guard CGPreflightPostEventAccess(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        return true
    }
    var allowed: Bool { enabled && !learning && !recording && outputContext() }
    func receive(_ current: Set<String>) {
        let down = current.subtracting(pressed)
        let up = pressed.subtracting(current)
        pressed = current
        for source in down {
            let generation = UUID()
            flashGeneration[source] = generation
            recentPresses.insert(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.flashGeneration[source] == generation else { return }
                self.recentPresses.remove(source)
                self.flashGeneration.removeValue(forKey: source)
            }
        }
        if learning, let source = down.sorted().first(where: { Self.slots.contains($0) }) {
            let old = sources[selected]
            if let other = Self.slots.first(where: { $0 != selected && sources[$0] == source }) { sources[other] = old }
            sources[selected] = source; learning = false; save()
            message = "Learned \(selected): decoded ID \(source)."; return
        }
        for source in up { stop(source) }
        guard allowed else { releaseAll(); if !down.isEmpty { report(blockedReason) }; return }
        for source in down {
            guard let slot = Self.slots.first(where: { sources[$0] == source }), let binding = bindings[slot], binding.assigned else { report("\(source) has no keyboard mapping. Choose a key in the mapper."); continue }
            if binding.mode == "Hold" || binding.mode == "Repeat" {
                let alreadyHeld = held.values.contains { $0.code == binding.code }
                held[source] = binding
                if !alreadyHeld { emit(binding.code, true, binding.modifiers, false) }
                if binding.mode == "Repeat" {
                    let delay = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        guard self.allowed, self.pressed.contains(source) else { self.releaseAll(); return }
                        self.emit(binding.code, true, binding.modifiers, true)
                        let timer = Timer(timeInterval: 0.035, repeats: true) { [weak self] _ in
                            guard let self else { return }
                            guard self.allowed, self.pressed.contains(source) else { self.releaseAll(); return }
                            self.emit(binding.code, true, binding.modifiers, true)
                        }
                        self.repeating[source] = timer
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    repeating[source] = delay
                    RunLoop.main.add(delay, forMode: .common)
                }
            } else {
                tap(binding)
            }
        }
    }
    func navigationPreset() {
        releaseAll()
        for (slot, code, label) in [("up", UInt16(126), "↑"), ("down", 125, "↓"), ("left", 123, "←"), ("right", 124, "→")] {
            bindings[slot] = KeyBinding(code: code, label: label, mode: "Repeat", assigned: true)
        }
        save()
        message = "Arrow buttons send immediately and repeat while held. Other mappings are unchanged."
    }
    private func tap(_ binding: KeyBinding) {
        // Do not release a key another physical button is holding.
        guard !held.values.contains(where: { $0.code == binding.code }) else { return }
        emit(binding.code, true, binding.modifiers, false); emit(binding.code, false, binding.modifiers, false)
    }
    private func stop(_ source: String) {
        repeating.removeValue(forKey: source)?.invalidate()
        if let binding = held.removeValue(forKey: source), !held.values.contains(where: { $0.code == binding.code }) {
            emit(binding.code, false, binding.modifiers, false)
        }
    }
    func releaseAll() { for source in Array(repeating.keys) { stop(source) }; for source in Array(held.keys) { stop(source) } }
    func disconnected() { releaseAll(); pressed = []; recentPresses = []; flashGeneration = [:]; enabled = false }
    func learn() { cancelRecording(); enabled = false; learning.toggle(); message = learning ? "Press the physical button shown in the selected position." : "Learning cancelled." }
    func cancelRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
    func recordKey() {
        enabled = false; learning = false; recording = true
        message = "Press a key or shortcut. Escape cancels; choose Escape from the menu to map it."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode != 53 {
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                let label = KeyChoice.all.first(where: { $0.code == event.keyCode })?.name ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
                var binding = self.bindings[self.selected] ?? KeyBinding()
                binding.code = event.keyCode; binding.label = label; binding.modifiers = UInt64(flags.rawValue); binding.assigned = true
                self.update(binding)
            }
            self.cancelRecording(); self.message = "Mapping saved."; return nil
        }
    }
}
struct KeyChoice {
    let name: String
    let code: UInt16
    static let all: [KeyChoice] = [
        ("A",0),("S",1),("D",2),("F",3),("H",4),("G",5),("Z",6),("X",7),("C",8),("V",9),("B",11),("Q",12),("W",13),("E",14),("R",15),("Y",16),("T",17),("1",18),("2",19),("3",20),("4",21),("6",22),("5",23),("=",24),("9",25),("7",26),("-",27),("8",28),("0",29),("]",30),("O",31),("U",32),("[",33),("I",34),("P",35),("Return",36),("L",37),("J",38),("'",39),("K",40),(";",41),("\\",42),(",",43),("/",44),("N",45),("M",46),(".",47),("Tab",48),("Space",49),("`",50),("Backspace",51),("Escape",53),("F1",122),("F2",120),("F3",99),("F4",118),("F5",96),("F6",97),("F7",98),("F8",100),("F9",101),("F10",109),("F11",103),("F12",111),("Home",115),("End",119),("Page Up",116),("Page Down",121),("Delete",117),("←",123),("→",124),("↓",125),("↑",126)
    ].map { KeyChoice(name: $0.0, code: UInt16($0.1)) }
}

struct MapperView: View {
    @ObservedObject var mapper: Mapper
    private var binding: KeyBinding { mapper.bindings[mapper.selected] ?? KeyBinding() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Your buttons. Your shortcuts.").font(.largeTitle.bold())
                    Text("Keyboard control for your Mac").foregroundStyle(.secondary)
                }
                Spacer()
                Button(mapper.enabled ? "Disable output" : "Enable output") { if mapper.enabled { mapper.enabled = false } else { mapper.enable() } }.buttonStyle(.borderedProminent)
            }
            HStack(alignment: .top, spacing: 24) {
                pod(left: true)
                pod(left: false)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Edit: \(mapper.selected.uppercased())").font(.headline)
                    Text("Decoded ID: \(mapper.sources[mapper.selected] ?? "—")").font(.caption).foregroundStyle(.secondary)
                    Picker("Key", selection: Binding(get: { binding.assigned ? Int(binding.code) : -1 }, set: { code in
                        var value = binding; value.assigned = code >= 0
                        if let choice = KeyChoice.all.first(where: { Int($0.code) == code }) { value.code = choice.code; value.label = choice.name; if (123...126).contains(choice.code) { value.mode = "Repeat" } }
                        mapper.update(value)
                    })) {
                        Text("Unassigned").tag(-1)
                        if binding.assigned && !KeyChoice.all.contains(where: { $0.code == binding.code }) {
                            Text(binding.label).tag(Int(binding.code))
                        }
                        ForEach(KeyChoice.all, id: \.code) { Text($0.name).tag(Int($0.code)) }
                    }
                    HStack {
                        modifier("⌘", .maskCommand); modifier("⌥", .maskAlternate)
                        modifier("⌃", .maskControl); modifier("⇧", .maskShift)
                    }
                    Picker("Behavior", selection: Binding(get: { binding.mode }, set: { var value = binding; value.mode = $0; mapper.update(value) })) {
                        ForEach(["Tap", "Hold", "Repeat"], id: \.self) { Text($0) }
                    }
                    Button(mapper.recording ? "Cancel recording" : "Record keyboard shortcut") { if mapper.recording { mapper.cancelRecording() } else { mapper.recordKey() } }
                    Button(mapper.learning ? "Cancel learning" : "Learn physical button") { mapper.learn() }
                    Divider()
                    Button("Map arrow keys") { mapper.navigationPreset() }
                    Button("Load MyWhoosh I / K preset") { mapper.preset() }
                    Text("Keys go to the focused app. Repeat starts after 250 ms, then sends every 35 ms. Arrow keys scroll or navigate according to the app.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 260)
            }
            Text("Schematic layout • Click a position, then Learn to confirm it. Lit buttons show live input.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(mapper.permissionStatus).font(.caption).textSelection(.enabled)
                Button("Grant permission…") { mapper.requestPermission() }
            }
            HStack {
                Button(mapper.testPending ? "Switch to TextEdit now…" : "Test I key in 3 seconds") { mapper.scheduleTest() }.disabled(mapper.testPending || !mapper.enabled)
                Text(mapper.outputStatus).font(.caption).textSelection(.enabled)
            }
            Text(mapper.message).font(.callout).foregroundStyle(mapper.enabled ? Color.green : Color.secondary)
        }.padding(20).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
    func modifier(_ title: String, _ flag: CGEventFlags) -> some View {
        Toggle(title, isOn: Binding(get: { binding.modifiers & flag.rawValue != 0 }, set: { on in
            var value = binding
            if on { value.modifiers |= flag.rawValue } else { value.modifiers &= ~flag.rawValue }
            mapper.update(value)
        })).toggleStyle(.button)
    }
    func pod(left: Bool) -> some View {
        VStack {
            Text(left ? "LEFT POD" : "RIGHT POD").font(.caption.bold()).tracking(2)
            ZStack {
                RoundedRectangle(cornerRadius: 54).fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 54).stroke(Color.gray.opacity(0.35), lineWidth: 2))
                VStack(spacing: 12) {
                    button(left ? "up" : "y", title: left ? "↑" : "Y")
                    HStack(spacing: 22) {
                        button(left ? "left" : "z", title: left ? "←" : "Z")
                        button(left ? "right" : "a", title: left ? "→" : "A")
                    }
                    button(left ? "down" : "b", title: left ? "↓" : "B")
                    button(left ? "minus" : "plus", title: left ? "−" : "+", wide: true)
                }.padding(18)
            }.frame(width: 220, height: 290)
        }
    }
    func button(_ slot: String, title: String, wide: Bool = false) -> some View {
        let source = mapper.sources[slot] ?? slot
        let active = mapper.pressed.contains(source) || mapper.recentPresses.contains(source)
        let mapping = mapper.bindings[slot] ?? KeyBinding()
        return Button {
            mapper.cancelRecording(); mapper.learning = false; mapper.selected = slot
        } label: {
            VStack(spacing: 1) {
                Text(title).font(.title3.bold())
                Text(mapping.displayLabel).font(.system(size: 10))
            }.frame(width: wide ? 130 : 60, height: 48)
                .background(active ? Color.green.opacity(0.8) : mapper.selected == slot ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(mapper.selected == slot ? Color.accentColor : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityLabel("\(slot), \(mapping.label)")
    }
}
