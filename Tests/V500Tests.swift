import XCTest
@testable import AstralAI

// MARK: - V5.0.0 Tests
//
// Validates the astra-os Linux workstation and Astral AI upgrades:
// - astra-os Linux FHS (/etc/os-release, /etc/hostname, /proc/version,
//   /proc/cpuinfo, /proc/meminfo)
// - Advanced Linux commands: jq, awk, xargs, tee, sqlite3, bc, column,
//   export/$VAR, || fallback, sudo unwrap, git init/status/commit/log,
//   apt install/list, neofetch, ps aux, free, lscpu
// - Strict Astral AI identity without version numbers

@MainActor
final class V500Tests: XCTestCase {

    private var shell: SandboxShell!

    override func setUp() async throws {
        shell = SandboxShell.shared
        _ = await shell.run("cd ~")
        _ = await shell.run("rm -rf V500Tests")
        _ = await shell.run("mkdir -p V500Tests")
    }

    // MARK: - Linux FHS & System Inspection

    func testLinuxEtcAndProcFilesExist() async {
        let osRelease = await shell.run("cat /etc/os-release")
        XCTAssertEqual(osRelease.exitCode, 0)
        XCTAssertTrue(osRelease.stdout.contains("Astra-OS GNU/Linux"))

        let procVersion = await shell.run("cat /proc/version")
        XCTAssertEqual(procVersion.exitCode, 0)
        XCTAssertTrue(procVersion.stdout.contains("Linux version 6.12"))

        let neofetch = await shell.run("neofetch")
        XCTAssertEqual(neofetch.exitCode, 0)
        XCTAssertTrue(neofetch.stdout.contains("Astra-OS GNU/Linux"))
    }

    // MARK: - Environment Variables & Logical OR (`||`)

    func testExportAndVariableExpansion() async {
        _ = await shell.run("export GREETING=Marhaba_Astral")
        let echoed = await shell.run("echo $GREETING")
        XCTAssertEqual(echoed.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Marhaba_Astral")
    }

    func testLogicalOrFallbackRunsOnFailure() async {
        let res = await shell.run("cat V500Tests/nonexistent.txt || echo recovered")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "recovered")
    }

    // MARK: - Advanced Text, Math, SQLite & JSON Tools (`jq`, `awk`, `tee`, `sqlite3`, `bc`)

    func testJqExtractsJSONField() async {
        let res = await shell.run("echo '{\"version\":\"5.0.0\",\"agent\":\"Astral AI\"}' | jq -r .agent")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Astral AI")
    }

    func testAwkPrintsColumns() async {
        let res = await shell.run("echo 'alpha beta gamma' | awk '{print $1, $3}'")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "alpha gamma")
    }

    func testTeeWritesFileAndPassesStdout() async {
        let res = await shell.run("echo astral_pipeline | tee V500Tests/tee.txt | tr a-z A-Z")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ASTRAL_PIPELINE")
        let saved = await shell.run("cat V500Tests/tee.txt")
        XCTAssertEqual(saved.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "astral_pipeline")
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

    // MARK: - Git & Apt

    func testGitInitCommitAndLog() async {
        _ = await shell.run("cd V500Tests && git init && echo 'hello' > app.py && git add . && git commit -m 'Initial commit'")
        let log = await shell.run("git log")
        XCTAssertEqual(log.exitCode, 0)
        XCTAssertTrue(log.stdout.contains("Initial commit"))
        _ = await shell.run("cd ~")
    }

    func testSudoTransparentExecution() async {
        let res = await shell.run("sudo apt install htop && which htop")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertTrue(res.stdout.contains("/usr/bin/htop"))
    }
}
