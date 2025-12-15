import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var notificationPermissionGranted = false
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    notificationStep
                case 2:
                    readyStep
                default:
                    EmptyView()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(currentStep == totalSteps - 1 ? "Start" : "Next") {
                    if currentStep == totalSteps - 1 {
                        completeOnboarding()
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(width: 420, height: 340)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Port Forwarder")
                .font(.title2.bold())

            Text("Easily manage your Kubernetes port-forward\nconnections from the menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var notificationStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Notifications")
                .font(.title2.bold())

            Text("Would you like to be notified about\nconnection status changes?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                NotificationManager.shared.requestPermission()
                notificationPermissionGranted = true
            } label: {
                Label(
                    notificationPermissionGranted ? "Permission Requested" : "Allow Notifications",
                    systemImage: notificationPermissionGranted ? "checkmark.circle.fill" : "bell"
                )
            }
            .buttonStyle(.bordered)
            .disabled(notificationPermissionGranted)
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.title2.bold())

            Text("Port Forwarder is now in your menu bar.\nYou can access it anytime from there.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(.secondary)
                Text("Click the")
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                Text("icon in the menu bar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        hasCompletedOnboarding = true

        // Hide from Dock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }

        dismiss()
    }
}

#Preview {
    OnboardingView()
}
