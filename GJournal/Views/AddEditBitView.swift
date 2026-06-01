//
//  AddEditBitView.swift
//  GJournal
//
//  Micro-journaling entry wizard (Feel → Event → Action).
//  Emotion detection is AI-background-only — no emotion picker shown here.
//  The AI classifies emotions after the entry is saved (see CoreMLEmotionService).
//

import SwiftUI
import SwiftData

struct AddEditBitView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @ObservedObject var repository: BaseJournalRepository

    let bitToEdit: Bit?
    let date: Date

    @State private var currentStep: TherapyStep = .welcome
    @State private var title: String = ""
    @State private var feel: String = ""
    @State private var event: String = ""
    @State private var action: String = ""
    @State private var intensity: Double = 2.0
    @State private var showingRepoError = false

    // Layout — updated by GeometryReader to avoid deprecated UIScreen.main.bounds
    @State private var slideWidth: CGFloat = 400
    @State private var slideOffset: CGFloat = 400
    @State private var currentStepOpacity: Double = 0

    enum TherapyStep: CaseIterable {
        case welcome
        case title
        case feelCheck
        case eventExplore
        case actionPlan
        case intensity
        case review

        var title: String {
            switch self {
            case .welcome:      return "Welcome"
            case .title:        return "Let's Begin"
            case .feelCheck:    return "Step 1: Feel"
            case .eventExplore: return "Step 2: Event"
            case .actionPlan:   return "Step 3: Action"
            case .intensity:    return "Intensity"
            case .review:       return "Review Your Story"
            }
        }

        var stepNumber: Int {
            switch self {
            case .welcome, .title: return 0
            case .feelCheck:       return 1
            case .eventExplore:    return 2
            case .actionPlan:      return 3
            case .intensity:       return 4
            case .review:          return 5
            }
        }
    }

    var isEditing: Bool { bitToEdit != nil }
    var totalSteps: Int { 5 }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if isEditing {
                        EditFormView(
                            title: $title,
                            feel: $feel,
                            event: $event,
                            action: $action,
                            intensity: $intensity,
                            onSave: saveBit,
                            onCancel: { dismiss() }
                        )
                    } else {
                        VStack {
                            if currentStep != .welcome {
                                ProgressIndicator(currentStep: currentStep.stepNumber, totalSteps: totalSteps)
                                    .padding(.top, 20)
                            }

                            ZStack {
                                ForEach([currentStep], id: \.self) { step in
                                    stepView(for: step)
                                        .offset(x: slideOffset)
                                        .opacity(currentStepOpacity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Spacer()
                        }
                    }
                }
                .onAppear {
                    slideWidth = geometry.size.width
                    slideOffset = geometry.size.width
                    loadBitData()
                    if !isEditing { animateIn() }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func stepView(for step: TherapyStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStepView(isEditing: isEditing, onNext: nextStep)
        case .title:
            TitleStepView(title: $title, onNext: nextStep, onSkip: nextStep)
        case .feelCheck:
            FeelStepView(feel: $feel, onNext: nextStep)
        case .eventExplore:
            EventStepView(event: $event, onNext: nextStep)
        case .actionPlan:
            ActionStepView(action: $action, onNext: nextStep)
        case .intensity:
            IntensityStepView(intensity: $intensity, onNext: nextStep)
        case .review:
            ReviewStepView(
                title: title,
                feel: feel,
                event: event,
                action: action,
                intensity: intensity,
                onSave: saveBit,
                onEdit: previousStep
            )
        }
    }

    private func nextStep() {
        let steps = TherapyStep.allCases
        guard let idx = steps.firstIndex(of: currentStep), idx < steps.count - 1 else { return }
        animateToStep(steps[idx + 1])
    }

    private func previousStep() {
        let steps = TherapyStep.allCases
        guard let idx = steps.firstIndex(of: currentStep), idx > 0 else { return }
        animateToStep(steps[idx - 1])
    }

    private func animateToStep(_ step: TherapyStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            slideOffset = -slideWidth
            currentStepOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentStep = step
            slideOffset = slideWidth
            withAnimation(.easeInOut(duration: 0.3)) {
                slideOffset = 0
                currentStepOpacity = 1
            }
        }
    }

    private func animateIn() {
        withAnimation(.easeInOut(duration: 0.5)) {
            slideOffset = 0
            currentStepOpacity = 1
        }
    }

    private func loadBitData() {
        guard let bit = bitToEdit else { return }
        title    = bit.title ?? ""
        feel     = bit.feel
        event    = bit.event
        action   = bit.action
        intensity = Double(bit.intensity)
    }

    private func saveBit() {
        let titleToSave = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        if let bit = bitToEdit {
            repository.updateBit(
                id: bit.id, title: titleToSave,
                feel: feel, event: event, action: action,
                intensity: Int(intensity)
            )
        } else {
            repository.createBit(
                title: titleToSave,
                feel: feel, event: event, action: action,
                intensity: Int(intensity)
            )
        }
        dismiss()
    }
}

