import XCTest
@testable import AstralAI

// MARK: - V5.0.0 Tests
//
// Validates the V5.0.0 upgrades:
// - astra-os 5.0.0 Linux FHS (/etc/os-release, /etc/hostname, /proc/version,
//   /proc/cpuinfo, /proc/meminfo)
// - Advanced Linux commands: jq, awk, xargs, tee, export/$VAR, || fallback,
//   sudo unwrap, git init/status/commit/log, apt install/list, neofetch,
//   ps aux, free, lscpu
// - Markdown V5 task list checkboxes, callouts, and inline parsing
// - Custom AstralComputerIcon and V5 Liquid Glass shimmer

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
        XCTAssertTrue(osRelease.stdout.contains("5.0.0"))

        let procVersion = await shell.run("cat /proc/version")
        XCTAssertEqual(procVersion.exitCode, 0)
        XCTAssertTrue(procVersion.stdout.contains("Linux version 6.12"))

        let neofetch = await shell.run("neofetch")
        XCTAssertEqual(neofetch.exitCode, 0)
        XCTAssertTrue(neofetch.stdout.contains("Astra-OS GNU/Linux 5.0.0"))
    }

    // MARK: - Environment Variables & Logical OR (`||`)

    func testExportAndVariableExpansion() async {
        _ = await shell.run("export GREETING=Marhaba_V5")
        let echoed = await shell.run("echo $GREETING")
        XCTAssertEqual(echoed.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Marhaba_V5")
    }

    func testLogicalOrFallbackRunsOnFailure() async {
        let res = await shell.run("cat V500Tests/nonexistent.txt || echo recovered")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "recovered")
    }

    // MARK: - Advanced Text & JSON Tools (`jq`, `awk`, `tee`, `xargs`)

    func testJqExtractsJSONField() async {
        let res = await shell.run("echo '{\"version\":\"5.0.0\",\"agent\":\"Astral\"}' | jq -r .version")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "5.0.0")
    }

    func testAwkPrintsColumns() async {
        let res = await shell.run("echo 'alpha beta gamma' | awk '{print $1, $3}'")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "alpha gamma")
    }

    func testTeeWritesFileAndPassesStdout() async {
        let res = await shell.run("echo v5_pipeline | tee V500Tests/tee.txt | tr a-z A-Z")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertEqual(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "V5_PIPELINE")
        let saved = await shell.run("cat V500Tests/tee.txt")
        XCTAssertEqual(saved.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "v5_pipeline")
    }

    // MARK: - Git & Apt

    func testGitInitCommitAndLog() async {
        _ = await shell.run("cd V500Tests && git init && echo 'hello' > app.py && git add . && git commit -m 'Initial V5 commit'")
        let log = await shell.run("git log")
        XCTAssertEqual(log.exitCode, 0)
        XCTAssertTrue(log.stdout.contains("Initial V5 commit"))
        _ = await shell.run("cd ~")
    }

    func testSudoTransparentExecution() async {
        let res = await shell.run("sudo apt install htop && which htop")
        XCTAssertEqual(res.exitCode, 0)
        XCTAssertTrue(res.stdout.contains("/usr/bin/htop"))
    }
}
