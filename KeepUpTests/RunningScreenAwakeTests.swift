import Testing
@testable import KeepUp

@MainActor struct RunningScreenAwakeTests {
    @Test func restoresOriginalTimerAfterPauseOrLeavingScreen() {
        var systemValue = false
        var writes: [Bool] = []
        let owner = RunningScreenAwake(read: { systemValue }, write: { systemValue = $0; writes.append($0) })
        owner.update(active: true)
        owner.update(active: true)
        #expect(systemValue)
        owner.update(active: false)
        owner.update(active: false)
        #expect(!systemValue)
        #expect(writes == [true, false])
    }

    @Test func preservesExistingTimerOverrideAndRecapturesOnNextAppearance() {
        var systemValue = true
        let owner = RunningScreenAwake(read: { systemValue }, write: { systemValue = $0 })
        owner.update(active: true)
        owner.update(active: false)
        #expect(systemValue)
        systemValue = false
        owner.update(active: true)
        owner.update(active: false)
        #expect(!systemValue)
    }
}
