// AppPickerView.swift
// App / Features / LockSetup
//
// docs/spec.md §4 (v1 — Launch): "App picker (FamilyActivityPicker) with saved 'lock sets' (e.g.,
// Social, Games, All)." §11 Architecture lists `FamilyControls, ManagedSettings, DeviceActivity` as
// the only frameworks that ever see real app identity, and both §11's data flow note and
// `Core/Sources/Core/Models/LockSet.swift`'s header comment are explicit that the resulting tokens
// "never leave the device." This view respects that boundary structurally: it only ever hands a
// `FamilyActivitySelection` value back to its caller through a `Binding` — it never encodes,
// persists, logs, or inspects the tokens inside it. Persisting a selection onto a named `LockSet`
// (encoding it into `LockSet.appTokensBlob`) is `LockSetManager`'s job, not this view's.
//
// Visual pass (design wave 2026-09-23; `docs/design/composition-audit.md` offender 7 and
// `docs/design/better-layout-findings.md` row 1.8): the highest-stakes choice in lock setup used to
// be a stock `LabeledContent` row ("Select apps ....... 3 apps") inside a `Form` `Section`, with no
// preview of what would actually be shielded. It is now a card that shows the picked apps. The card
// is the shared `zanoCard`, presses with the shared `PressableStyle`, and the picked-app tiles carry a
// hairline edge (a `surface2` tile on a `surface` card is 1.08:1, so an app icon with a dark artwork
// had no visible slot).
//
// Showing the apps uses FamilyControls' own privacy-preserving `Label(token)` (system-rendered, so
// the token-privacy rule above still holds: this app never reads a bundle id or display name off a
// token). Two documented limits of that API shape the design (Apple Developer Forums thread 731387):
// the icon is only about 25pt and cannot be upscaled without blurring, so icons sit at natural size
// inside a 40pt tile instead of being scaled up; and `Label(token)` for categories and web domains
// is the same initializer family. NOT VERIFIED ON A DEVICE (no Mac in this environment): the three
// `Label(token)` call sites in `ActivityTokenTile` and how the icon-only style sizes inside the tile.
//
// `body` is not a `Section`; this view is placed inside a `ScrollView`/`VStack` (`LockSetEditorSheet`
// in `LockSetupView.swift` is its only call site).

import SwiftUI
import FamilyControls
// Named explicitly, like `Screen4AppSelection`/`Screen10PlanReveal` do for the same `Label(token)` use:
// `ApplicationToken` / `ActivityCategoryToken` / `WebDomainToken` (ManagedSettings) and the token
// `Label` initializers (ManagedSettingsUI) are used below, and this file should not depend on
// `FamilyControls` happening to re-export them.
import ManagedSettings
import ManagedSettingsUI
import Core

// MARK: - Shared picked-item model (also used by LockSetupView's row icons)

/// One picked app, category, or website, flattened so the row/strip views below can iterate a single
/// `ForEach`. Not copy and not persisted; a transient view-model value over the opaque tokens.
enum PickedActivityItem: Hashable, Identifiable {
    case app(ApplicationToken)
    case category(ActivityCategoryToken)
    case web(WebDomainToken)

    var id: PickedActivityItem { self }
}

extension FamilyActivitySelection {
    /// Apps first, then categories, then websites. Tokens are opaque and unordered, so each group is
    /// sorted by hash: not meaningful, but stable for the life of the process, which is what stops the
    /// icon strip reshuffling on every SwiftUI re-render (a `Set`'s own order is stable per instance,
    /// but a fresh decode of a `LockSet` blob on each row render is a new instance).
    var pickedActivityItems: [PickedActivityItem] {
        let apps = applicationTokens
            .sorted { $0.hashValue < $1.hashValue }
            .map { PickedActivityItem.app($0) }
        let categories = categoryTokens
            .sorted { $0.hashValue < $1.hashValue }
            .map { PickedActivityItem.category($0) }
        let sites = webDomainTokens
            .sorted { $0.hashValue < $1.hashValue }
            .map { PickedActivityItem.web($0) }
        return apps + categories + sites
    }

    /// "3 apps, 1 category", or `Copy.lockSetup.noAppsSelected` when nothing is picked. One place
    /// for the summary that the lock-set rows, the picker card and its VoiceOver value all show.
    var lockSetupSummary: String {
        let appCount = applicationTokens.count
        let categoryCount = categoryTokens.count
        let webDomainCount = webDomainTokens.count
        guard appCount + categoryCount + webDomainCount > 0 else {
            return Copy.lockSetup.noAppsSelected
        }
        return Copy.lockSetup.selectionSummary(
            appCount: appCount,
            categoryCount: categoryCount,
            webDomainCount: webDomainCount
        )
    }
}

/// One picked item as a rounded-square tile. `Theme.Radius.small` (12) on a 40pt tile puts the
/// tile corner at 30% of its side, close to an app icon's own squircle, and the icon inside sits
/// roughly 7pt in, which makes the two corners concentric (`docs/design/better-ui-findings.md`
/// section 2.4). The hairline edge gives the slot a visible boundary on a `surface` card.
struct ActivityTokenTile: View {
    let item: PickedActivityItem
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Colors.surface2)
            icon
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let token):
            Label(token).labelStyle(.iconOnly)
        case .category(let token):
            Label(token).labelStyle(.iconOnly)
        case .web(let token):
            Label(token).labelStyle(.iconOnly)
        }
    }
}

