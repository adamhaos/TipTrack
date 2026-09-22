import SwiftUI
import LocalAuthentication
import Observation
import WidgetKit

@MainActor @Observable
final class PrivacyManager {
    static let shared = PrivacyManager()
    var enabled = UserDefaults.standard.bool(forKey: "privacyEnabled")
    var unlocked = false
    var authenticating = false
    var message: String?
    var hidden: Bool { enabled && !unlocked }

    func authenticate() async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        do {
            let success = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "Reveal your TipTrack earnings")
            unlocked = success
            message = nil
            return success
        } catch {
            message = "Authentication was not completed. Your earnings remain hidden."
            return false
        }
    }
    func setEnabled(_ value: Bool) async {
        guard await authenticate() else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "privacyEnabled")
        let shared = UserDefaults(suiteName: "group.atm.TipTrack")
        shared?.set(value, forKey: "privacyEnabled")
        if value { shared?.removeObject(forKey: "tiptrack.widget.snapshot") }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct EarningsProtection: ViewModifier {
    @Bindable private var privacy = PrivacyManager.shared
    func body(content: Content) -> some View {
        if privacy.hidden {
            VStack(spacing: 10) {
                Image(systemName: "eye.slash").font(.title2)
                Text("Earnings hidden").font(.headline)
                Button("Unlock with Face ID") { Task { _ = await privacy.authenticate() } }
                    .buttonStyle(.borderedProminent).disabled(privacy.authenticating)
                if let message = privacy.message { Text(message).font(.caption).multilineTextAlignment(.center) }
            }
            .frame(maxWidth: .infinity).padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        } else { content }
    }
}
extension View {
    func protectEarnings() -> some View { modifier(EarningsProtection()) }
}

struct AppLockView: View {
    @Bindable private var privacy = PrivacyManager.shared
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.tint)
                Text("TipTrack Is Locked").font(.title2.bold())
                Text("Authenticate to open your jobs, shifts, and earnings.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Unlock with Face ID") { Task { _ = await privacy.authenticate() } }
                    .buttonStyle(.borderedProminent).disabled(privacy.authenticating)
                if let message = privacy.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(32)
        }
        .task {
            _ = await privacy.authenticate()
        }
    }
}
