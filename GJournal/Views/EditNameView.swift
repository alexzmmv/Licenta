import SwiftUI

/// Rename the account. The name is a display label used in the dashboard
/// greeting — it is not a credential and grants no access to anything.
struct EditNameView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { trimmed.count >= 2 }

    private var isUnchanged: Bool { trimmed == (authManager.currentUser ?? "") }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(save)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                } else {
                    Text("This is only used to greet you on the dashboard. It never leaves your device.")
                }
            }
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!isValid || isUnchanged)
            }
        }
        .onAppear {
            name = authManager.currentUser ?? ""
            isFocused = true
        }
    }

    private func save() {
        guard isValid, !isUnchanged else { return }
        do {
            try authManager.updateName(name)
            dismiss()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't save your name. Please try again."
        }
    }
}

#Preview {
    NavigationStack {
        EditNameView()
            .environmentObject(AuthManager())
    }
}
