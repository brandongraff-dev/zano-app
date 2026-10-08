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
// Pass 2 "playful" (2026-10-03): the glyph of the tab you pick does a bounce (`symbolEffect(.bounce)`,
// keyed per tab so only the newly selected one jumps), the pill's spring is squishier
// (`Theme.Motion.tabPill`), and every item squishes on press (`PressableStyle`). The glyph keeps one
// identity across selected/unselected so the bounce plays on the glyph you just picked.
//
// `.isTabBar` is not added to the container: its SwiftUI availability on the iOS 17 target is
// unverified here, and a wrong trait would change what the UI tests' query sees.

struct ZanoTabBar: View {
    @Binding var selection: AppTab
    /// A lock is running: the Lock item carries a small dot and says so to VoiceOver.
    var isLockActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    /// Bumped for a tab each time it is picked: drives that tab's glyph bounce, and only that one.
    @State private var bounces: [AppTab: Int] = [:]

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
            bounces[item.tab, default: 0] += 1
            withAnimation(reduceMotion ? nil : Theme.Motion.tabPill) {
                selection = item.tab
            }
        } label: {
            itemLabel(item, isSelected: isSelected, showsLockDot: showsLockDot)
        }
        .buttonStyle(.pressable(scale: 0.88))
        // Selected: as wide as its pill needs; unselected: share what's left.
        .layoutPriority(isSelected ? 1 : 0)
        .accessibilityLabel(item.title)
        .accessibilityValue(showsLockDot ? Copy.lockStatus.tabLockRunningValue : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(item.title, systemImage: item.symbol)
        }
    }

    /// One structure for both states, so the glyph keeps its identity (and its bounce) when the tab
    /// is picked; the selected one grows its label and the sliding pill.
    private func itemLabel(_ item: Item, isSelected: Bool, showsLockDot: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs - 2) {
            glyph(item, isSelected: isSelected, showsLockDot: showsLockDot)
            if isSelected {
                Text(item.title)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // The bar is a fixed height, like the system tab bar; at larger sizes the
                    // Large Content Viewer (long-press) shows the title instead (session 41).
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }
        }
        .padding(.horizontal, isSelected ? Theme.Spacing.md : 0)
        .frame(maxWidth: isSelected ? nil : .infinity)
        .frame(minWidth: Theme.Metrics.minTapTarget)
        .frame(height: Theme.Metrics.tabBarItem)
        .background {
            if isSelected {
                selectionPill
                    .matchedGeometryEffect(id: "pill", in: pill)
            }
        }
        .contentShape(Capsule())
    }

    private func glyph(_ item: Item, isSelected: Bool, showsLockDot: Bool) -> some View {
        Image(systemName: isSelected ? item.selectedSymbol : item.symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 20, weight: isSelected ? .bold : .semibold))
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.muted)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .symbolEffect(.bounce.up, options: .speed(1.1), value: reduceMotion ? 0 : bounces[item.tab, default: 0])
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
            // Pass 3 (restraint): a solid pill with the glass rim; no sheen, no glow.
            .fill(Theme.Colors.accentFill)
            .overlay(shape.strokeBorder(Theme.Colors.glassEdge, lineWidth: Theme.Metrics.edgeWidth))
    }
}
