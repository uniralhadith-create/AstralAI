import XCTest
@testable import AstralAI

// MARK: - V8.0.0 Ubuntu Base 24.04 LTS & TextToolProtocol Fault-Tolerance Tests

@MainActor
final class V500Tests: XCTestCase {

    private var shell: SandboxShell!

    override func setUp() async throws {
        shell = SandboxShell.shared
        _ = await shell.run("cd ~")
        _ = await shell.run("rm -rf V500Tests")
        _ = await shell.run("mkdir -p V500Tests")
    }

    // MARK: - Ubuntu Base 24.04.2 LTS (Noble Numbat · ARM64) Inspection

    func testUbuntuBaseEtcAndProcFilesExist() async {
        let osRelease = await shell.run("cat /etc/os-release")
        XCTAssertEqual(osRelease.exitCode, 0)
        XCTAssertTrue(osRelease.stdout.contains("Ubuntu 24.04.2 LTS"))

        let lsb = await shell.run("lsb_release -a")
        XCTAssertEqual(lsb.exitCode, 0)
        XCTAssertTrue(lsb.stdout.contains("noble"))

        let dpkg = await shell.run("dpkg --print-architecture")
        XCTAssertEqual(dpkg.exitCode, 0)
        XCTAssertEqual(dpkg.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "arm64")

        let neofetch = await shell.run("neofetch")
        XCTAssertEqual(neofetch.exitCode, 0)
        XCTAssertTrue(neofetch.stdout.contains("Ubuntu 24.04.2 LTS"))
    }

    // MARK: - Fault-Tolerant ASTRAL_TOOL & Thinking Stripping (Kimi K2.5 Fix)

    func testMalformedAstralToolWithUnescapedInnerQuotesIsRecoveredAndStripped() {
        let kimiLine = #"ASTRAL_TOOL {"name": "web_search", "arguments": {"max_results":10,"query":""سيرة لسان الذهب" сайт"}}"#
        let calls = TextToolProtocol.parseCalls(in: kimiLine)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "web_search")

        let cleaned = TextToolProtocol.cleanVisibleText(kimiLine)
        XCTAssertTrue(cleaned.isEmpty, "Raw ASTRAL_TOOL line must never appear in visible chat text")
    }

    func testThinkingBlocksExtractedAndStrippedFromVisibleText() {
        let raw = "<think>Searching for Tariq El-Fares...</think>\nASTRAL_TOOL {\"name\": \"web_search\", \"arguments\": {\"query\": \"Tariq\"}}\nالإجابة النهائية هنا."
        let thoughts = TextToolProtocol.extractThinkingBlocks(in: raw)
        XCTAssertEqual(thoughts, ["Searching for Tariq El-Fares..."])

        let cleaned = TextToolProtocol.cleanVisibleText(raw)
        XCTAssertEqual(cleaned, "الإجابة النهائية هنا.")
    }

    // MARK: - Environment Variables, SQLite3, Math & Git

    func testExportAndVariableExpansion() async {
        _ = await shell.run("export GREETING=Marhaba_Astral")
        let echoed = await shell.run("echo $GREETING")
        XCTAssertEqual(echoed.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Marhaba_Astral")
    }

    func testSqlite3CreatesTableAndQueriesRows() async {
        let create = await shell.run("sqlite3 V500Tests/test.db \"CREATE TABLE items (id INT, title TEXT); INSERT INTO items VALUES (1, 'Astral AI'); SELECT id, title FROM items;\"")
        XCTAssertEqual(create.exitCode, 0)
        XCTAssertEqual(create.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "1|Astral AI")
    }

    func testBcEvaluatesArithmeticExpression() async {
        let res = await shell.run("echo '6 * 7' | bc")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "42")
    }

    func testSudoTransparentExecution() async {
        let res = await shell.run("sudo apt install htop && which htop")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertTrue(res.stdout.contains("/usr/bin/htop"))
    }
}
