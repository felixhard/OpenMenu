import SwiftUI
import AppKit
import OpenMenuCore

/// First-launch onboarding: welcome, the Accessibility grant, and a wrap-up.
/// Hosted in its own centered window by `OnboardingController`.
struct OnboardingView: View {

    /// Called when the user finishes the last step.
    let finish: () -> Void

    private enum Step {
        case welcome, permission, done
    }

    @State private var step = Step.welcome
    @State private var accessibilityGranted = Permissions.isAccessibilityTrusted
    @State private var hasPromptedAccessibility = false

    var body: some View {
        ZStack {
            switch step {
            case .welcome: welcome.transition(stepTransition)
            case .permission: permission.transition(stepTransition)
            case .done: done.transition(stepTransition)
            }
        }
        .frame(width: 360, height: 460)
        .background(GlassCard(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Poll while the permission step is up so the card flips to "Granted"
        // the moment the user flips the switch in System Settings.
        .task(id: step) {
            guard step == .permission else { return }
            while !Task.isCancelled {
                accessibilityGranted = Permissions.isAccessibilityTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 10) {
            Spacer()
            // Load from the asset catalog, not NSApp.applicationIconImage: the
            // latter goes through Icon Services, whose cache can serve a stale
            // icon for a while after the icon changes.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 108, height: 108)
            Text("Welcome to OpenMenu")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Window switching, clipboard history, window tiling and system monitoring. All from your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Get Started") { advance(to: .permission) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .padding(28)
    }

    private var permission: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 18)
            Text("Enable Accessibility")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("OpenMenu needs Accessibility to see and move other apps' windows. It powers the window switcher, tiling and keyboard cleaning.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            accessibilityCard
                .padding(.top, 14)

            Text("OpenMenu appears in System Settings under Privacy & Security, Accessibility.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Button("Continue") { advance(to: .done) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!accessibilityGranted)
        }
        .padding(28)
    }

    private var accessibilityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "accessibility")
                .font(.system(size: 24))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(accessibilityGranted ? "Granted" : "Required")
                    .font(.system(size: 11))
                    .foregroundStyle(accessibilityGranted ? LiquidGlass.good : .white.opacity(0.55))
            }
            Spacer()
            if accessibilityGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(LiquidGlass.good)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(hasPromptedAccessibility ? "Open Settings" : "Grant") {
                    requestAccessibility()
                }
                .buttonStyle(OnboardingSmallButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .animation(.easeOut(duration: 0.2), value: accessibilityGranted)
    }

    private var done: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(LiquidGlass.good)
            Text("You're all set")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("OpenMenu lives in your menu bar. Press \u{2318}Tab to switch windows and \u{2318}\u{21E7}V for clipboard history.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Start Using OpenMenu") { finish() }
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .padding(28)
    }

    // MARK: - Actions

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }

    /// First click surfaces the system prompt (which deep-links to the pane).
    /// If the user already dismissed it, macOS won't show it again, so later
    /// clicks open the Accessibility pane directly.
    private func requestAccessibility() {
        if hasPromptedAccessibility {
            Permissions.openAccessibilitySettings()
        } else {
            hasPromptedAccessibility = true
            Permissions.ensureAccessibility(prompt: true)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 28).combined(with: .opacity),
            removal: .offset(x: -28).combined(with: .opacity)
        )
    }
}

/// Full-width accent call-to-action used for each step's main button.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(LiquidGlass.accent) : AnyShapeStyle(.white.opacity(0.08)))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact accent button for the permission card's Grant action.
private struct OnboardingSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(LiquidGlass.accent))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