// MARK: - Progress

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color(red: 0.55, green: 0.4, blue: 0.95) : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == currentStep ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .padding()
    }
}

// MARK: - Step Views

struct WelcomeStepView: View {
    let isEditing: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                Text(isEditing ? "Edit Your Story" : "Welcome to Your Journey")
                    .font(.title).fontWeight(.bold).foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(isEditing ? "Let's update your entry" : "Take a moment to explore your feelings and experiences")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer()
            Button(action: onNext) {
                Text("Begin").font(.headline).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(red: 0.55, green: 0.4, blue: 0.95)).cornerRadius(25)
            }
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
    }
}

struct TitleStepView: View {
    @Binding var title: String
    let onNext: () -> Void
    let onSkip: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("Give your story a title")
                    .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                Text("Optional — helps you remember this moment")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }.padding(.top, 60)
            Spacer()
            VStack(spacing: 20) {
                TextField("My story title...", text: $title)
                    .font(.title3).foregroundColor(.white).padding()
                    .background(Color.gray.opacity(0.2)).cornerRadius(15)
                    .focused($focused).padding(.horizontal, 30)
                HStack(spacing: 20) {
                    Button(action: onSkip) {
                        Text("Skip").font(.body).foregroundColor(.gray)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.gray.opacity(0.2)).cornerRadius(25)
                    }
                    Button(action: onNext) {
                        Text("Continue").font(.headline).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(red: 0.55, green: 0.4, blue: 0.95)).cornerRadius(25)
                    }
                }.padding(.horizontal, 30)
            }.padding(.bottom, 60)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

struct FeelStepView: View {
    @Binding var feel: String
    let onNext: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("How are you feeling right now?")
                    .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                Text("Describe your emotional state in your own words")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }.padding(.top, 60)
            Spacer()
            VStack(spacing: 20) {
                TextEditor(text: $feel)
                    .font(.body).foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2)).cornerRadius(15)
                    .frame(minHeight: 120).focused($focused).padding(.horizontal, 30)
                Button(action: onNext) {
                    Text("Next").font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding()
                        .background(feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.3) : Color(red: 0.55, green: 0.4, blue: 0.95))
                        .cornerRadius(25)
                }
                .disabled(feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }.padding(.bottom, 60)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

struct EventStepView: View {
    @Binding var event: String
    let onNext: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("What happened today?")
                    .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                Text("Share the events or situations that influenced how you're feeling")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }.padding(.top, 60)
            Spacer()
            VStack(spacing: 20) {
                TextEditor(text: $event)
                    .font(.body).foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2)).cornerRadius(15)
                    .frame(minHeight: 120).focused($focused).padding(.horizontal, 30)
                Button(action: onNext) {
                    Text("Next").font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding()
                        .background(event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.3) : Color(red: 0.55, green: 0.4, blue: 0.95))
                        .cornerRadius(25)
                }
                .disabled(event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }.padding(.bottom, 60)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

struct ActionStepView: View {
    @Binding var action: String
    let onNext: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("What will you do about it?")
                    .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                Text("Think about your next steps. What actions will you take?")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }.padding(.top, 60)
            Spacer()
            VStack(spacing: 20) {
                TextEditor(text: $action)
                    .font(.body).foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2)).cornerRadius(15)
                    .frame(minHeight: 120).focused($focused).padding(.horizontal, 30)
                Button(action: onNext) {
                    Text("Next").font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding()
                        .background(action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.3) : Color(red: 0.55, green: 0.4, blue: 0.95))
                        .cornerRadius(25)
                }
                .disabled(action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }.padding(.bottom, 60)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

