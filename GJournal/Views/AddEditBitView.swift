//
//  AddEditBitView.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI

struct AddEditBitView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @ObservedObject var repository: BaseJournalRepository

    let bitToEdit: Bit?
    let date: Date

    // Therapy session state
    @State private var currentStep: TherapyStep = .welcome
    @State private var title: String = ""
    @State private var feel: String = ""
    @State private var event: String = ""
    @State private var action: String = ""
    @State private var selectedFeelEmotion: Emotion = .joy
    @State private var selectedEventEmotion: Emotion = .surprise
    @State private var selectedActionEmotion: Emotion = .hope
    @State private var intensity: Double = 2.0
    @State private var showingRepoError = false
    @State private var emotionConfigManager: EmotionConfigurationManager?

    // Animation states
    @State private var slideOffset: CGFloat = UIScreen.main.bounds.width
    @State private var currentStepOpacity: Double = 0

    enum TherapyStep: CaseIterable {
        case welcome
        case title
        case feelCheck
        case feelEmotion
        case eventExplore
        case eventEmotion
        case actionPlan
        case actionEmotion
        case intensity
        case review

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .title: return "Let's Begin"
            case .feelCheck: return "Step 1: Feel"
            case .feelEmotion: return "Step 1: Feel"
            case .eventExplore: return "Step 2: Event"
            case .eventEmotion: return "Step 2: Event"
            case .actionPlan: return "Step 3: Action"
            case .actionEmotion: return "Step 3: Action"
            case .intensity: return "Intensity"
            case .review: return "Review Your Story"
            }
        }

        var stepNumber: Int {
            switch self {
            case .welcome, .title: return 0
            case .feelCheck, .feelEmotion: return 1
            case .eventExplore, .eventEmotion: return 2
            case .actionPlan, .actionEmotion: return 3
            case .intensity: return 4
            case .review: return 5
            }
        }
    }

    var isEditing: Bool {
        bitToEdit != nil
    }

    var totalSteps: Int { 5 }

    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                if isEditing {
                    // Simple edit form for existing bits
                    EditFormView(
                        title: $title,
                        feel: $feel,
                        event: $event,
                        action: $action,
                        selectedFeelEmotion: $selectedFeelEmotion,
                        selectedEventEmotion: $selectedEventEmotion,
                        selectedActionEmotion: $selectedActionEmotion,
                        intensity: $intensity,
                        emotionConfigManager: emotionConfigManager,
                        onSave: saveBit,
                        onCancel: { dismiss() }
                    )
                } else {
                    // Therapeutic journey for new bits
                    VStack {
                        // Progress indicator
                        if currentStep != .welcome {
                            ProgressIndicator(currentStep: currentStep.stepNumber, totalSteps: totalSteps)
                                .padding(.top, 20)
                        }

                        // Content area
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
            .navigationBarHidden(true)
            .onAppear {
                emotionConfigManager = EmotionConfigurationManager(modelContext: modelContext)
                loadBitData()
                if !isEditing {
                    animateIn()
                }
            }
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
        case .feelEmotion:
            EmotionSelectionView(
                title: "How did that feel?",
                subtitle: "Choose the emotion that best captures your feeling",
                selectedEmotion: $selectedFeelEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.feel) ?? Emotion.allCases,
                onNext: nextStep
            )
        case .eventExplore:
            EventStepView(event: $event, onNext: nextStep)
        case .eventEmotion:
            EmotionSelectionView(
                title: "What emotion does this event bring up?",
                subtitle: "Select how this event made you feel",
                selectedEmotion: $selectedEventEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.event) ?? Emotion.allCases,
                onNext: nextStep
            )
        case .actionPlan:
            ActionStepView(action: $action, onNext: nextStep)
        case .actionEmotion:
            EmotionSelectionView(
                title: "How do you feel about taking this action?",
                subtitle: "What emotion does your plan bring up?",
                selectedEmotion: $selectedActionEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.action) ?? Emotion.allCases,
                onNext: nextStep
            )
        case .intensity:
            IntensityStepView(intensity: $intensity, onNext: nextStep)
        case .review:
            ReviewStepView(
                title: title,
                feel: feel,
                feelEmotion: selectedFeelEmotion,
                event: event,
                eventEmotion: selectedEventEmotion,
                action: action,
                actionEmotion: selectedActionEmotion,
                intensity: intensity,
                onSave: saveBit,
                onEdit: previousStep
            )
        }
    }

    private func nextStep() {
        let steps = TherapyStep.allCases
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex < steps.count - 1 else { return }

        animateToStep(steps[currentIndex + 1])
    }

    private func previousStep() {
        let steps = TherapyStep.allCases
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex > 0 else { return }

        animateToStep(steps[currentIndex - 1])
    }

    private func animateToStep(_ step: TherapyStep) {
        // Slide out current
        withAnimation(.easeInOut(duration: 0.3)) {
            slideOffset = -UIScreen.main.bounds.width
            currentStepOpacity = 0
        }

        // Change step and slide in new
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentStep = step
            slideOffset = UIScreen.main.bounds.width

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
        if let bit = bitToEdit {
            title = bit.title ?? ""
            feel = bit.feel
            event = bit.event
            action = bit.action
            selectedFeelEmotion = bit.feelEmotion
            selectedEventEmotion = bit.eventEmotion
            selectedActionEmotion = bit.actionEmotion
            intensity = Double(bit.intensity)
        }
    }

    private func saveBit() {
        let titleToSave = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title

        if let bit = bitToEdit {
            repository.updateBit(
                id: bit.id,
                title: titleToSave,
                feel: feel,
                event: event,
                action: action,
                feelEmotion: selectedFeelEmotion,
                eventEmotion: selectedEventEmotion,
                actionEmotion: selectedActionEmotion,
                intensity: Int(intensity)
            )
        } else {
            repository.createBit(
                title: titleToSave,
                feel: feel,
                event: event,
                action: action,
                feelEmotion: selectedFeelEmotion,
                eventEmotion: selectedEventEmotion,
                actionEmotion: selectedActionEmotion,
                intensity: Int(intensity)
            )
        }

        dismiss()
    }
}

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.pink : Color.gray.opacity(0.3))
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
                    .foregroundColor(.pink)

                Text(isEditing ? "Edit Your Story" : "Welcome to Your Journey")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(isEditing ? "Let's update your emotional journey" : "Take a moment to explore your feelings and experiences")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: onNext) {
                Text("Begin")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .cornerRadius(25)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

struct TitleStepView: View {
    @Binding var title: String
    let onNext: () -> Void
    let onSkip: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("Give your story a title")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("This is optional, but it can help you remember this moment")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 20) {
                TextField("My story title...", text: $title)
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 30)

                HStack(spacing: 20) {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.body)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(25)
                    }

                    Button(action: onNext) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink)
                            .cornerRadius(25)
                    }
                }
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

