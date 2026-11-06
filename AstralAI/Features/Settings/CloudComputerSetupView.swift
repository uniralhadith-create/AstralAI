import SwiftUI

// MARK: - Cloud & Local Linux Alpha Computer Setup

/// The computer control room: switch the whole app between the on-device
/// astra-os Linux Alpha workstation (`install-alpha-minimal-20260426T153103Z.iso`,
/// Kernel `6.18.52-gentoo-alpha`) and the REAL Ubuntu cloud computer (E2B),
/// inspect/extract the Linux Alpha kernel & SquashFS rootfs, enter an API key,
/// and live-test the boot.
struct CloudComputerSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var mode = ComputerModeController.shared
    @ObservedObject private var cloud = E2BComputer.shared
    @ObservedObject private var alpha = AlphaLinuxSubsystem.shared

    @State private var keyText = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testFailed = false
    @State private var probingISO = false
    @State private var alphaActionMessage: String?

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AstralTheme.Spacings.m) {
                computerModeSection
                alphaLinuxKernelSection
                apiKeySection
                testSection
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.vertical, AstralTheme.Spacings.m)
        }
        .background(AstralTheme.background.ignoresSafeArea())
        .navigationTitle(L("settings.cloudComputer", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                GlassBackButton {
                    dismiss()
                }
            }
        }
        .onAppear {
            keyText = cloud.usesCustomKey
                ? (cloud.apiKey ?? "")
                : ""
        }
    }

    // MARK: Mode switch

    private var computerModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AstralTheme.orbGreen.opacity(0.14))
                        .frame(width: 38, height: 38)
                    AstralComputerIcon(
                        size: 20,
                        color: AstralTheme.textPrimary,
                        accentColor: AstralTheme.orbGreen,
                        isActive: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.modeTitle", "Settings"))
                        .font(AstralTheme.headline(16))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text(L("settings.modeIntro", "Settings"))
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                modeCard(
                    title: L("settings.modeLocal", "Settings"),
                    caption: "astra-os · Linux Alpha",
                    icon: AstralIcons.cpu,
                    selected: mode.mode == .local) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            mode.mode = .local
                        }
                    }

                modeCard(
                    title: L("settings.modeCloud", "Settings"),
                    caption: "Ubuntu · E2B Root",
                    icon: AstralIcons.cloud,
                    selected: mode.mode == .cloud) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            mode.mode = .cloud
                        }
                    }
            }

            Text(L("settings.modeFooter", "Settings"))
                .font(AstralTheme.body(11.5))
                .foregroundStyle(AstralTheme.moonDust)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: Linux Alpha Kernel & ISO-9660 RootFS Control Card

    private var alphaLinuxKernelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AIcon(
                    AstralIcons.terminal,
                    size: 16,
                    strokeWidth: 2.1,
                    color: AstralTheme.orbGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linux Alpha Kernel & SquashFS RootFS")
                        .font(AstralTheme.headline(14.5))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text("\(AlphaLinuxSubsystem.isoFileName) · 252.7 MiB")
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                kernelDetailRow(label: "Kernel", value: "\(AlphaLinuxSubsystem.kernelRelease) (\(alpha.activeKernelImage))")
                kernelDetailRow(label: "Bootloader", value: "SRM \(AlphaLinuxSubsystem.srmFirmwareVersion) · aboot \(AlphaLinuxSubsystem.abootVersion)")
                kernelDetailRow(label: "RootFS", value: "/mnt/cdrom/image.squashfs (OverlayFS /)")
                kernelDetailRow(label: "Drive ID", value: AlphaLinuxSubsystem.driveFileID)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AstralTheme.actionFill.opacity(0.04)))

            // SRM aboot kernel slot switcher
            HStack(spacing: 8) {
                Button {
                    _ = AlphaLinuxSubsystem.shared.runAboot(["boot", "0"])
                    alphaActionMessage = "Switched to Slot 0: /boot/gentoo (LSA EV56+ SMP)"
                } label: {
                    Text("Slot 0: gentoo (LSA)")
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(alpha.activeBootSlot < 3 ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .liquidGlass(
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                            tint: alpha.activeBootSlot < 3 ? AstralTheme.orbGreen.opacity(0.16) : .clear,
                            interactive: true)
                }
                .buttonStyle(.plain)

                Button {
                    _ = AlphaLinuxSubsystem.shared.runAboot(["boot", "3"])
                    alphaActionMessage = "Switched to Slot 3: /boot/gentoo_nolsa (Marvel/Titan)"
                } label: {
                    Text("Slot 3: gentoo_nolsa")
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(alpha.activeBootSlot >= 3 ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .liquidGlass(
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                            tint: alpha.activeBootSlot >= 3 ? AstralTheme.orbGreen.opacity(0.16) : .clear,
                            interactive: true)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        probingISO = true
                        defer { probingISO = false }
                        let res = await SandboxShell.shared.run("alpha-iso probe-drive")
                        alphaActionMessage = res.stdout.components(separatedBy: .newlines).first ?? "Verified Linux Alpha ISO"
                    }
                } label: {
                    HStack(spacing: 6) {
                        if probingISO {
                            ProgressView().controlSize(.mini)
                        } else {
                            AIcon(AstralIcons.checkCircle, size: 13, strokeWidth: 2.1, color: AstralTheme.orbGreen)
                        }
                        Text("Verify Drive ISO")
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(probingISO)

                Button {
                    Task {
                        let res = await SandboxShell.shared.run("alpha-iso extract-kernel")
                        alphaActionMessage = res.stdout.components(separatedBy: .newlines).first ?? "Extracted kernel to Workspace"
                    }
                } label: {
                    HStack(spacing: 6) {
                        AIcon(AstralIcons.fileCode, size: 13, strokeWidth: 2.1, color: AstralTheme.textPrimary)
                        Text("Extract Kernel")
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
            }

            if let alphaActionMessage {
                Text(alphaActionMessage)
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    private func kernelDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AstralTheme.mono(10.5).weight(.semibold))
                .foregroundStyle(AstralTheme.moonDust)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeCard(
        title: String,
        caption: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                AIcon(
                    icon,
                    size: 21,
                    strokeWidth: 2.1,
                    color: selected ? AstralTheme.orbGreen : AstralTheme.textSecondary)
                Text(title)
                    .font(AstralTheme.headline(13))
                    .foregroundStyle(selected ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                Text(caption)
                    .font(AstralTheme.mono(9.5))
                    .foregroundStyle(AstralTheme.moonDust)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                tint: selected ? AstralTheme.orbGreen.opacity(0.12) : AstralTheme.actionFill.opacity(0.03),
                interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selected ? AstralTheme.orbGreen.opacity(0.65) : Color.clear,
                        lineWidth: 1.4))
        }
        .buttonStyle(.plain)
    }

    // MARK: API key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "key", "settings.cloudAPIKey", table: "Settings")

            HStack(spacing: 8) {
                AIcon(
                    AstralIcons.key,
                    size: 15,
                    strokeWidth: 2.1,
                    color: cloud.isConfigured ? AstralTheme.success : AstralTheme.warning)
                Text(cloud.usesCustomKey
                    ? L("settings.cloudKeyCustom", "Settings")
                    : L("settings.cloudKeyBundled", "Settings"))
                    .font(AstralTheme.body(12.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                Spacer()
            }

            SecureField("e2b_...", text: $keyText)
                .font(AstralTheme.mono(13))
                .textFieldStyle(GlassTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if E2BComputer.shared.isConfigured && cloud.usesCustomKey {
                Button(role: .destructive) {
                    E2BComputer.shared.apiKey = ""
                    keyText = ""
                } label: {
                    HStack(spacing: 6) {
                        AIcon(AstralIcons.cloudOff, size: 13, strokeWidth: 2.1, color: AstralTheme.danger)
                        Text(L("settings.cloudDisconnect", "Settings"))
                            .font(AstralTheme.headline(13))
                            .foregroundStyle(AstralTheme.danger)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(L("settings.cloudKeyFooter", "Settings"))
                .font(AstralTheme.body(11.5))
                .foregroundStyle(AstralTheme.moonDust)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: Test

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await testAndSave() }
            } label: {
                HStack(spacing: 8) {
                    if testing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        AIcon(
                            AstralIcons.rocket,
                            size: 15,
                            strokeWidth: 2.1,
                            color: AstralTheme.actionForeground)
                    }
                    Text(testing
                         ? L("settings.cloudTesting", "Settings")
                         : L("settings.cloudTestAndSave", "Settings"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(testing)

            if let testResult {
                HStack(spacing: 8) {
                    AIcon(
                        testFailed ? AstralIcons.close : AstralIcons.checkCircle,
                        size: 14,
                        strokeWidth: 2.3,
                        color: testFailed ? AstralTheme.danger : AstralTheme.success)
                    Text(testResult)
                        .font(AstralTheme.body(12))
                        .foregroundStyle(testFailed ? AstralTheme.danger : AstralTheme.success)
                }
            }

            cloudStatusRow

            Text(L("settings.cloudAutoOff", "Settings"))
                .font(AstralTheme.body(11.5))
                .foregroundStyle(AstralTheme.moonDust)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    private var cloudStatusRow: some View {
        HStack(spacing: 8) {
            AIcon(
                AstralIcons.cloud,
                size: 14,
                strokeWidth: 2,
                color: AstralTheme.moonDust)
            Text(cloudStatusText)
                .font(AstralTheme.mono(12))
                .foregroundStyle(AstralTheme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private var cloudStatusText: String {
        switch cloud.status {
        case .off: return L("settings.cloudOff", "Settings")
        case .starting: return L("settings.cloudStarting", "Settings")
        case .running: return L("settings.cloudRunning", "Settings")
        case .failed: return L("settings.cloudFailed", "Settings")
        }
    }

    private func testAndSave() async {
        testing = true
        testResult = nil
        defer { testing = false }

        if !trimmedKey.isEmpty {
            E2BComputer.shared.apiKey = trimmedKey
        }
        do {
            _ = try await E2BComputer.shared.run(
                "echo 'Astral cloud computer online' && uname -a",
                timeout: 90)
            testFailed = false
            testResult = L("settings.cloudReady", "Settings")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await E2BComputer.shared.kill()
        } catch {
            if !trimmedKey.isEmpty {
                E2BComputer.shared.apiKey = ""
            }
            testFailed = true
            testResult = error.localizedDescription
        }
    }
}