struct IntensityStepView: View {
    @Binding var intensity: Double
    let onNext: () -> Void
    private let labels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("How intense is this feeling?")
                    .font(.title2).fontWeight(.semibold).foregroundColor(.white)
                Text("Slide to adjust the intensity of your overall experience")
                    .font(.body).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }.padding(.top, 60)
            Spacer()
            VStack(spacing: 30) {
                ZStack {
                    Circle().stroke(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.3), lineWidth: 8).frame(width: 150, height: 150)
                    Circle().trim(from: 0, to: intensity / 4.0)
                        .stroke(Color(red: 0.55, green: 0.4, blue: 0.95), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 150, height: 150).rotationEffect(.degrees(-90))
                    VStack {
                        Text(labels[Int(intensity) - 1]).font(.title3).fontWeight(.semibold).foregroundColor(.white)
                        Text("\(Int(intensity))/4").font(.caption).foregroundColor(.gray)
                    }
                }
                Slider(value: $intensity, in: 1...4, step: 1).accentColor(Color(red: 0.55, green: 0.4, blue: 0.95)).padding(.horizontal, 50)
                Button(action: onNext) {
                    Text("Almost Done").font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(red: 0.55, green: 0.4, blue: 0.95)).cornerRadius(25)
                }.padding(.horizontal, 30)
            }.padding(.bottom, 60)
        }
    }
}

struct ReviewStepView: View {
    let title: String
    let feel: String
    let event: String
    let action: String
    let intensity: Double
    let onSave: () -> Void
    let onEdit: () -> Void
    private let labels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("Your Story").font(.title).fontWeight(.bold).foregroundColor(.white)
                    Text("Here's your entry — emotions will be detected automatically after saving")
                        .font(.body).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }.padding(.top, 60)

                VStack(spacing: 20) {
                    if !title.isEmpty { ReviewSection(label: "Title", content: title) }
                    if !feel.isEmpty  { ReviewSection(label: "Feel",  content: feel)  }
                    if !event.isEmpty { ReviewSection(label: "Event", content: event) }
                    if !action.isEmpty { ReviewSection(label: "Action", content: action) }
                    ReviewSection(label: "Intensity", content: labels[Int(intensity) - 1])
                }.padding(.horizontal, 30)

                VStack(spacing: 16) {
                    Button(action: onSave) {
                        Text("Save My Story").font(.headline).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(red: 0.55, green: 0.4, blue: 0.95)).cornerRadius(25)
                    }
                    Button(action: onEdit) {
                        Text("Make Changes").font(.body).foregroundColor(.gray)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.gray.opacity(0.2)).cornerRadius(25)
                    }
                }.padding(.horizontal, 30).padding(.bottom, 60)
            }
        }
    }
}

struct ReviewSection: View {
    let label: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.headline).fontWeight(.semibold).foregroundColor(.white)
            Text(content).font(.body).foregroundColor(.gray).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
}

// MARK: - Edit Form (plain text, no emotion pickers)

struct EditFormView: View {
    @Binding var title: String
    @Binding var feel: String
    @Binding var event: String
    @Binding var action: String
    @Binding var intensity: Double
    let onSave: () -> Void
    let onCancel: () -> Void
    private let labels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel).foregroundColor(.gray)
                Spacer()
                Text("Edit Entry").font(.headline).fontWeight(.semibold).foregroundColor(.white)
                Spacer()
                Button("Save", action: onSave).foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95)).fontWeight(.semibold)
            }
            .padding(.horizontal, 20).padding(.top, 50).padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 24) {
                    EditSection(label: "Title (Optional)", text: $title, placeholder: "Add a title…")
                    EditSection(label: "Feel", text: $feel, placeholder: "How are you feeling?")
                    EditSection(label: "Event", text: $event, placeholder: "What happened?")
                    EditSection(label: "Action", text: $action, placeholder: "What will you do?")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Intensity").font(.subheadline).fontWeight(.medium).foregroundColor(.gray)
                        VStack(spacing: 16) {
                            HStack {
                                Text(labels[Int(intensity) - 1]).font(.body).fontWeight(.medium).foregroundColor(.white)
                                Spacer()
                                Text("\(Int(intensity))/4").font(.caption).foregroundColor(.gray)
                            }
                            Slider(value: $intensity, in: 1...4, step: 1).accentColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                        }
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.2)).cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 100)
            }
        }
    }
}

struct EditSection: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.subheadline).fontWeight(.medium).foregroundColor(.gray)
            TextEditor(text: $text)
                .font(.body).foregroundColor(.white)
                .scrollContentBackground(.hidden).background(Color.clear)
                .frame(minHeight: 60)
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Color.gray.opacity(0.2)).cornerRadius(12)
                .overlay(
                    text.isEmpty ? Text(placeholder).foregroundColor(.gray.opacity(0.5)).padding(20) : nil,
                    alignment: .topLeading
                )
        }
    }
}
