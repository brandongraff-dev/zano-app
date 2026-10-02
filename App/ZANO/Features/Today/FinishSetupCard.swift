// FinishSetupCard.swift
// App / ZANO / Features / Today
//
// The post-onboarding "Finish setup" checklist on Today (docs/design/buildout-plan.md, Wave 1D):
// once the first lock has run, the things that make verification automatic instead of manual.
//
// Short flow (founder decision 2026-10-02): onboarding went from 15 screens to 7, and the optional
// setup topics it used to walk through live here instead, as a short list of one-tap next steps:
//   - from `TodayView` (unchanged call site): NFC tags, gym (only with a gym goal), Apple Health
//     (only with a steps / home-workout goal), the widget. TodayView decides whether each is done
//     and what it opens (`NFCTagsView`, `GymSetupView`, the Health primer, the widget how-to).
//   - added here: notifications (audit N2: before this, permission was only asked on the first-win
//     Start, so "Do it later" left the shield's Emergency button notification silently failing),
//     coach voice (onboarding no longer asks; the default stays Hype) and Sunrise alarm (onboarding
//     no longer asks; the wake time stays unset until this is saved). The squad item was removed
//     (founder decision 2026-10-02: squads are hidden for v1).
// Each item disappears once done, at most `maxVisibleItems` open items show at a time (the next one
// moves up as one is finished), and the whole card draws nothing when every item is done.
//
// Done-state for the items added here (read, never written by anything but the user's own action):
//   coach voice  the user picked one in the sheet below, or their `User.coachVoice` is not the
//                default (they picked one in Settings);
//   Sunrise      the Sunrise alarm settings row exists in the App Group store, which only happens
//                when its setup screen (or the Bedtime Gate's, which shares the row) is saved;
//   notifications  permission is granted (authorized / provisional / ephemeral). Tapping asks once
//                if never asked; if it was refused, it opens the app's page in the Settings app
//                (iOS can't show the prompt twice). Re-read whenever the scene becomes active.
//
// Also here: the widget how-to sheet the widget item opens (an app can't add a widget for the user),
// and the coach-voice sheet.

import SwiftUI
import SwiftData
import Core

struct FinishSetupItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let isDone: Bool
    let action: () -> Void
}

struct FinishSetupCard: View {
    /// Items `TodayView` builds (tags, gym, health, widget). The card adds its own after these.
    let items: [FinishSetupItem]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query private var users: [User]

    @AppStorage("finishSetup.coachVoicePicked.v1") private var coachVoicePicked = false
    /// `nil` until read on appear.
    @State private var sunriseConfigured: Bool?
    @State private var notificationStatus: NotificationPermission.Status?
    @State private var showsCoachVoice = false
    @State private var showsSunrise = false

    /// Same signature `TodayView` already calls (`FinishSetupCard(items:onDismiss:)`).
    init(items: [FinishSetupItem], onDismiss: @escaping () -> Void) {
        self.items = items
        self.onDismiss = onDismiss
    }

    /// "A short checklist": never more than this many open items at once.
    static let maxVisibleItems = 5

    /// Display order, by id. Ids not listed (a future item from TodayView) go last.
    private static let order = ["notifications", "tags", "gym", "health", "voice", "sunrise", "widget"]

    private var allItems: [FinishSetupItem] {
        let merged = items + ownItems
        return merged.sorted { lhs, rhs in
            (Self.order.firstIndex(of: lhs.id) ?? Self.order.count) < (Self.order.firstIndex(of: rhs.id) ?? Self.order.count)
        }
    }

    /// The open items on show: done ones are hidden, and only the first `maxVisibleItems`.
    private var visibleItems: [FinishSetupItem] {
        Array(allItems.filter { !$0.isDone }.prefix(Self.maxVisibleItems))
    }

    private var ownItems: [FinishSetupItem] {
        var result: [FinishSetupItem] = []
        // Wait for the read so the item never flashes in and straight back out.
        if let notificationStatus {
            result.append(FinishSetupItem(
                id: "notifications",
                icon: "bell.badge.fill",
                title: Copy.onboarding.finishSetupNotificationsTitle,
                detail: notificationStatus == .denied
                    ? Copy.onboarding.finishSetupNotificationsDeniedDetail
                    : Copy.onboarding.finishSetupNotificationsDetail,
                isDone: notificationStatus == .allowed,
                action: { tapped("notifications") { turnOnNotifications() } }
            ))
        }
        result.append(
            FinishSetupItem(
                id: "voice",
                icon: OnboardingKit.icon(for: currentVoice),
                title: Copy.onboarding.finishSetupVoiceTitle,
                detail: Copy.onboarding.finishSetupVoiceDetail,
                isDone: coachVoicePicked || currentVoice != .hype,
                action: { tapped("voice") { showsCoachVoice = true } }
            )
        )
        // Wait for the reads so an item never flashes in and straight back out.
        if let sunriseConfigured {
            result.append(FinishSetupItem(
                id: "sunrise",
                icon: "sunrise.fill",
                title: Copy.onboarding.finishSetupSunriseTitle,
                detail: Copy.onboarding.finishSetupSunriseDetail,
                isDone: sunriseConfigured,
                action: { tapped("sunrise") { showsSunrise = true } }
            ))
        }
        return result
    }

    private var currentVoice: CoachVoice {
        users.first?.coachVoice ?? .hype
    }

