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
        print("Passed 8 mapper checks (fake keyboard event sink).")
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
        Mapper(defaults: testDefaults(), outputContext: { true })
    }
    func testPresetTapAndNoDuplicatePackets() {
        let model = mapper()
        var events: [String] = []
        model.emit = { code, down, _ in events.append("\(code):\(down)") }
        model.enabled = true
        model.receive(["plus"]); model.receive(["plus"]); model.receive([])
        XCTAssertEqual(events, ["34:true", "34:false"])
        model.receive(["minus"])
        XCTAssertEqual(Array(events.suffix(2)), ["40:true", "40:false"])
    }
    func testDisconnectReleasesHeldKeysAndDisarms() {
        let model = mapper()
        var events: [Bool] = []
        model.emit = { _, down, _ in events.append(down) }
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
        model.emit = { _, down, _ in events.append(down) }
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
        model.emit = { _, _, _ in count += 1 }
        model.receive(["plus"]); model.receive([])
        XCTAssertEqual(count, 0)
        let blocked = Mapper(defaults: testDefaults(), outputContext: { false })
        blocked.emit = { _, _, _ in count += 1 }
        blocked.enabled = true; blocked.receive(["plus"])
        XCTAssertEqual(count, 0)
    }
    func testFocusChangeReleasesHeldKeys() {
        let model = mapper()
        var events: [Bool] = []
        model.emit = { _, down, _ in events.append(down) }
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
        model.emit = { _, _, _ in count += 1 }
        model.bindings["plus"]?.mode = "Repeat"
        model.enabled = true; model.receive(["plus"])
        XCTAssertEqual(count, 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.52))
        XCTAssertGreaterThan(count, 2)
        model.receive([])
        let afterRelease = count
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(count, afterRelease)
    }

}
