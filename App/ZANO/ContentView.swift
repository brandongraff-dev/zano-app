import SwiftUI
import Core

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ZANO")
                .font(.system(size: 48, weight: .bold))
            Text("Session 0 scaffold — Today/Lock/Fuel/Progress/Settings land in Session 5 (docs/spec.md §15).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    ContentView()
}
