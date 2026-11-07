import XCTest
@testable import AstralAI

// MARK: - astra-os sandbox tests

/// Exercises the astra-os work environment: shell semantics, path
/// resolution, redirection, grep, escaping protection and the HTML-to-text
/// converter. Runs against the real (app-sandboxed) filesystem roots.
@MainActor
final class SandboxShellTests: XCTestCase {

    private var shell: SandboxShell { SandboxShell.shared }

    override func setUp() async throws {
        // Fresh home for every test.
        _ = await shell.run("cd ~")
        _ = await shell.run("rm -rf SandboxTests")
    }

    // MARK: Shell basics

    func testTokenizeHonorsQuotes() {
        XCTAssertEqual(
            SandboxShell.tokenize("echo \"hello world\" 'a b'"),
            ["echo", "hello world", "a b"])
        XCTAssertEqual(
            SandboxShell.tokenize("grep -n pattern file.txt"),
            ["grep", "-n", "pattern", "file.txt"])
    }

    func testPwdStartsAtHome() async {
        let result = await shell.run("pwd")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, SandboxShell.homePath)
    }

    func testEchoWritesFileWithRedirection() async {
        let write = await shell.run("echo \"# Test\" > SandboxTests/notes.md")
        XCTAssertEqual(write.exitCode, 0)

        let read = await shell.run("cat SandboxTests/notes.md")
        XCTAssertEqual(read.exitCode, 0)
        XCTAssertEqual(read.stdout, "# Test")
    }

    func testAppendRedirectionAddsLine() async {
        _ = await shell.run("echo one > SandboxTests/log.txt")
        _ = await shell.run("echo two >> SandboxTests/log.txt")
        let read = await shell.run("cat SandboxTests/log.txt")
        XCTAssertEqual(read.stdout, "one\ntwo")
    }

    func testCdAndRelativePaths() async {
        _ = await shell.run("mkdir -p SandboxTests/inner")
        let cd = await shell.run("cd SandboxTests/inner")
        XCTAssertEqual(cd.exitCode, 0)
        let pwd = await shell.run("pwd")
        XCTAssertEqual(pwd.stdout, SandboxShell.homePath + "/SandboxTests/inner")
        _ = await shell.run("cd ~")
    }

    func testLsListsCreatedFiles() async {
        _ = await shell.run("mkdir -p SandboxTests/dir")
        _ = await shell.run("touch SandboxTests/dir/alpha.txt SandboxTests/dir/beta.txt")
        let ls = await shell.run("ls SandboxTests/dir")
        XCTAssertEqual(ls.exitCode, 0)
        XCTAssertTrue(ls.stdout.contains("alpha.txt"))
        XCTAssertTrue(ls.stdout.contains("beta.txt"))
    }

    func testGrepFindsLines() async {
        _ = await shell.run("echo apple > SandboxTests/fruits.txt")
        _ = await shell.run("echo banana >> SandboxTests/fruits.txt")
        _ = await shell.run("echo cherry >> SandboxTests/fruits.txt")
        let grep = await shell.run("grep an SandboxTests/fruits.txt")
        XCTAssertEqual(grep.exitCode, 0)
        XCTAssertTrue(grep.stdout.contains("banana"))
        XCTAssertFalse(grep.stdout.contains("cherry"))
    }

    func testWcCountsLines() async {
        _ = await shell.run("echo a > SandboxTests/three.txt")
        _ = await shell.run("echo b >> SandboxTests/three.txt")
        _ = await shell.run("echo c >> SandboxTests/three.txt")
        let wc = await shell.run("wc -l SandboxTests/three.txt")
        XCTAssertEqual(wc.stdout.trimmingCharacters(in: .whitespaces), "3")
    }

    func testHeadAndTail() async {
        _ = await shell.run("echo 1 > SandboxTests/nums.txt")
        _ = await shell.run("echo 2 >> SandboxTests/nums.txt")
        _ = await shell.run("echo 3 >> SandboxTests/nums.txt")
        _ = await shell.run("echo 4 >> SandboxTests/nums.txt")
        _ = await shell.run("echo 5 >> SandboxTests/nums.txt")
        let head = await shell.run("head -n 2 SandboxTests/nums.txt")
        XCTAssertEqual(head.stdout, "1\n2")
        let tail = await shell.run("tail -n 2 SandboxTests/nums.txt")
        XCTAssertEqual(tail.stdout, "4\n5")
    }

    func testMvRenames() async {
        _ = await shell.run("echo data > SandboxTests/old.txt")
        let mv = await shell.run("mv SandboxTests/old.txt SandboxTests/new.txt")
        XCTAssertEqual(mv.exitCode, 0)
        let read = await shell.run("cat SandboxTests/new.txt")
        XCTAssertEqual(read.stdout, "data")
        let missing = await shell.run("cat SandboxTests/old.txt")
        XCTAssertNotEqual(missing.exitCode, 0)
    }

    func testSedReplacesPattern() async {
        _ = await shell.run("echo \"hello world\" > SandboxTests/greet.txt")
        let sed = await shell.run("sed s/world/astra/ SandboxTests/greet.txt")
        XCTAssertEqual(sed.exitCode, 0)
        XCTAssertTrue(sed.stdout.contains("hello astra"))
    }

    // MARK: Security

    func testParentTraversalIsBlocked() async {
        let escape = await shell.run("cat ../../../../etc/passwd")
        XCTAssertNotEqual(escape.exitCode, 0)
        let escape2 = await shell.run("ls /private/etc")
        XCTAssertNotEqual(escape2.exitCode, 0)
        let escape3 = await shell.run("cd ../..")
        XCTAssertNotEqual(escape3.exitCode, 0)
        // The shell is still at home after the failed escapes.
        let pwd = await shell.run("pwd")
        XCTAssertEqual(pwd.stdout, SandboxShell.homePath)
    }

    // MARK: Output shaping

    func testCappedOutputMarksTruncation() {
        let long = String(repeating: "x", count: 500)
        let capped = SandboxShell.capped(long, limit: 100)
        XCTAssertTrue(capped.contains("truncated"))
        XCTAssertLessThanOrEqual(capped.count, 140)
    }

    func testBodyTextStripsHTML() {
        let html = """
        <html><head><style>body{color:red}</style></head>
        <body><nav>menu</nav><h1>Title</h1><p>First &amp; paragraph</p>
        <script>alert(1)</script></body></html>
        """
        let text = SandboxShell.bodyText(
            from: Data(html.utf8),
            url: URL(string: "https://example.com")!)
        XCTAssertFalse(text.contains("<"))
        XCTAssertFalse(text.contains("alert"))
        XCTAssertFalse(text.contains("color:red"))
        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("First & paragraph"))
    }

    func testUnknownCommandFailsWithHint() async {
        let result = await shell.run("frobnicate --now")
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("command not found"))
    }

    func testHelpListsCommandGroups() async {
        let result = await shell.run("help")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("curl"))
        XCTAssertTrue(result.stdout.contains("grep"))
        XCTAssertTrue(result.stdout.contains("search"))
    }
}
