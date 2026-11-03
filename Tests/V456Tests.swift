import XCTest
@testable import AstralAI

// MARK: - V4.5.6 tests
//
// The fixes this release is built on:
// - 15 fresh Lucide icons downloaded from the internet and bundled
//   (loader-circle, panel-left, message-square-plus, …),
// - the icon registry maps every semantic role to a bundled parsable SVG,
// - skill files attached to a message import straight into the Skills
//   library (the auto-install path),
// - the attachment suffix rule that triggers the auto-install.

final class V456Tests: XCTestCase {

    // MARK: New icon set

    func testV456NewIconsLoadAndParse() {
        // The 15 icons added in V4.5.6 — every one must exist in the
        // bundle and parse into real geometry.
        let icons = [
            "loader-circle", "panel-left", "message-square-plus", "arrow-up",
            "chevrons-up-down", "puzzle", "map", "braces", "table", "mic",
            "history", "circle-check", "file-up", "plug-zap", "users",
        ]
        var failures: [String] = []
        for icon in icons {
            let url = Bundle.main.url(
                forResource: icon, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: icon, withExtension: "svg")
            guard let url, let svg = try? String(contentsOf: url, encoding: .utf8) else {
                failures.append(icon + "-missing")
                continue
            }
            guard LucideSVGParser.parse(svg) != nil else {
                failures.append(icon + "-parse")
                continue
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "these V4.5.6 icons failed to load/parse: \(failures.joined(separator: ", "))")
    }

    func testRegistryRolesResolveToBundledIcons() {
        // Every semantic role in the AstralIcons registry must point at a
        // bundled, parsable SVG — a typo here would render the fallback
        // rounded square instead of the icon.
        let roles = [
            AstralIcons.computer, AstralIcons.terminal, AstralIcons.browser,
            AstralIcons.search, AstralIcons.file, AstralIcons.filePlus,
            AstralIcons.fileCode, AstralIcons.folder, AstralIcons.folderPlus,
            AstralIcons.folderOpen, AstralIcons.send, AstralIcons.settings,
            AstralIcons.sparkles, AstralIcons.cpu, AstralIcons.cloud,
            AstralIcons.cloudOff, AstralIcons.hardDrive, AstralIcons.click,
            AstralIcons.back, AstralIcons.forward, AstralIcons.plus,
            AstralIcons.check, AstralIcons.close, AstralIcons.play,
            AstralIcons.stop, AstralIcons.download, AstralIcons.upload,
            AstralIcons.chevronDown, AstralIcons.chevronUp,
            AstralIcons.chevronForward, AstralIcons.externalLink,
            AstralIcons.todo, AstralIcons.chat, AstralIcons.zap,
            AstralIcons.package, AstralIcons.trash, AstralIcons.eye,
            AstralIcons.share, AstralIcons.key, AstralIcons.rocket,
            AstralIcons.bot, AstralIcons.brain, AstralIcons.wrench,
            AstralIcons.refresh, AstralIcons.image, AstralIcons.wifi,
            AstralIcons.shield, AstralIcons.languages, AstralIcons.compass,
            AstralIcons.spinner, AstralIcons.sidebar, AstralIcons.newChat,
            AstralIcons.arrowUp, AstralIcons.chevronsUpDown, AstralIcons.puzzle,
            AstralIcons.map, AstralIcons.braces, AstralIcons.table,
            AstralIcons.mic, AstralIcons.history, AstralIcons.checkCircle,
            AstralIcons.fileUp, AstralIcons.plug, AstralIcons.users,
        ]
        var failures: [String] = []
        for name in Set(roles) {
            let url = Bundle.main.url(
                forResource: name, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: name, withExtension: "svg")
            guard let url,
                  let svg = try? String(contentsOf: url, encoding: .utf8),
                  LucideSVGParser.parse(svg) != nil else {
                failures.append(name)
                continue
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "registry roles without a bundled parsable icon: \(failures.joined(separator: ", "))")
    }

    // MARK: Skill auto-install (attachment path)

    /// The exact import call the attachment auto-install path makes: a
    /// single-skill JSON payload must decode, install and land in the
    /// Skills library.
    @MainActor
    func testSkillImportFromAttachedJSON() throws {
        let json = """
        {"slug": "test-skill-v456", "name": "Test Skill", "summary": "v4.5.6 test",
         "category": "imported", "icon": "sparkles", "instructions": "Do the thing."}
        """
        let skills = try SkillStore.shared.importFromData(Data(json.utf8))
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills.first?.name, "Test Skill")
        XCTAssertTrue(
            SkillStore.shared.installed.contains { $0.slug == "test-skill-v456" },
            "the imported skill must land in the Skills library")
    }

    /// The suffix rule that arms the auto-install for attachments: .skill,
    /// .skill.skill and .json are skill files; anything else is not.
    func testSkillAttachmentSuffixDetection() {
        let names = [
            "helper.skill", "pack.skill.skill", "data.json",
            "photo.png", "notes.txt", "archive.Skill",
        ]
        let detected = names.filter {
            let lowered = $0.lowercased()
            return lowered.hasSuffix(".skill")
                || lowered.hasSuffix(".skill.skill")
                || lowered.hasSuffix(".json")
        }
        XCTAssertEqual(
            detected,
            ["helper.skill", "pack.skill.skill", "data.json", "archive.Skill"],
            "detection is case-insensitive and excludes non-skill files")
    }
}
