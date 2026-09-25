// FinishSetupCard.swift
// App / ZANO / Features / Today
//
// The post-onboarding "Finish setup" checklist on Today (docs/design/buildout-plan.md, Wave 1D):
// once the first lock has run, the things that make verification automatic instead of manual (NFC
// tags, a saved gym, Apple Health, the widget). `TodayView` decides which items apply (a gym item
// only with a gym goal, Health only with a steps or home-workout goal), whether each is done, and
// what each opens; this file only draws them. The card disappears when every item is done, or for
// good when hidden.
//
// Also here: the widget how-to sheet the widget item opens (an app can't add a widget for the user).

import SwiftUI
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
    let items: [FinishSetupItem]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let doneCount = items.filter(\.isDone).count
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(Copy.today.setupCardTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.today.setupCardProgress(done: doneCount, total: items.count))
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
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.Colors.hairline)
                            .frame(height: Theme.Metrics.edgeWidth)
                            .padding(.leading, Theme.Spacing.md + 32 + Theme.Spacing.sm)
                    }
                    FinishSetupRow(item: item)
                }
            }
            .zanoCard()
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: doneCount)
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
        .background(Theme.Colors.background)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
