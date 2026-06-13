import SwiftUI

private enum ChangePINStep {
    case verifyOld
    case enterNew
    case confirmNew(first: String)
    case success
}

struct ChangePINView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var step: ChangePINStep = .verifyOld
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                switch step {
                    case .verifyOld:
                        PINKeypadView(
                            title: "Current PIN",
                            subtitle: "Enter your current PIN to continue",
                            errorMessage: errorMessage,
                            onCancel: { dismiss() }
                        ) { pin in
                            if authManager.verifyPIN(pin) {
                                errorMessage = nil
                                withAnimation { step = .enterNew }
                            } else {
                                errorMessage = "Incorrect PIN — try again"
                            }
                        }

                    case .enterNew:
                        PINKeypadView(
                            title: "New PIN",
                            subtitle: "Choose a new 6-digit PIN",
                            errorMessage: errorMessage,
                            onCancel: { withAnimation { step = .verifyOld } }
                        ) { pin in
                            errorMessage = nil
                            withAnimation { step = .confirmNew(first: pin) }
                        }

                    case .confirmNew(let first):
                        PINKeypadView(
                            title: "Confirm new PIN",
                            subtitle: "Re-enter the new PIN",
                            errorMessage: errorMessage,
                            onCancel: { withAnimation { step = .enterNew } }
                        ) { pin in
                            if pin == first {
                                authManager.setPIN(pin)
                                withAnimation { step = .success }
                            } else {
                                errorMessage = "PINs don't match — try again"
                                withAnimation { step = .enterNew }
                            }
                        }

                    case .success:
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 72))
                                .foregroundColor(.green)
                            Text("PIN updated")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Button("Done") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(.pink)
                        }
                    }
                Spacer()
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .success = step { } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

#Preview {
    ChangePINView()
        .environmentObject(AuthManager())
}
