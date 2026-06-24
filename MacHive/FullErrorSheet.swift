import SwiftUI

struct FullErrorSheet: View {
    let message: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Error Details")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 300)
            .padding(8)
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)

            Button("Copy Full Error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 500)
    }
}
