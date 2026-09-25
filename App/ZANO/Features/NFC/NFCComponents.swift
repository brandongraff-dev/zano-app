// NFCComponents.swift
// App / ZANO / Features / NFC
//
// Small pieces shared by the NFC screens: section/card/row chrome (Settings' equivalents are
// `private` to `SettingsView.swift`), labels and glyphs for tag kinds and actions, and
// `TagTapScene`, the phone-meets-tag illustration used by the write flow, the unmapped-tag prompt
// and Lock Card setup (the onboarding one in `Screen9NFCTags.swift` is file-private and scripted;
// this one is state-driven so it can show progress, success and failure).

import SwiftUI
import Core

// MARK: - Kind / action presentation

extension NFCTagKind {
    var nfcLabel: String {
        switch self {
        case .sunrise: Copy.nfc.kindSunrise
        case .bottle: Copy.nfc.kindBottle
        case .shaker: Copy.nfc.kindShaker
        case .desk: Copy.nfc.kindDesk
        case .gymBag: Copy.nfc.kindGymBag
        case .lockCard: Copy.nfc.kindLockCard
        case .custom: Copy.nfc.kindCustom
        }
    }

    var nfcSymbol: String {
        switch self {
        case .sunrise: "sunrise"
        case .bottle: "drop"
        case .shaker: "takeoutbag.and.cup.and.straw"
        case .desk: "desktopcomputer"
        case .gymBag: "dumbbell"
        case .lockCard: "creditcard"
        case .custom: "wave.3.right"
        }
    }
}

/// The action choices the map sheet offers, one per `NFCTagAction` case (payloads are edited
/// separately in the sheet).
enum NFCActionChoice: String, CaseIterable, Identifiable, Hashable {
    case logProtein, logWater, logCreatine, startFocus, gymCheckIn, startLock, lockCardToggle, sunriseKey, logCustomGoal

    var id: String { rawValue }

    init(_ action: NFCTagAction) {
        switch action {
        case .logProtein: self = .logProtein
        case .logWater: self = .logWater
        case .logCreatine: self = .logCreatine
        case .startFocus: self = .startFocus
        case .gymCheckIn: self = .gymCheckIn
        case .startLock: self = .startLock
        case .lockCardToggle: self = .lockCardToggle
        case .sunriseKey: self = .sunriseKey
        case .logCustomGoal: self = .logCustomGoal
        }
    }

    var title: String {
        switch self {
        case .logProtein: Copy.nfc.actionLogProtein
        case .logWater: Copy.nfc.actionLogWater
        case .logCreatine: Copy.nfc.actionLogCreatine
        case .startFocus: Copy.nfc.actionStartFocus
        case .gymCheckIn: Copy.nfc.actionGymCheckIn
        case .startLock: Copy.nfc.actionStartLock
        case .lockCardToggle: Copy.nfc.actionLockCard
        case .sunriseKey: Copy.nfc.actionSunriseKey
        case .logCustomGoal: Copy.nfc.actionCustomGoal
        }
    }

    var detail: String {
        switch self {
        case .logProtein: Copy.nfc.actionLogProteinDetail
        case .logWater: Copy.nfc.actionLogWaterDetail
        case .logCreatine: Copy.nfc.actionLogCreatineDetail
        case .startFocus: Copy.nfc.actionStartFocusDetail
        case .gymCheckIn: Copy.nfc.actionGymCheckInDetail
        case .startLock: Copy.nfc.actionStartLockDetail
        case .lockCardToggle: Copy.nfc.actionLockCardDetail
        case .sunriseKey: Copy.nfc.actionSunriseKeyDetail
        case .logCustomGoal: Copy.nfc.actionCustomGoalDetail
        }
    }

    /// Same glyphs the rest of the app uses for these goals (`drop.fill` water, `fork.knife`
    /// protein, `sunrise.fill` alarm).
    var symbol: String {
        switch self {
        case .logProtein: "fork.knife"
        case .logWater: "drop.fill"
        case .logCreatine: "pills.fill"
        case .startFocus: "timer"
        case .gymCheckIn: "dumbbell.fill"
        case .startLock: "lock.fill"
        case .lockCardToggle: "creditcard.fill"
        case .sunriseKey: "sunrise.fill"
        case .logCustomGoal: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .logProtein: Theme.Colors.Ring.protein
        case .logWater: Theme.Colors.Ring.water
        case .logCreatine: Theme.Colors.Ring.creatine
        case .startFocus: Theme.Colors.Ring.focus
        case .gymCheckIn: Theme.Colors.Ring.workout
        case .startLock, .lockCardToggle: Theme.Colors.accent
        case .sunriseKey: Theme.Colors.Ring.sunriseAlarm
        case .logCustomGoal: Theme.Colors.textSecondary
        }
    }
}

