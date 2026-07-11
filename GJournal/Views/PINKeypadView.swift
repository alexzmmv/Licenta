import SwiftUI

struct PINKeypadView: View {
    let title: String
    var subtitle: String? = nil
    var errorMessage: String? = nil
    var onCancel: (() -> Void)? = nil
    let onComplete: (String) -> Void   // called once when 6 digits are entered; pin resets after

    @State private var pin = ""
    private let pinLength = 6

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let sub = subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 20) {
                ForEach(0..<pinLength, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.pink : Color.gray.opacity(0.3))
                        .frame(width: 14, height: 14)
                        .animation(.easeInOut(duration: 0.08), value: pin.count)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
                    .animation(.easeInOut, value: errorMessage)
            }

            VStack(spacing: 16) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { digit in
                            digitButton(digit)
                        }
                    }
                }
                HStack(spacing: 24) {
                    if let cancel = onCancel {
                        Button("Cancel", action: cancel)
                            .frame(width: 76, height: 76)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Color.clear.frame(width: 76, height: 76)
                    }
                    digitButton(0)
                    Button {
                        if !pin.isEmpty { pin.removeLast() }
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.title2)
                    }
                    .frame(width: 76, height: 76)
                    .foregroundColor(.primary)
                    .accessibilityIdentifier("PINDelete")
                    .accessibilityLabel(Text("Delete"))
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func digitButton(_ digit: Int) -> some View {
        Button {
            guard pin.count < pinLength else { return }
            pin += String(digit)
            if pin.count == pinLength {
                let completed = pin
                pin = ""                // reset so keypad is ready for retry
                onComplete(completed)
            }
        } label: {
            Text(String(digit))
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .frame(width: 76, height: 76)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
        }
        .foregroundColor(.primary)
        .accessibilityIdentifier("PINDigit\(digit)")
    }
}

#Preview {
    PINKeypadView(title: "Enter PIN", subtitle: "6-digit code") { pin in
        print("PIN entered: \(pin)")
    }
}
