import AppKit

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) { precondition(actual == expected, "Expected \(expected), got \(actual)") }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertGreaterThan(_ actual: Int, _ expected: Int) { precondition(actual > expected) }

@main final class MapperTests {
    static func main() {
        let suite = MapperTests()
        defer { suite.tearDown() }
        suite.testPresetTapAndNoDuplicatePackets()
        suite.testDisconnectReleasesHeldKeysAndDisarms()
        suite.testSharedHeldKeyOnlyReleasesAfterBothButtons()
        suite.testLearningSwapsSources()
        suite.testDisabledAndBlockedContextDoNotEmit()
        suite.testFocusChangeReleasesHeldKeys()
        suite.testPersistenceAndPresetRetainsLearnedSources()
        suite.testRepeatStopsOnRelease()
        suite.testRapidPressesAreNotDropped()
        suite.testOldScrollMappingsBecomeRepeatingArrows()
        suite.testRepeatCancellation()
        suite.testArrowEventEncoding()
        suite.testRepeatUsesKeyDownsUntilRelease()
        print("Passed 13 mapper checks (fake keyboard event sink).")
    }
    private var suites: [String] = []
    private func testDefaults() -> UserDefaults {
        let name = "ClickMapperTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
    }
    private func mapper() -> Mapper {
        let model = Mapper(defaults: testDefaults(), outputContext: { true })
        model.preset()
        return model
    }
    func testPresetTapAndNoDuplicatePackets() {
        let model = mapper()
        var events: [String] = []
        model.emit = { code, down, _, _ in events.append("\(code):\(down)") }
        model.enabled = true
        model.receive(["plus"]); model.receive(["plus"]); model.receive([])
        XCTAssertEqual(events, ["34:true", "34:false"])
        model.receive(["minus"])
        XCTAssertEqual(Array(events.suffix(2)), ["40:true", "40:false"])
    }
    func testDisconnectReleasesHeldKeysAndDisarms() {
        let model = mapper()
        var events: [Bool] = []
        model.emit = { _, down, _, _ in events.append(down) }
        model.bindings["plus"]?.mode = "Hold"
        model.enabled = true; model.receive(["plus"])
        XCTAssertEqual(events, [true])
        model.disconnected()
        XCTAssertEqual(events, [true, false]); XCTAssertFalse(model.enabled)
        XCTAssertTrue(model.pressed.isEmpty)
    }
    func testSharedHeldKeyOnlyReleasesAfterBothButtons() {
        let model = mapper()
        var events: [Bool] = []
        model.emit = { _, down, _, _ in events.append(down) }
        let binding = KeyBinding(code: 34, label: "I", mode: "Hold", assigned: true)
        model.bindings["plus"] = binding; model.bindings["minus"] = binding
        model.enabled = true
        model.receive(["plus", "minus"]); model.receive(["minus"])
        XCTAssertEqual(events, [true])
        model.receive([]); XCTAssertEqual(events, [true, false])
    }
    func testLearningSwapsSources() {
        let model = mapper()
        model.selected = "plus"; model.learn(); model.receive(["minus"])
        XCTAssertEqual(model.sources["plus"], "minus")
        XCTAssertEqual(model.sources["minus"], "plus")
        XCTAssertFalse(model.learning); XCTAssertFalse(model.enabled)
    }
    func testDisabledAndBlockedContextDoNotEmit() {
        let model = mapper()
        var count = 0
        model.emit = { _, _, _, _ in count += 1 }
        model.receive(["plus"]); model.receive([])
        XCTAssertEqual(count, 0)
        let blocked = Mapper(defaults: testDefaults(), outputContext: { false })
        blocked.emit = { _, _, _, _ in count += 1 }
        blocked.enabled = true; blocked.receive(["plus"])
        XCTAssertEqual(count, 0)
    }
    func testFocusChangeReleasesHeldKeys() {
        let model = mapper()
        var events: [Bool] = []
        model.emit = { _, down, _, _ in events.append(down) }
        model.bindings["plus"]?.mode = "Hold"
        model.enabled = true; model.receive(["plus"])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(events, [true, false])
    }
    func testPersistenceAndPresetRetainsLearnedSources() {
        let defaults = testDefaults()
        let first = Mapper(defaults: defaults)
        first.selected = "plus"; first.learn(); first.receive(["minus"])
        first.update(KeyBinding(code: 49, label: "Space", modifiers: 1 << 20, mode: "Hold", assigned: true))
        let second = Mapper(defaults: defaults)
        XCTAssertEqual(second.bindings["plus"], first.bindings["plus"])
        XCTAssertEqual(second.sources["plus"], "minus")
        XCTAssertFalse(second.enabled)
        second.preset()
        XCTAssertEqual(second.sources["plus"], "minus")
        XCTAssertEqual(second.bindings["plus"]?.code, 34)
    }
    func testRepeatStopsOnRelease() {
        let model = mapper()
        var count = 0
        model.emit = { _, _, _, _ in count += 1 }
        model.bindings["plus"]?.mode = "Repeat"
        model.enabled = true; model.receive(["plus"])
        XCTAssertEqual(count, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.52))
        XCTAssertGreaterThan(count, 2)
        model.receive([])
        let afterRelease = count
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(count, afterRelease)
    }


    func testRapidPressesAreNotDropped() {
        let model = mapper()
        var events = 0
        model.emit = { _, _, _, _ in events += 1 }
        model.bindings["plus"]?.mode = "Repeat"
        model.enabled = true
        for _ in 0..<30 { model.receive(["plus"]); model.receive([]) }
        XCTAssertEqual(events, 60)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(events, 60)
    }
    func testOldScrollMappingsBecomeRepeatingArrows() {
        let defaults = testDefaults()
        let old = ["up": KeyBinding(code: 49, label: "Space", assigned: true, longPress: "Scroll up", scrollSpeed: 4)]
        defaults.set(try! JSONEncoder().encode(old), forKey: "bindings.v1")
        let model = Mapper(defaults: defaults, outputContext: { true })
        XCTAssertEqual(model.bindings["up"]?.code, 126)
        XCTAssertEqual(model.bindings["up"]?.mode, "Repeat")
        XCTAssertEqual(model.bindings["up"]?.longPress, nil)
    }
    func testRepeatCancellation() {
        for cancel in ["disable", "disconnect", "focus"] {
            let model = mapper()
            var count = 0
            model.emit = { _, _, _, _ in count += 1 }
            model.navigationPreset()
            model.enabled = true; model.receive(["up"])
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            XCTAssertGreaterThan(count, 3)
            switch cancel {
            case "disable": model.enabled = false
            case "disconnect": model.disconnected()
            default: NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            }
            let stopped = count
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            XCTAssertEqual(count, stopped)
        }
    }
    func testArrowEventEncoding() {
        for (code, character) in [(UInt16(123), UniChar(0xF702)), (124, 0xF703), (125, 0xF701), (126, 0xF700)] {
            let event = KeyboardEvents.make(code: code, down: true, modifiers: CGEventFlags.maskShift.rawValue, repeating: true)!
            XCTAssertTrue(event.flags.contains(.maskNumericPad))
            XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
            XCTAssertTrue(event.flags.contains(.maskShift))
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 1)
            var length = 0; var actual: UniChar = 0
            event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &length, unicodeString: &actual)
            XCTAssertEqual(length, 1); XCTAssertEqual(actual, character)
        }
    }
    func testRepeatUsesKeyDownsUntilRelease() {
        let model = mapper()
        var events: [String] = []
        model.emit = { _, down, _, repeating in events.append("\(down):\(repeating)") }
        model.navigationPreset(); model.enabled = true
        model.receive(["down"])
        XCTAssertEqual(events, ["true:false"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertGreaterThan(events.count, 2)
        XCTAssertTrue(events.dropFirst().allSatisfy { $0 == "true:true" })
        model.receive([])
        XCTAssertEqual(events.last, "false:false")
    }

}
