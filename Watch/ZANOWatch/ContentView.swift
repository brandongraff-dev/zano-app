// ContentView.swift
// Watch/ZANOWatch
//
// Minimal skeleton root view — mirrors App/ZANO/ContentView.swift's Session-0 scaffold in spirit
// (confirms the app launches and renders, nothing more). Real Watch UI (rings, "Start Lock"/
// "Start Focus" actions per docs/spec.md §5.21) is future v3 scope, not this task's.

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("ZANO")
                .font(.system(size: 24, weight: .bold))
            Text("Watch companion — v3 scaffold (docs/spec.md §5.21).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
