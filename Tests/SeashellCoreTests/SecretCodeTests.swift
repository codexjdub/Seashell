import Foundation
import Testing
@testable import SeashellCore

struct SecretCodeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Types `keys` a quarter of a second apart (or `spacing`), beginning `from`
    /// seconds in, and says whether the last one completed the code.
    private func typing(_ keys: String, spacing: TimeInterval = 0.25, from: TimeInterval = 0,
                        into code: inout SecretCode) -> Bool {
        var completed = false
        for (index, key) in keys.enumerated() {
            completed = code.type(key, at: start.addingTimeInterval(from + Double(index) * spacing))
        }
        return completed
    }

    @Test func oneOneOneReturnOpensIt() {
        var code = SecretCode("111\r")
        let opened = typing("111\r", into: &code)
        #expect(opened)
    }

    @Test func onlyTheExactCode() {
        for keys in ["11\r", "1121\r", "111", "111 \r", "211\r1"] {
            var code = SecretCode("111\r")
            let opened = typing(keys, into: &code)
            #expect(!opened, "\(keys.debugDescription)")
        }
    }

    @Test func extraKeysBeforeItDontMatter() {
        var code = SecretCode("111\r")
        let opened = typing("ab11111\r", into: &code)
        #expect(opened)
    }

    @Test func tooSlowStartsOver() {
        var code = SecretCode("111\r", gap: 2)
        let slow = typing("111\r", spacing: 2.5, into: &code)
        #expect(!slow)
        let quickEnough = typing("111\r", spacing: 1.9, from: 20, into: &code)
        #expect(quickEnough, "after a long pause it starts over, and a code typed in time still works")
    }

    @Test func itCanBeTypedAgain() {
        var code = SecretCode("111\r")
        let first = typing("111\r", into: &code)
        let returnAgain = code.type("\r", at: start.addingTimeInterval(1.1))
        let second = typing("111\r", from: 2, into: &code)
        #expect(first)
        #expect(!returnAgain, "Return alone right after doesn't count again")
        #expect(second)
    }

    @Test func knowsWhichKeysAreInTheCode() {
        let code = SecretCode("111\r")
        #expect(code.isPart("1") && code.isPart("\r"))
        #expect(!code.isPart("2") && !code.isPart("a"))
    }
}
