import SwiftUI
import UIKit

// MARK: - Quick Launch (V4.6.0 — the Action Button experience)

/// The creative overlay the `astral://quick` deep link and the Quick Task
/// app intent land in: a deep-space stage, a breathing green orb, and one
/// big glass input that fires the task the moment it is sent — the app
/// blooms open directly here from the Action Button (iPhone 15 Pro and
/// later), so giving Astral a task never feels like opening an app.
///
/// The flow: press the Action Button → iOS shows the task text field over
/// whatever is on screen → the app opens straight into this overlay with
/// the task seeded → haptic pulse → send → the overlay hands the turn to
/// the live chat underneath and dissolves.
struct QuickLaunchView: View {
    /// Seed text handed over by the deep link / intent (consumed on open).
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var appeared = false
    @State private var sending = false
    @State private var dragOffset: CGFloat = 0

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager

    var body: some View {
        ZStack {
            quickBackground

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                orbStage
                Spacer(minLength: 12)
                composerPanel
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 22)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .offset(y: dragOffset)
        .gesture(dismissDrag)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                appeared = true
            }
            // The Action Button pulse: a heavy hit then a success chime —
            // the physical "Astra heard you" moment.
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let seed = env.quickLaunchSeed, !seed.isEmpty {
                draft = seed
                env.quickLaunchSeed = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                focused = true
            }
        }
        .onDisappear {
            env.quickLaunchSeed = nil
        }
    }

    // MARK: Background

    /// Deep-space stage: the app background, a soft green nebula glow, and
    /// a field of drifting stars drawn on one canvas.
    private var quickBackground: some View {
        ZStack {
            AstralTheme.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    AstralTheme.orbGreen.opacity(0.14),
                    AstralTheme.orbGreen.opacity(0.0),
                ],
                center: .center,
                startRadius: 20,
                endRadius: 460)
                .ignoresSafeArea()

            QuickStarfield()
                .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassCloseButton { close() }

            Spacer()

            HStack(spacing: 6) {
                AIcon(
                    AstralIcons.zap,
                    size: 12,
                    strokeWidth: 2.4,
                    color: AstralTheme.orbGreen)
                Text(L("quick.badge", "Chat"))
                    .font(AstralTheme.mono(11).weight(.semibold))
                    .foregroundStyle(AstralTheme.textSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .liquidCapsule()
            .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    // MARK: Orb stage

    private var orbStage: some View {
        VStack(spacing: 18) {
            ActivityOrb(color: AstralTheme.orbGreen, size: 64)

            VStack(spacing: 7) {
                Text(L("quick.title", "Chat"))
                    .font(AstralTheme.display(30, weight: .semibold))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L("quick.subtitle", "Chat"))
                    .font(AstralTheme.body(14.5))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Composer

    private var composerPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    L("quick.placeholder", "Chat"),
                    text: $draft,
                    axis: .vertical)
                    .font(AstralTheme.body(17))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { sendDraft() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 54, alignment: .center)

                Button(action: sendDraft) {
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 17,
                        strokeWidth: 2.6,
                        color: AstralTheme.actionForeground)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(AstralTheme.actionFill))
                }
                .buttonStyle(PressableOrbStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                // V4.7.0: the button breathes awake the moment there is
                // something to send — a scale pulse, not just a fade.
                .scaleEffect(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.86 : 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: draft.isEmpty)
                .padding(.trailing, 8)
            }
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 27, style: .continuous),
                interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))

            Text(L("quick.swipeHint", "Chat"))
                .font(AstralTheme.body(12))
                .foregroundStyle(AstralTheme.textSecondary.opacity(0.8))
        }
    }

    // MARK: Gestures & actions

    /// Swipe down anywhere to dissolve back into the chat.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height * 0.55
            }
            .onEnded { value in
                if value.translation.height > 130 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true

        // The tactile send: lighter than the arrival pulse.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let session = env.sessionStore.newSession()
        env.sessionStore.select(session)
        Task { @MainActor in
            session.send(text)
        }

        // Hand the turn to the live chat underneath, then dissolve.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            close()
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            env.showQuickLaunch = false
        }
    }
}

// MARK: - Starfield

/// A single-canvas star field — deterministic positions, drifting
/// twinkles, no timers (TimelineView drives the phase).
private struct QuickStarfield: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            Canvas { context, size in
                let date = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<90 {
                    let seed = Double(index)
                    let x = size.width * fract(sin(seed * 12.9898) * 43758.5453)
                    let y = size.height * fract(sin(seed * 78.233) * 43758.5453)
                    let radius = 0.7 + fract(sin(seed * 39.425) * 43758.5453) * 1.5
                    let phase = sin(date * (0.35 + fract(seed * 0.7) * 0.6) + seed)
                    let alpha = 0.16 + 0.5 * max(0, phase)
                    let rect = CGRect(
                        x: x - radius, y: y - radius,
                        width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
