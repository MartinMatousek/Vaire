import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("TimeKeeper")
                .font(.headline)
            Text("Scaffold — Fáze 0")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 240, height: 120)
    }
}

#Preview {
    ContentView()
}
