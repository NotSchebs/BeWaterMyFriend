import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Be water, my friend")
                .font(.title2.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