struct FeelStepView: View {
    @Binding var feel: String
    let onNext: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("How are you feeling right now?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Take a moment to check in with yourself. What emotions are you experiencing?")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 20) {
                TextEditor(text: $feel)
                    .font(.body)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .frame(minHeight: 120)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 30)

                Button(action: onNext) {
                    Text("Next")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.pink)
                        .cornerRadius(25)
                }
                .disabled(feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

struct EventStepView: View {
    @Binding var event: String
    let onNext: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("What happened today?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Share the events or situations that influenced how you're feeling")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 20) {
                TextEditor(text: $event)
                    .font(.body)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .frame(minHeight: 120)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 30)

                Button(action: onNext) {
                    Text("Next")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.pink)
                        .cornerRadius(25)
                }
                .disabled(event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

struct ActionStepView: View {
    @Binding var action: String
    let onNext: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text("What will you do about it?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Think about your next steps. What actions will you take moving forward?")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 20) {
                TextEditor(text: $action)
                    .font(.body)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .frame(minHeight: 120)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 30)

                Button(action: onNext) {
                    Text("Next")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.pink)
                        .cornerRadius(25)
                }
                .disabled(action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

struct EmotionSelectionView: View {
    let title: String
    let subtitle: String
    @Binding var selectedEmotion: Emotion
    let emotions: [Emotion]
    let onNext: () -> Void

    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(emotions, id: \.self) { emotion in
                        TherapyEmotionCell(
                            emotion: emotion,
                            isSelected: selectedEmotion == emotion
                        ) {
                            selectedEmotion = emotion
                        }
                    }
                }
                .padding(.horizontal, 30)
            }

            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .cornerRadius(25)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 60)
        }
    }
}

struct TherapyEmotionCell: View {
    let emotion: Emotion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? emotion.color : Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Text(emotion.emoji)
                        .font(.title2)
                }

                Text(emotion.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct IntensityStepView: View {
    @Binding var intensity: Double
    let onNext: () -> Void

    private let intensityLabels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("How intense is this feeling?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Slide to adjust the intensity of your overall experience")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 30) {
                // Large intensity indicator
                ZStack {
                    Circle()
                        .stroke(Color.pink.opacity(0.3), lineWidth: 8)
                        .frame(width: 150, height: 150)

                    Circle()
                        .trim(from: 0, to: intensity / 4.0)
                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))

                    VStack {
                        Text(intensityLabels[Int(intensity) - 1])
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Text("\(Int(intensity))/4")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Slider(value: $intensity, in: 1...4, step: 1)
                    .accentColor(.pink)
                    .padding(.horizontal, 50)

                Button(action: onNext) {
                    Text("Almost Done")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .cornerRadius(25)
                }
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 60)
        }
    }
}

struct ReviewStepView: View {
    let title: String
    let feel: String
    let feelEmotion: Emotion
    let event: String
    let eventEmotion: Emotion
    let action: String
    let actionEmotion: Emotion
    let intensity: Double
    let onSave: () -> Void
    let onEdit: () -> Void

    private let intensityLabels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("Your Story")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Here's your emotional journey for today")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)

