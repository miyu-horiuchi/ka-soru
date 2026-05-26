import SwiftUI

struct LookupView: View {
    @ObservedObject var model: LookupViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top toolbar
            HStack {
                Spacer()
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Refresh — cancel current and clear")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.turns.isEmpty {
                        Text("Waiting…")
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { _, turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.prompt)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            Text(turn.answer.isEmpty ? "Thinking…" : turn.answer)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let err = model.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            Text("Click ↻ above to reset and try again.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                TextField("Ask a follow-up", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submitFollowUp() }
                Button("Send") { model.submitFollowUp() }
                    .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
