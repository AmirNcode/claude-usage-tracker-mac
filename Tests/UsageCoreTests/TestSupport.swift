import Foundation

/// Minimal test harness: the CLT-only Swift toolchain on the build machine ships
/// neither XCTest nor Swift Testing, so tests are a plain executable that exits
/// non-zero on failure.
final class TestRunner {
    static let shared = TestRunner()
    private(set) var failureCount = 0
    private(set) var checkCount = 0
    private var currentTest = ""

    func run(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        do {
            try body()
        } catch {
            failureCount += 1
            print("FAIL [\(name)] threw: \(error)")
        }
    }

    func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        checkCount += 1
        if !condition {
            failureCount += 1
            let filename = URL(fileURLWithPath: file).lastPathComponent
            print("FAIL [\(currentTest)] \(filename):\(line) — \(message)")
        }
    }

    func finish() -> Never {
        if failureCount == 0 {
            print("OK — all \(checkCount) checks passed")
            exit(0)
        }
        print("FAILED — \(failureCount) failure(s) out of \(checkCount) checks")
        exit(1)
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    TestRunner.shared.run(name, body)
}

func expect(_ condition: Bool, _ message: String = "expectation failed", file: String = #file, line: Int = #line) {
    TestRunner.shared.expect(condition, message, file: file, line: line)
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #file, line: Int = #line) {
    TestRunner.shared.expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

func expectThrows(_ body: () throws -> Void, file: String = #file, line: Int = #line) {
    do {
        try body()
        TestRunner.shared.expect(false, "expected an error to be thrown", file: file, line: line)
    } catch {
        TestRunner.shared.expect(true, "", file: file, line: line)
    }
}
