import XCTest
@testable import AstralAI

// MARK: - V4.7.0 tests
//
// The upgrades this release is built on:
// - astra-os is a FULL shell now: pipes (cmd | cmd), chaining (cmd && cmd;
//   cmd) with real exit-code semantics, stdin threading, and 16 new
//   commands (sort, uniq, cut, tr, rev, diff, seq, base64, md5sum,
//   shasum, df, env, which, basename, dirname, chmod, sleep),
// - the Action Button never opens the app: QuickTaskIntent answers
//   in-place and the exchange syncs back through the shared inbox,
// - the cloud computer auto-escalates permission failures with sudo and
//   gains cloud_file_push (the two-machine mirror is complete).

@MainActor
final class V470Tests: XCTestCase {

    private var shell: SandboxShell!

    override func setUp() async throws {
        shell = SandboxShell.shared
        _ = await shell.run("cd ~")
        _ = await shell.run("rm -rf V470Tests")
        _ = await shell.run("mkdir -p V470Tests")
    }

    // MARK: - Pipes

    func testPipeGrepsSortsAndUniqs() async {
        _ = await shell.run("echo cherry > V470Tests/fruits.txt")
        _ = await shell.run("echo apple >> V470Tests/fruits.txt")
        _ = await shell.run("echo cherry >> V470Tests/fruits.txt")
        _ = await shell.run("echo apple >> V470Tests/fruits.txt")

        let piped = await shell.run("cat V470Tests/fruits.txt | sort | uniq -c")
        let lines = piped.stdout.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(piped.exitCode, 0)
        XCTAssertTrue(lines.contains { $0.hasSuffix("2 apple") }, "uniq -c must count apple twice: \(lines)")
        XCTAssertTrue(lines.contains { $0.hasSuffix("2 cherry") }, "uniq -c must count cherry twice: \(lines)")
    }

    func testPipeHeadLimitsLines() async {
        let result = await shell.run("seq 1 20 | head -3")
        XCTAssertEqual(
            result.stdout.split(separator: "\n").map(String.init),
            ["1", "2", "3"])
    }

    func testPipeWritesThroughRedirect() async {
        let piped = await shell.run("seq 1 5 | sort -r > V470Tests/desc.txt")
        XCTAssertEqual(piped.exitCode, 0)
        let read = await shell.run("cat V470Tests/desc.txt")
        XCTAssertEqual(
            read.stdout.split(separator: "\n").map(String.init),
            ["5", "4", "3", "2", "1"])
    }

    // MARK: - Chaining

    func testAndChainRunsOnSuccess() async {
        _ = await shell.run("rm -f V470Tests/chain.txt")
        let chained = await shell.run("echo hi > V470Tests/chain.txt && cat V470Tests/chain.txt")
        XCTAssertEqual(chained.exitCode, 0)
        XCTAssertEqual(chained.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hi")
    }

    func testAndChainSkipsAfterFailure() async {
        _ = await shell.run("rm -f V470Tests/skipped.txt")
        // cat on a missing file fails → the && chain stops → nothing written.
        let chained = await shell.run("cat V470Tests/definitely-missing.txt && echo wrote > V470Tests/skipped.txt")
        XCTAssertNotEqual(chained.exitCode, 0)
        let check = await shell.run("ls V470Tests/skipped.txt")
        XCTAssertNotEqual(check.exitCode, 0, "the failed && chain must not run the second command")
    }

    func testSemicolonChainContinuesAfterFailure() async {
        _ = await shell.run("rm -f V470Tests/after.txt")
        let chained = await shell.run("cat V470Tests/definitely-missing.txt; echo done > V470Tests/after.txt")
        let check = await shell.run("cat V470Tests/after.txt")
        XCTAssertEqual(check.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "done")
        _ = chained
    }

    // MARK: - New text tools

    func testTrUppercasesPipedText() async {
        let result = await shell.run("echo hello | tr a-z A-Z")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "HELLO")
    }

