// CreateJoinSquadSheet.swift
// App / ZANO / Features / Squad
//
// Create a squad (name, emblem, color → invite code + share link) or join one by code
// (docs/spec.md §5.7). Opened from the Squad tab's hero, or from `zano://squad/join/<CODE>` with
// the code filled in.
//
// Offline: creating still works (the squad and its code are saved locally and queued for sync, so
// the code is "reserved"); joining a code that isn't on this phone can't resolve without the
// backend, so the code is saved and retried automatically once squads are live
// (`SquadHomeModel.joinSquad`). The buttons say which of those will happen before the tap.

import SwiftUI
import Core

struct CreateJoinSquadSheet: View {
    enum Mode: String, Identifiable, CaseIterable {
        case create, join
        var id: String { rawValue }
    }

    let model: SquadHomeModel
    let initialMode: Mode
    let prefilledCode: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var style = SquadStyle.default
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var created: SquadSnapshot?
    @State private var joinResult: SquadHomeModel.JoinOutcome?
    @State private var successTick = 0
    @FocusState private var focusedField: Field?

    private enum Field { case name, code }

    init(model: SquadHomeModel, initialMode: Mode, prefilledCode: String = "") {
        self.model = model
        self.initialMode = initialMode
        self.prefilledCode = prefilledCode
        _mode = State(initialValue: initialMode)
        _code = State(initialValue: prefilledCode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let created {
                        createdContent(created)
                    } else if let joinResult {
                        joinedContent(joinResult)
                    } else {
                        Picker("", selection: $mode) {
                            Text(Copy.squad.createTab).tag(Mode.create)
                            Text(Copy.squad.joinTab).tag(Mode.join)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        switch mode {
                        case .create: createForm
                        case .join: joinForm
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .zanoText(.captionEmphasized)
                                .foregroundStyle(Theme.Colors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: mode)
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: created)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle(created == nil && joinResult == nil
                             ? (mode == .create ? Copy.squad.createTitle : Copy.squad.joinTitle)
                             : Copy.squad.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if created == nil && joinResult == nil {
                        Button(Copy.squad.cancel) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if created != nil || joinResult != nil {
                        Button(Copy.squad.done) { dismiss() }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: successTick)
            .onChange(of: mode) { _, _ in errorMessage = nil }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Create

    private var createForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                Text(style.emoji)
                    .font(.system(size: 34))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(style.color.opacity(0.18)))
                    .overlay(Circle().strokeBorder(style.color.opacity(0.6), lineWidth: 1.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.squad.nameFieldLabel)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    TextField(Copy.squad.namePlaceholder, text: $name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.text)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .name)
                        .onChange(of: name) { _, new in
                            if new.count > 32 { name = String(new.prefix(32)) }
                        }
                        .accessibilityLabel(Copy.squad.nameFieldLabel)
                }
            }
            .padding(Theme.Spacing.md)
            .zanoCard(tint: style.color)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SquadSectionLabel(text: Copy.squad.emojiLabel)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 8), spacing: Theme.Spacing.xs) {
                    ForEach(SquadStyle.emojis, id: \.self) { emoji in
                        Button {
                            style.emoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                        .fill(style.emoji == emoji ? style.color.opacity(0.22) : Theme.Colors.surface2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                        .strokeBorder(style.emoji == emoji ? style.color : .clear, lineWidth: Theme.Metrics.selectedStroke)
                                )
                        }
                        .buttonStyle(.pressable(scale: 0.94))
                        .accessibilityAddTraits(style.emoji == emoji ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: style)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SquadSectionLabel(text: Copy.squad.colorLabel)
                HStack(spacing: 0) {
                    ForEach(SquadStyle.palette.indices, id: \.self) { index in
                        Button {
                            style.colorIndex = index
                        } label: {
                            Circle()
                                .fill(SquadStyle.palette[index])
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.Colors.text, lineWidth: style.colorIndex == index ? 2 : 0)
                                        .padding(-4)
                                )
                                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                        }
                        .buttonStyle(.pressable(scale: 0.9))
                        .accessibilityAddTraits(style.colorIndex == index ? .isSelected : [])
                    }
                }
            }

            if !model.backendConnected {
                Text(Copy.squad.inviteOfflineNote)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                title: model.backendConnected ? Copy.squad.createButton : Copy.squad.createOfflineButton,
                systemImage: "person.2.fill",
                isEnabled: !isWorking && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { await create() }
            }
            .accessibilityIdentifier("squad.createSubmit")
        }
        .onAppear { if initialMode == .create { focusedField = .name } }
    }

    private func create() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let squad = try await model.createSquad(name: name, style: style)
            created = squad
            successTick += 1
        } catch {
            errorMessage = SquadHomeModel.message(for: error)
        }
    }

    private func createdContent(_ squad: SquadSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Text(style.emoji)
                    .font(.system(size: 44))
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(style.color.opacity(0.2)))
                    .overlay(Circle().strokeBorder(style.color.opacity(0.6), lineWidth: 1.5))
                    .accessibilityHidden(true)
                Text(model.backendConnected ? Copy.squad.createdTitle : Copy.squad.createdOfflineTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.squad.createdBody)
                    .zanoText(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            SquadInviteCodeCard(squad: squad, backendConnected: model.backendConnected)
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    // MARK: - Join

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(Copy.squad.joinBody)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField(Copy.squad.codePlaceholder, text: $code)
                .font(Theme.Typography.numeral(size: 34, weight: .heavy))
                .tracking(6)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.join)
                .focused($focusedField, equals: .code)
                .onChange(of: code) { _, new in
                    let cleaned = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if cleaned != new { code = cleaned }
                }
                .onSubmit { if code.count == 6 { Task { await join() } } }
                .padding(.vertical, Theme.Spacing.md)
                .zanoWell(radius: Theme.Radius.medium)
                .accessibilityLabel(Copy.squad.codeFieldLabel)
                .accessibilityIdentifier("squad.codeField")

            if !model.backendConnected {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityHidden(true)
                    Text(Copy.squad.joinOfflineNote)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PrimaryButton(
                title: model.backendConnected ? Copy.squad.joinButton : Copy.squad.joinOfflineButton,
                systemImage: "arrow.right.circle.fill",
                isEnabled: !isWorking && code.count == 6
            ) {
                Task { await join() }
            }
            .accessibilityIdentifier("squad.joinSubmit")
        }
        .onAppear { if initialMode == .join { focusedField = .code } }
    }

    private func join() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            joinResult = try await model.joinSquad(code: code)
            successTick += 1
        } catch {
            errorMessage = SquadHomeModel.message(for: error)
        }
    }

    private func joinedContent(_ result: SquadHomeModel.JoinOutcome) -> some View {
        let title: String
        let message: String
        switch result {
        case .joined(let squad):
            title = Copy.squad.joinedTitle(squadName: squad.name)
            message = Copy.squad.joinedBody
        case .savedForLater(let code):
            title = Copy.squad.offlineTitle
            message = Copy.squad.offlinePendingJoin(code)
        }
        return VStack(spacing: Theme.Spacing.md) {
            IconBadge(systemName: "person.2.fill", size: .large)
            Text(title)
                .zanoText(.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
            Text(message)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: Copy.squad.done) { dismiss() }
                .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .transition(.opacity)
    }
}