extension NFCTagAction {
    /// "Log protein · 25 g", "Start focus · 25 min", "Log a goal · Cold shower".
    /// `goalTitle` resolves a custom goal's name (the mapping only stores its id).
    func nfcSummary(goalTitle: String? = nil) -> String {
        let choice = NFCActionChoice(self)
        switch self {
        case .logProtein(let grams):
            return Copy.nfc.summary(action: choice.title, detail: Copy.nfc.proteinAmount(grams: grams))
        case .logWater(let ml):
            return Copy.nfc.summary(action: choice.title, detail: Copy.nfc.waterAmount(milliliters: ml))
        case .startFocus(let minutes):
            return Copy.nfc.summary(action: choice.title, detail: Copy.nfc.focusLength(minutes: minutes))
        case .logCustomGoal:
            if let goalTitle { return Copy.nfc.summary(action: choice.title, detail: goalTitle) }
            return choice.title
        case .startLock, .logCreatine, .sunriseKey, .gymCheckIn, .lockCardToggle:
            return choice.title
        }
    }
}

extension NFCTagMapping {
    /// The tag's own label, or "this tag" when it was saved without one.
    var nfcDisplayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Copy.nfc.unnamedTagLabel : trimmed
    }
}

extension NFCTagTapEffect {
    /// The toast line for this effect.
    var toastText: String {
        switch self {
        case .loggedWater(let ml): Copy.nfc.toastWater(milliliters: ml)
        case .loggedProtein(let grams): Copy.nfc.toastProtein(grams: grams)
        case .loggedCreatine: Copy.nfc.toastCreatine
        case .sunriseKey: Copy.nfc.toastSunrise
        case .lockStarted: Copy.nfc.toastLockStarted
        case .lockStatus(let remaining): Copy.nfc.toastLockStatus(goalsRemaining: remaining)
        case .focusStarted(let minutes): Copy.nfc.toastFocusStarted(minutes: minutes)
        case .gymCheckInStarted: Copy.nfc.toastGymCheckIn
        case .loggedCustomGoal(let title): Copy.nfc.toastCustomGoal(title: title)
        }
    }

    var toastSymbol: String {
        switch self {
        case .loggedWater: "drop.fill"
        case .loggedProtein: "fork.knife"
        case .loggedCreatine: "pills.fill"
        case .sunriseKey: "sunrise.fill"
        case .lockStarted, .lockStatus: "lock.fill"
        case .focusStarted: "timer"
        case .gymCheckInStarted: "dumbbell.fill"
        case .loggedCustomGoal: "checkmark.circle.fill"
        }
    }
}

// MARK: - Chrome

/// Section title + content + optional footer, matching Settings' section rhythm.
struct NFCSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            content
            if let footer {
                Text(footer)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xxs)
            }
        }
    }
}

/// A selectable row: glyph, title, detail, and a check when selected.
struct NFCChoiceRow: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var tint: Color = Theme.Colors.accent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    IconBadge(systemName: systemImage, tint: tint, size: .small)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    if let detail {
                        Text(detail)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.hairlineStrong)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A compact tile for the placement grid.
struct NFCKindTile: View {
    let kind: NFCTagKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: kind.nfcSymbol)
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(height: 28)
                    .accessibilityHidden(true)
                Text(kind.nfcLabel)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, Theme.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isSelected ? Theme.Colors.accentWash : Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent : Theme.Colors.hairline,
                        lineWidth: isSelected ? Theme.Metrics.selectedStroke : Theme.Metrics.edgeWidth
                    )
            )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Hairline between rows inside a card.
struct NFCRowDivider: View {
    var inset: CGFloat = Theme.Spacing.md

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// Numbered step (1, 2, 3) with a title and optional detail.
struct NFCStepRow: View {
    let number: Int
    let title: String
    var detail: String?
    var isDone = false

    @ScaledMetric(relativeTo: .footnote) private var badge: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(isDone ? Theme.Colors.accentFill : Theme.Colors.surface2)
                Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                } else {
                    Text("\(number)")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                }
            }
            .frame(width: badge, height: badge)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                if let detail {
                    Text(detail)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An inline caution line (missing gym, no eligible goals...).
struct NFCNotice: View {
    let text: String
    var systemImage = "exclamationmark.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.warning)
                .accessibilityHidden(true)
            Text(text)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoWell()
    }
}

