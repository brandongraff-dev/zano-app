// SuggestionCard.swift
// App / ZANO / Features / Today / Suggestions
//
// The shared shape of every Today suggestion card: an icon, one headline, one line, an optional
// small accessory (a chip, a ramp, a progress bar), one primary action, and a close glyph ("Not
// today" to VoiceOver). v2: on tinted glass. The six
// card files only fill it in. Strings come from `Copy.today`; the card composes none.

import SwiftUI
import Core

struct SuggestionCard<Accessory: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    /// `nil` hides the button (e.g. Plan B waiting on Health to catch up).
    let actionTitle: String?
    var actionIcon: String? = nil
    var isBusy: Bool = false
    let onAction: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: icon, tint: tint, size: .small)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                // v2: a glass close glyph instead of the words "Not today" (still spoken).
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(width: 30, height: 30)
                        .background(ZanoGlass(Circle()))
                        .minTapTarget()
                }
                .buttonStyle(.pressable(scale: 0.94))
                .accessibilityLabel(Copy.today.suggestionDismissSpoken(title))
            }

            accessory()

            if let actionTitle {
                PrimaryButton(
                    title: actionTitle,
                    systemImage: actionIcon,
                    style: .secondary,
                    isEnabled: !isBusy,
                    action: onAction
                )
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard(radius: Theme.Radius.medium, tint: reduceTransparency ? nil : tint)
    }
}

extension SuggestionCard where Accessory == EmptyView {
    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        actionTitle: String?,
        actionIcon: String? = nil,
        isBusy: Bool = false,
        onAction: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.isBusy = isBusy
        self.onAction = onAction
        self.onDismiss = onDismiss
        self.accessory = { EmptyView() }
    }
}

/// A small capsule under the card's line ("1 freeze left").
struct SuggestionChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs + 2)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: Theme.Metrics.edgeWidth))
    }
}