/// The "+N" tile that stands in for every item past the visible ones, same footprint and edge as
/// `ActivityTokenTile` (the strip here and the row icon stack in `LockSetupView` each used to draw
/// their own copy).
struct ActivityOverflowTile: View {
    let count: Int
    var size: CGFloat = 40

    var body: some View {
        Text("+\(count)")
            .font(Theme.Typography.numeralSmall())
            .foregroundStyle(Theme.Colors.muted)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(
                Theme.Colors.surface2,
                in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Picker card

/// Reusable control for choosing which apps / activity categories / web domains belong to a
/// `LockSet`. Wraps FamilyControls' system `FamilyActivityPicker` behind a single card: tapping it
/// requests Screen Time authorization if needed (docs/spec.md §24: "Family Controls entitlement...
/// apply to Apple on day one"; until that's approved, the **Family Controls (Development)**
/// capability covers real-device testing per CLAUDE.md's environment-status block), then presents
/// the system picker sheet via `.familyActivityPicker(isPresented:selection:)`.
struct AppPickerView: View {
    /// The selection being built or edited. Owned by the caller so this view stays ignorant of
    /// persistence — the caller is typically about to hand this straight to `LockSetManager`.
    @Binding var selection: FamilyActivitySelection

    @State private var isPickerPresented = false
    @State private var authorizationAlert: AuthorizationAlert?

    /// How many item tiles fit on one line inside the card's 16pt padding on the narrowest supported
    /// phone (375pt): 5 tiles + the overflow tile = 6 x 40 + 5 x 8 = 280pt of 311pt available.
    private static let maxTiles = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                Task { await requestAuthorizationThenPresentPicker() }
            } label: {
                pickerCard
            }
            .buttonStyle(.pressable)
            // One VoiceOver element: the row title and its value. The token tiles are decorative
            // (and, being system-rendered tokens, VoiceOver cannot name them for us).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.lockSetup.selectAppsButtonLabel)
            .accessibilityValue(selection.lockSetupSummary)
            .accessibilityAddTraits(.isButton)

            Text(Copy.lockSetup.appPickerFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .alert(
            authorizationAlert?.title ?? "",
            isPresented: Binding(
                get: { authorizationAlert != nil },
                set: { isPresented in
                    if !isPresented { authorizationAlert = nil }
                }
            ),
            presenting: authorizationAlert
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { authorizationAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: Card

    private var pickedItems: [PickedActivityItem] {
        selection.pickedActivityItems
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.lockSetup.selectAppsButtonLabel)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(selection.lockSetupSummary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.sm)
                // `chevron.forward`, not `chevron.right`, so it mirrors in RTL locales.
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
            }

            if pickedItems.isEmpty {
                emptyDropZone
            } else {
                pickedStrip
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    /// Dashed outline with a plus: an empty slot that reads as "put apps here" rather than a blank
    /// gap (`docs/design/competitive-research.md` 3.10: an empty state should invite, not look like a
    /// rendering bug). Decorative; the row's own accessibility label carries the meaning.
    private var emptyDropZone: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .strokeBorder(
                Theme.Colors.hairlineStrong,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
            )
            .frame(height: Theme.Metrics.minTapTarget + Theme.Spacing.md)
            .overlay {
                Image(systemName: "plus")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .accessibilityHidden(true)
    }

    private var pickedStrip: some View {
        let visible = Array(pickedItems.prefix(Self.maxTiles))
        let overflow = pickedItems.count - visible.count
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(visible) { item in
                ActivityTokenTile(item: item)
            }
            if overflow > 0 {
                ActivityOverflowTile(count: overflow)
            }
            Spacer(minLength: 0)
        }
    }

    /// FamilyControls authorization gates everything the picker can show: with no authorization
    /// (or a denied one) `FamilyActivityPicker` still opens but silently shows nothing selectable,
    /// which reads as a bug rather than a permissions problem — so this checks/requests first and
    /// only presents the system sheet once `.approved`, showing our own alert otherwise.
    ///
    /// `.individual` (not `.child`) is the correct `FamilyControlsMember` here: ZANO restricts the
    /// signed-in user's own device, it is never a parent managing a child's device.
    private func requestAuthorizationThenPresentPicker() async {
        let center = AuthorizationCenter.shared

        if center.authorizationStatus == .notDetermined {
            do {
                try await center.requestAuthorization(for: .individual)
            } catch {
                authorizationAlert = AuthorizationAlert(
                    title: Copy.lockSetup.authorizationErrorTitle,
                    message: Copy.lockSetup.authorizationErrorMessage
                )
                return
            }
        }

        switch center.authorizationStatus {
        case .approved:
            isPickerPresented = true
        case .denied, .notDetermined:
            authorizationAlert = AuthorizationAlert(
                title: Copy.lockSetup.authorizationDeniedTitle,
                message: Copy.lockSetup.authorizationDeniedMessage
            )
        @unknown default:
            isPickerPresented = true
        }
    }
}

/// File-scoped alert payload — plain `Identifiable` glue for SwiftUI's `.alert(_:isPresented:
/// presenting:actions:message:)`, not a shared model.
private struct AuthorizationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    AppPickerPreviewContainer()
}

private struct AppPickerPreviewContainer: View {
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        ScrollView {
            AppPickerView(selection: $selection)
                .padding(Theme.Spacing.md)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
    }
}