// MARK: - TagTapScene

/// A phone lowering onto a silver ZANO tag with blue read waves. State-driven:
/// `.idle` breathes slowly, `.active` pulses fast (scan in progress), `.success` lands a check,
/// `.failure` shows a quiet cross. Decorative; the text beside it carries the meaning.
struct TagTapScene: View {
    enum Phase: Equatable {
        case idle, active, success, failure
    }

    var phase: Phase = .idle
    /// `.card` draws the Lock Card instead of a round sticker.
    var style: Style = .sticker

    enum Style { case sticker, card }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 220, height: 180)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || phase == .success || phase == .failure)) { context in
            scene(time: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size.width, height: size.height)
        .animation(Theme.Motion.springStandard, value: phase)
        .sensoryFeedback(trigger: phase) { _, new -> SensoryFeedback? in
            switch new {
            case .success: return .success
            case .failure: return .error
            case .active: return .impact(flexibility: .soft, intensity: 0.5)
            case .idle: return nil
            }
        }
        .accessibilityHidden(true)
    }

    private func scene(time: TimeInterval) -> some View {
        let tagCenter = CGPoint(x: size.width / 2, y: size.height * 0.64)
        let period: Double = phase == .active ? 1.1 : 2.4
        let phoneDown: CGFloat = (phase == .idle && !reduceMotion) ? CGFloat((sin(time * 2 * .pi / 3.2) + 1) / 2) : 1

        return ZStack {
            // Read waves.
            ForEach(0..<3, id: \.self) { index in
                let local = reduceMotion || phase == .success || phase == .failure
                    ? Double(index) / 3 + 0.2
                    : ((time / period) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(waveColor, lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                    .scaleEffect(1 + local * 1.4)
                    .opacity(phase == .failure ? 0.12 : (1 - local) * 0.8)
                    .position(tagCenter)
            }

            tagBody
                .position(tagCenter)
                .shadow(color: Theme.Colors.accent.opacity(phase == .active || phase == .success ? 0.55 : 0.2), radius: 16)

            phone
                .frame(width: 66, height: 120)
                .rotationEffect(.degrees(-8))
                .position(x: tagCenter.x + 30, y: tagCenter.y - 70 - 22 * (1 - phoneDown))
                .opacity(phase == .success ? 0.35 : 1)

            if phase == .success || phase == .failure {
                resultBadge
                    .position(x: tagCenter.x + 36, y: tagCenter.y - 30)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var waveColor: Color {
        phase == .failure ? Theme.Colors.muted : Theme.Colors.accent
    }

    @ViewBuilder
    private var tagBody: some View {
        switch style {
        case .sticker:
            ZStack {
                Circle().fill(Theme.Colors.metallic)
                Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1).padding(5)
                ZanoMark(height: 24, style: .mono(Theme.Colors.background.opacity(0.82)))
            }
            .frame(width: 64, height: 64)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.75))
        case .card:
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            ZStack(alignment: .bottomLeading) {
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                ZanoMark(height: 16, style: .brand)
                    .padding(10)
            }
            .frame(width: 118, height: 75)
            .overlay(shape.strokeBorder(Theme.Colors.edgeGradient(), lineWidth: 1))
            .rotation3DEffect(.degrees(48), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        }
    }

    private var phone: some View {
        let outer = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .top) {
            outer.fill(
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Theme.Colors.lockedAmbient, Theme.Colors.background], startPoint: .top, endPoint: .bottom))
                .padding(3)
            Capsule().fill(Color.black).frame(width: 18, height: 5).padding(.top, 8)
        }
        .overlay(outer.strokeBorder(Theme.Colors.edgeGradient(), lineWidth: 1))
        .shadow(color: Theme.Colors.shadow, radius: 10, y: 6)
    }

    private var resultBadge: some View {
        Image(systemName: phase == .success ? "checkmark" : "xmark")
            .font(Theme.Typography.icon(.small, weight: .bold))
            .foregroundStyle(phase == .success ? Theme.Colors.onAccent : Theme.Colors.text)
            .frame(width: 30, height: 30)
            .background(phase == .success ? Theme.Colors.accentFill : Theme.Colors.surface2, in: Circle())
            .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 2))
    }
}
