import SwiftUI
import Core

// The floating glass tab bar (founder's reference, 2026-09-24): one dark glass capsule floating
// above the content, thin outline icons with small labels, and the selected tab lit by a soft
// circle of light that glides between tabs. It replaces the system tab bar (hidden in
// `MainTabView`), which can't be restyled this far. `TabView` still owns tab state, so each tab
// keeps its navigation stack and scroll position.
//
// Accessibility: the bar is one container ("zano.tabBar") of buttons named by their tab titles,
// the selected one carrying `.isSelected`, which is what the UI tests query.

struct ZanoTabBar: View {
    @Binding var selection: AppTab

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
        Item(tab: .fuel, title: Copy.fuel.screenTitle, symbol: "fuelpump"),
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
        .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zano.tabBar")
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func button(for item: Item) -> some View {
        let isSelected = selection == item.tab
        return Button {
            guard selection != item.tab else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) {
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
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                            .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 12)
                            .frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "glow", in: glow)
                    }
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Theme.Colors.muted)
                }
                .frame(width: 40, height: 34)
                Text(item.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Dark frosted glass with a top-lit rim and a faint light along the bottom edge.
    private var glass: some View {
        let shape = Capsule(style: .continuous)
        return ZStack {
            if reduceTransparency {
                shape.fill(Theme.Colors.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.45))
            }
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.07), Color.white.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.05), Color.white.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        }
        .environment(\.colorScheme, .dark)
    }
}
