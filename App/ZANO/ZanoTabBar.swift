import SwiftUI
import Core

// The floating glass tab bar (founder's reference, 2026-09-24): one dark glass capsule floating
// above the content, thin outline icons with small labels, and the selected tab lit by a soft
// circle of light that glides between tabs. It replaces the system tab bar (hidden in
// `MainTabView`), which can't be restyled this far. `TabView` still owns tab state, so each tab
// keeps its navigation stack and scroll position.
//
// Accessibility: the bar is one container ("zano.tabBar") of buttons named by their tab titles,
// the selected one carrying `.isSelected`, which is what the UI tests query. The labels are a fixed
// 11pt (the bar can't grow), so each item offers the Large Content Viewer instead. Selection is
// color and glow only, at one font weight, so the labels never change width.
//
// `.isTabBar` is not added to the container: its SwiftUI availability on the iOS 17 target is
// unverified here, and a wrong trait would change what the UI tests' `zanoTabBar.buttons[...]`
// query sees.

struct ZanoTabBar: View {
    @Binding var selection: AppTab
    /// A lock is running: the Lock item carries a small blue dot and says so to VoiceOver.
    var isLockActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var glow

    /// Space each tab reserves at the bottom so its content and bottom bars clear the capsule.
    static let reservedHeight: CGFloat = 80

    private static let height: CGFloat = 64

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let symbol: String
        var id: AppTab { tab }
    }

    private let items: [Item] = [
        Item(tab: .today, title: Copy.today.screenTitle, symbol: "scope"),
        Item(tab: .lock, title: Copy.lockStatus.screenTitle, symbol: "lock"),
        Item(tab: .fuel, title: Copy.fuel.screenTitle, symbol: "fork.knife"),
        Item(tab: .progress, title: Copy.progress.screenTitle, symbol: "chart.line.uptrend.xyaxis"),
        Item(tab: .settings, title: Copy.settings.screenTitle, symbol: "gearshape"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(for: item)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(glass)
        .shadow(color: Theme.Colors.background.opacity(0.55), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zano.tabBar")
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func button(for item: Item) -> some View {
        let isSelected = selection == item.tab
        let showsLockDot = item.tab == .lock && isLockActive
        return Button {
            guard selection != item.tab else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
                selection = item.tab
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Theme.Colors.accent.opacity(0.55), Theme.Colors.accent.opacity(0.12)],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 22
                                )
                            )
                            .overlay(Circle().strokeBorder(Theme.Colors.edgeTop, lineWidth: 0.5))
                            .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 12)
                            .frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "glow", in: glow)
                    }
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.muted)
                        .overlay(alignment: .topTrailing) {
                            if showsLockDot {
                                Circle()
                                    .fill(Theme.Colors.accent)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().strokeBorder(Theme.Colors.lockedAmbient, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }
                        }
                }
                .frame(width: 40, height: 34)
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(showsLockDot ? Copy.lockStatus.tabLockRunningValue : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(item.title, systemImage: item.symbol)
        }
    }

    /// Dark frosted glass with a top-lit rim and a faint light along the bottom edge.
    private var glass: some View {
        let shape = Capsule(style: .continuous)
        return ZStack {
            if reduceTransparency {
                shape.fill(Theme.Colors.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.Colors.background.opacity(0.45))
            }
            shape.fill(Theme.Colors.glassFill)
            shape.strokeBorder(Theme.Colors.glassEdge, lineWidth: 0.75)
        }
        .environment(\.colorScheme, .dark)
    }
}