                VStack(spacing: 20) {
                    if !title.isEmpty {
                        ReviewSection(
                            title: "Title",
                            content: title,
                            emotion: nil
                        )
                    }

                    if !feel.isEmpty {
                        ReviewSection(
                            title: "Feel",
                            content: feel,
                            emotion: feelEmotion
                        )
                    }

                    if !event.isEmpty {
                        ReviewSection(
                            title: "Event",
                            content: event,
                            emotion: eventEmotion
                        )
                    }

                    if !action.isEmpty {
                        ReviewSection(
                            title: "Action",
                            content: action,
                            emotion: actionEmotion
                        )
                    }

                    ReviewSection(
                        title: "Intensity",
                        content: intensityLabels[Int(intensity) - 1],
                        emotion: nil
                    )
                }
                .padding(.horizontal, 30)

                VStack(spacing: 16) {
                    Button(action: onSave) {
                        Text("Save My Story")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink)
                            .cornerRadius(25)
                    }

                    Button(action: onEdit) {
                        Text("Make Changes")
                            .font(.body)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(25)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 60)
            }
        }
    }
}

struct ReviewSection: View {
    let title: String
    let content: String
    let emotion: Emotion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let emotion = emotion {
                    Text(emotion.emoji)
                        .font(.title2)
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()
            }

            Text(content)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
}

// MARK: - Edit Form View

struct EditFormView: View {
    @Binding var title: String
    @Binding var feel: String
    @Binding var event: String
    @Binding var action: String
    @Binding var selectedFeelEmotion: Emotion
    @Binding var selectedEventEmotion: Emotion
    @Binding var selectedActionEmotion: Emotion
    @Binding var intensity: Double

    let emotionConfigManager: EmotionConfigurationManager?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var showingFeelEmotions = false
    @State private var showingEventEmotions = false
    @State private var showingActionEmotions = false

    private let intensityLabels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundColor(.gray)

                Spacer()

                Text("Edit Entry")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                Button("Save", action: onSave)
                    .foregroundColor(.pink)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .padding(.bottom, 20)

            // Form content
            ScrollView {
                VStack(spacing: 24) {
                    // Title section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Title (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        TextField("Add a title for this entry...", text: $title)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                    }

                    // Feel section
                    EditSection(
                        title: "Feel",
                        text: $feel,
                        emotion: selectedFeelEmotion,
                        placeholder: "How are you feeling?",
                        onEmotionTap: { showingFeelEmotions = true }
                    )

                    // Event section
                    EditSection(
                        title: "Event",
                        text: $event,
                        emotion: selectedEventEmotion,
                        placeholder: "What happened?",
                        onEmotionTap: { showingEventEmotions = true }
                    )

                    // Action section
                    EditSection(
                        title: "Action",
                        text: $action,
                        emotion: selectedActionEmotion,
                        placeholder: "What will you do?",
                        onEmotionTap: { showingActionEmotions = true }
                    )

                    // Intensity section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Intensity")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        VStack(spacing: 16) {
                            HStack {
                                Text(intensityLabels[Int(intensity) - 1])
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)

                                Spacer()

                                Text("\(Int(intensity))/4")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Slider(value: $intensity, in: 1...4, step: 1)
                                .accentColor(.pink)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingFeelEmotions) {
            EmotionPickerSheet(
                title: "Feel Emotion",
                selectedEmotion: $selectedFeelEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.feel) ?? Emotion.allCases,
                isPresented: $showingFeelEmotions
            )
        }
        .sheet(isPresented: $showingEventEmotions) {
            EmotionPickerSheet(
                title: "Event Emotion",
                selectedEmotion: $selectedEventEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.event) ?? Emotion.allCases,
                isPresented: $showingEventEmotions
            )
        }
        .sheet(isPresented: $showingActionEmotions) {
            EmotionPickerSheet(
                title: "Action Emotion",
                selectedEmotion: $selectedActionEmotion,
                emotions: emotionConfigManager?.getEmotionsForField(.action) ?? Emotion.allCases,
                isPresented: $showingActionEmotions
            )
        }
    }
}

struct EditSection: View {
    let title: String
    @Binding var text: String
    let emotion: Emotion
    let placeholder: String
    let onEmotionTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)

                Spacer()

                Button(action: onEmotionTap) {
                    HStack(spacing: 8) {
                        Text(emotion.emoji)
                            .font(.body)

                        Text(emotion.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(emotion.color.opacity(0.2))
                    .cornerRadius(8)
                }
            }

            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 80)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
        }
    }
}

struct EmotionPickerSheet: View {
    let title: String
    @Binding var selectedEmotion: Emotion
    let emotions: [Emotion]
    @Binding var isPresented: Bool

    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(emotions, id: \.self) { emotion in
                            Button(action: {
                                selectedEmotion = emotion
                                isPresented = false
                            }) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(selectedEmotion == emotion ? emotion.color : Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 60)

                                        Text(emotion.emoji)
                                            .font(.title2)
                                    }

                                    Text(emotion.rawValue)
                                        .font(.caption)
                                        .fontWeight(selectedEmotion == emotion ? .semibold : .regular)
                                        .foregroundColor(selectedEmotion == emotion ? .white : .gray)
                                }
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(selectedEmotion == emotion ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: selectedEmotion)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
                .foregroundColor(.pink)
            )
        }
        .preferredColorScheme(.dark)
    }