    var body: some View {
        let all = allItems
        let shown = visibleItems
        let doneCount = all.filter(\.isDone).count
        // A VStack, not a Group, so `.task` runs even while nothing is on show yet.
        VStack(spacing: 0) {
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(Copy.today.setupCardTitle)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.text)
                            .accessibilityAddTraits(.isHeader)
                        Text(Copy.today.setupCardProgress(done: doneCount, total: all.count))
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.muted)
                            .monospacedDigit()
                        Spacer(minLength: Theme.Spacing.sm)
                        Button(action: onDismiss) {
                            Text(Copy.today.setupCardDismiss)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.muted)
                                .frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable(scale: 0.94))
                        .accessibilityLabel(Copy.today.setupCardDismissSpoken)
                    }
                    .padding(.leading, Theme.Spacing.xxs)

                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(Theme.Colors.hairline)
                                    .frame(height: Theme.Metrics.edgeWidth)
                                    .padding(.leading, Theme.Spacing.md + 32 + Theme.Spacing.sm)
                            }
                            FinishSetupRow(item: item)
                                .transition(.opacity)
                        }
                    }
                    .zanoCard(radius: Theme.Radius.medium)
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: doneCount)
        .task(id: scenePhase) {
            // Also on returning from the Settings app, where notifications may have been turned on.
            guard scenePhase == .active else { return }
            await refreshOwnStatus()
        }
        .sheet(isPresented: $showsCoachVoice) {
            CoachVoiceSetupSheet {
                coachVoicePicked = true
            }
        }
        .sheet(isPresented: $showsSunrise, onDismiss: {
            Task { await refreshOwnStatus() }
        }) {
            NavigationStack { SunriseAlarmSetupView() }
                .preferredColorScheme(.dark)
        }
    }

    private func tapped(_ item: String, open: () -> Void) {
        Analytics.shared.capture(event: "today_finish_setup_item_tapped", properties: ["item": item])
        open()
    }

    private func refreshOwnStatus() async {
        sunriseConfigured = Self.isSunriseAlarmConfigured()
        notificationStatus = await NotificationPermission.status()
    }

    /// Never asked: the system prompt. Refused: the app's page in Settings (the prompt can't show
    /// twice). The row re-reads the status when the scene becomes active again.
    private func turnOnNotifications() {
        Task {
            if notificationStatus == .denied {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
                return
            }
            notificationStatus = await NotificationPermission.requestIfUndetermined()
            Analytics.shared.capture(
                event: "finish_setup_notifications_answered",
                properties: ["allowed": notificationStatus == .allowed]
            )
        }
    }

    /// Whether the Sunrise alarm settings row has ever been saved. The key is the identifier
    /// `SunriseAlarmManager` stores its settings under in the App Group defaults (an identifier, not
    /// copy); Core exposes no "has been configured" flag yet.
    private static func isSunriseAlarmConfigured() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        return defaults.data(forKey: "core.sunriseAlarm.settings.v1") != nil
    }
}

private struct FinishSetupRow: View {
    let item: FinishSetupItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: item.isDone ? "checkmark" : item.icon)
                    .font(Theme.Typography.icon(.small, weight: .bold))
                    .foregroundStyle(item.isDone ? Theme.Colors.onAccent : Theme.Colors.accent)
                    .frame(width: 32, height: 32)
                    .background(item.isDone ? Theme.Colors.accent : Theme.Colors.accentWash, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(item.isDone ? Theme.Colors.muted : Theme.Colors.text)
                        .strikethrough(item.isDone, color: Theme.Colors.muted)
                    Text(item.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if !item.isDone {
                    Image(systemName: "chevron.forward")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(item.isDone)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? Copy.today.statusDone : "")
    }
}

// MARK: - Coach voice sheet

/// The coach-voice choice onboarding used to ask: the four voices with their sample lines. Saves to
/// the local `User` row and the App Group mirror the extensions read, the same two writes Settings
/// makes. `onPicked` runs after a successful save.
private struct CoachVoiceSetupSheet: View {
    let onPicked: () -> Void

    init(onPicked: @escaping () -> Void) {
        self.onPicked = onPicked
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    private var selected: CoachVoice {
        users.first?.coachVoice ?? .hype
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Copy.onboarding.finishSetupVoiceSheetTitle)
                        .font(Theme.Typography.titleLarge)
                        .foregroundStyle(Theme.Colors.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(Copy.onboarding.finishSetupVoiceSheetSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(CoachVoice.allCases, id: \.rawValue) { voice in
                    SelectableCard(
                        title: voice.displayName,
                        subtitle: voice.sampleLine,
                        icon: OnboardingKit.icon(for: voice),
                        isSelected: selected == voice
                    ) {
                        select(voice)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.done) { dismiss() }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
        }
        // v2: the aurora canvas, like every screen.
        .zanoBackdrop()
        .sensoryFeedback(.selection, trigger: selected)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func select(_ voice: CoachVoice) {
        guard let user = users.first else { return }
        user.coachVoice = voice
        do {
            try modelContext.save()
            SharedDefaults.coachVoice = voice.rawValue
            Analytics.shared.capture(event: "finish_setup_coach_voice_picked", properties: ["voice": voice.rawValue])
            onPicked()
        } catch {
            // Nothing saved; the selection simply doesn't move. Settings offers the same choice.
        }
    }
}

/// How to add the ZANO widget. Apps can't place a widget themselves, so this is the three steps.
struct WidgetHowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(Copy.today.widgetHowToTitle)
                .font(Theme.Typography.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(Copy.today.widgetHowToSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("\(index + 1)")
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.accentWash, in: Circle())
                        .accessibilityHidden(true)
                    Text(step)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            PrimaryButton(title: Copy.today.widgetHowToDone) { dismiss() }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // v2: the aurora canvas, like every screen.
        .zanoBackdrop()
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