    func testCutSelectsFields() async {
        _ = await shell.run("echo \"name,age\" > V470Tests/row.csv")
        let result = await shell.run("cat V470Tests/row.csv | cut -d, -f1")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "name")
    }

    func testRevReversesLines() async {
        let result = await shell.run("echo abc | rev")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "cba")
    }

    func testBase64RoundTrip() async {
        let encoded = await shell.run("echo astral | base64")
        XCTAssertEqual(encoded.exitCode, 0)
        let cleaned = encoded.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = await shell.run("echo \(cleaned) | base64 -d")
        XCTAssertEqual(
            decoded.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "astral")
    }

    func testMd5SumIsStable() async {
        _ = await shell.run("echo hello > V470Tests/hash.txt")
        let first = await shell.run("md5sum V470Tests/hash.txt")
        let second = await shell.run("md5sum V470Tests/hash.txt")
        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(first.stdout, second.stdout)
        XCTAssertTrue(first.stdout.contains("  V470Tests/hash.txt"))
    }

    func testDiffDetectsDifference() async {
        _ = await shell.run("echo one > V470Tests/a.txt")
        _ = await shell.run("echo two > V470Tests/b.txt")
        let diff = await shell.run("diff V470Tests/a.txt V470Tests/b.txt")
        // Real diff semantics: exit 1 when the files differ (so && chains
        // work), with the classic < / > markers in the output.
        XCTAssertEqual(diff.exitCode, 1)
        XCTAssertTrue(diff.stdout.contains("< one"))
        XCTAssertTrue(diff.stdout.contains("> two"))

        let same = await shell.run("diff V470Tests/a.txt V470Tests/a.txt")
        XCTAssertEqual(same.exitCode, 0)
        XCTAssertEqual(same.stdout, "")
    }

    func testSeqRange() async {
        let result = await shell.run("seq 2 4")
        XCTAssertEqual(
            result.stdout.split(separator: "\n").map(String.init),
            ["2", "3", "4"])
    }

    // MARK: - Classic behaviors kept intact

    func testGrepOnFileStillWorks() async {
        _ = await shell.run("echo alpha > V470Tests/words.txt")
        _ = await shell.run("echo beta >> V470Tests/words.txt")
        let grep = await shell.run("grep alp V470Tests/words.txt")
        XCTAssertEqual(grep.exitCode, 0)
        XCTAssertEqual(grep.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "alpha")
    }

    // MARK: - Quick exchange inbox (the no-open Action Button bridge)

    func testQuickExchangeCodableRoundTrip() throws {
        let exchange = QuickExchange(
            question: "ما الطقس اليوم؟",
            answer: "الجو مشمس ☀️",
            date: Date())
        let data = try JSONEncoder().encode(exchange)
        let decoded = try JSONDecoder().decode(QuickExchange.self, from: data)
        XCTAssertEqual(decoded.question, exchange.question)
        XCTAssertEqual(decoded.answer, exchange.answer)
    }

    func testQuickInboxWritesConsumableFiles() {
        SharedAppGroup.ensureInboxExists()
        let before = (try? FileManager.default.contentsOfDirectory(
            at: SharedAppGroup.inboxURL, includingPropertiesForKeys: nil))?.count ?? 0

        QuickInbox.queuePendingTask("V470 pending probe")
        QuickInbox.queueCompletedExchange(
            question: "V470 question",
            answer: "V470 answer")

        let after = (try? FileManager.default.contentsOfDirectory(
            at: SharedAppGroup.inboxURL, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(after.count, before + 2, "both inbox markers must land")

        let meta = after.first { $0.pathExtension == "astralmeta" }
        let quick = after.first { $0.pathExtension == "astralquick" }
        XCTAssertNotNil(meta)
        XCTAssertNotNil(quick)

        if let meta,
           let text = try? String(contentsOf: meta, encoding: .utf8) {
            XCTAssertEqual(text, "V470 pending probe")
        }
        if let quick,
           let decoded = try? JSONDecoder().decode(
            QuickExchange.self, from: Data(contentsOf: quick)) {
            XCTAssertEqual(decoded.question, "V470 question")
            XCTAssertEqual(decoded.answer, "V470 answer")
        }

        // Clean up so the real app never sees the probes.
        try? FileManager.default.removeItem(at: meta!)
        try? FileManager.default.removeItem(at: quick!)
    }

    // MARK: - Sudo escalation detection

    func testPermissionFailureDetection() {
        // The exact strings Ubuntu tools print when root is required.
        XCTAssertTrue(E2BComputer.looksLikePermissionFailure(
            "mkdir: cannot create directory '/opt/app': Permission denied"))
        XCTAssertTrue(E2BComputer.looksLikePermissionFailure(
            "touch: cannot touch '/etc/hosts': Permission denied"))
        XCTAssertTrue(E2BComputer.looksLikePermissionFailure(
            "E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)"))
        XCTAssertFalse(E2BComputer.looksLikePermissionFailure(
            "bash: foo: command not found"))
        XCTAssertFalse(E2BComputer.looksLikePermissionFailure(""))
    }

    // MARK: - Session import (the completed-exchange history sync)

    func testImportCompletedExchangeAppendsPair() {
        let session = AgentSession(
            llm: V470StubLLM(),
            toolRegistry: ToolRegistry(browser: nil, workspace: V470StubWorkspace(), system: nil),
            system: nil)
        XCTAssertTrue(session.messages.isEmpty)
        session.importCompletedExchange(question: "سؤال سريع", answer: "إجابة سريعة")
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages.first?.role, .user)
        XCTAssertEqual(session.messages.first?.content, "سؤال سريع")
        XCTAssertEqual(session.messages.last?.role, .assistant)
        XCTAssertEqual(session.messages.last?.content, "إجابة سريعة")
    }
}

// MARK: - Test doubles (V4.7.0)

/// Minimal LLMProviding stub — answers nothing, records nothing; the
/// V4.7.0 session tests never run a turn. (Deliberately NOT MainActor:
/// the protocol's async requirements are nonisolated.)
private final class V470StubLLM: LLMProviding {
    func streamChat(
        messages: [ChatMessage],
        tools: [ToolSpec]?,
        model: String?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(messages: [ChatMessage], model: String?) async throws -> String { "" }

    func structured<T: Decodable>(
        messages: [ChatMessage],
        type: T.Type,
        model: String?
    ) async throws -> T {
        throw LLMError.badResponse("stub")
    }
}

@MainActor
private final class V470StubWorkspace: WorkspaceRouting {
    var rootURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    func write(path: String, content: String) throws -> URL { rootURL }
    func writeData(path: String, data: Data) throws -> URL { rootURL }
    func createFolder(path: String) throws -> URL { rootURL }
    func read(path: String) throws -> String { "" }
    func list() -> [WorkspaceFile] { [] }
    func delete(path: String) throws {}
    func zip(paths: [String], archiveName: String) throws -> URL { rootURL }
    func url(for path: String) -> URL? { nil }
}
