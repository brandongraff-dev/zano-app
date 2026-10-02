import SwiftUI
import Core

// The floating glass tab bar, v2 (docs/design/visual-direction-v2.md §4, founder feedback 2026-10-02:
// "a much cleaner glassmorphic bottom nav bar"). One chrome-glass capsule floating over the content,
// five icon-only tabs. The selected tab grows a liquid blue pill that slides between tabs
// (`matchedGeometryEffect` on `Theme.Motion.tabPill`) and reveals the tab's name; unselected tabs are
// a glyph only. Squad is hidden for v1 (`AppTab.squad` and its screens stay compiled, unreachable).
//
// Accessibility: the bar is one container ("zano.tabBar") of buttons whose accessibility labels are
// the tab titles (the UI tests query `zanoTabBar.buttons[title]`), the selected one carrying
// `.isSelected`. Labels are hidden visually on unselected tabs, never from VoiceOver, and every item
// offers the Large Content Viewer since the bar can't grow with Dynamic Type.
//
// Width on the narrowest phone: iPhone SE is 320pt, minus the 16pt gutters `MainTabView` pads the bar
// with and this bar's 6pt inner padding, leaves 276pt. Four glyph items at 44pt (176pt) plus spacing
// leave ~92pt for the pill: an icon and up to "Settings" at 15pt rounded semibold, which may shrink to
// 80% before truncating.
//
// `.isTabBar` is not added to the container: its SwiftUI availability on the iOS 17 target is
// unverified here, and a wrong trait would change what the UI tests' query sees.

struct ZanoTabBar: View {
    @Binding var selection: AppTab
    /// A lock is running: the Lock item carries a small dot and says so to VoiceOver.
    var isLockActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    /// Space each tab reserves at the bottom so its content and bottom bars clear the capsule.
    static let reservedHeight: CGFloat = 80

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let symbol: String
        let selectedSymbol: String
        var id: AppTab { tab }
    }

    private let items: [Item] = [
        Item(tab: .today, title: Copy.today.screenTitle, symbol: "sparkle", selectedSymbol: "sparkle"),
        Item(tab: .lock, title: Copy.lockStatus.screenTitle, symbol: "lock", selectedSymbol: "lock.fill"),
        Item(tab: .fuel, title: Copy.fuel.screenTitle, symbol: "fork.knife", selectedSymbol: "fork.knife"),
        Item(tab: .progress, title: Copy.progress.screenTitle, symbol: "chart.bar", selectedSymbol: "chart.bar.fill"),
        Item(tab: .settings, title: Copy.settings.screenTitle, symbol: "gearshape", selectedSymbol: "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                button(for: item)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Theme.Metrics.tabBarHeight)
        .background(ZanoGlass(Capsule(style: .continuous)))
        .shadow(color: Theme.Colors.shadow, radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zano.tabBar")
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func button(for item: Item) -> some View {
        let isSelected = selection == item.tab
        let showsLockDot = item.tab == .lock && isLockActive
        return Button {
            guard selection != item.tab else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.tabPill) {
                selection = item.tab
            }
        } label: {
            itemLabel(item, isSelected: isSelected, showsLockDot: showsLockDot)
        }
        .buttonStyle(.pressable(scale: 0.92))
        // Selected: as wide as its pill needs; unselected: share what's left.
        .layoutPriority(isSelected ? 1 : 0)
        .accessibilityLabel(item.title)
        .accessibilityValue(showsLockDot ? Copy.lockStatus.tabLockRunningValue : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(item.title, systemImage: item.symbol)
        }
    }

    @ViewBuilder
    private func itemLabel(_ item: Item, isSelected: Bool, showsLockDot: Bool) -> some View {
        if isSelected {
            HStack(spacing: Theme.Spacing.xs - 2) {
                glyph(item, isSelected: true, showsLockDot: showsLockDot)
                Text(item.title)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Metrics.tabBarItem)
            .background {
                selectionPill
                    .matchedGeometryEffect(id: "pill", in: pill)
            }
            .contentShape(Capsule())
        } else {
            glyph(item, isSelected: false, showsLockDot: showsLockDot)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.tabBarItem)
                .frame(minWidth: Theme.Metrics.minTapTarget)
                .contentShape(Rectangle())
        }
    }

    private func glyph(_ item: Item, isSelected: Bool, showsLockDot: Bool) -> some View {
        Image(systemName: isSelected ? item.selectedSymbol : item.symbol)
            .font(.system(size: 20, weight: isSelected ? .bold : .semibold))
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.muted)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .frame(width: 26, height: 26)
            .overlay(alignment: .topTrailing) {
                if showsLockDot {
                    Circle()
                        .fill(isSelected ? Theme.Colors.onAccent : Theme.Colors.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.Colors.backgroundDeep, lineWidth: 1.5))
                        .offset(x: 3, y: -1)
                }
            }
            .accessibilityHidden(true)
    }

    /// The liquid pill: `accentFill` (white labels clear AA on it), a sheen across its top, a specular
    /// rim and a soft blue glow under it.
    private var selectionPill: some View {
        let shape = Capsule(style: .continuous)
        return shape
            .fill(Theme.Colors.accentFill)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            .overlay(shape.strokeBorder(Theme.Colors.glassEdge, lineWidth: Theme.Metrics.edgeWidth))
            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 12, y: 4)
    }
}
