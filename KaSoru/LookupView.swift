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
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        // Only the latest turn, while we're still waiting, should show
                        // "Thinking…". A completed turn that came back empty would otherwise
                        // be stuck on "Thinking…" forever.
                        let isLatest = index == model.turns.count - 1
                        let placeholder = (isLatest && model.isWaiting) ? "Thinking…" : "(no response)"
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.prompt)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            Text(turn.answer.isEmpty ? placeholder : turn.answer)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if model.needsAuth {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Codex sign-in expired.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Sign in again to continue. This opens your browser.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Button {
                                model.authenticate()
                            } label: {
                                HStack(spacing: 6) {
                                    if model.isAuthenticating {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Signing in…")
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                        Text("Sign in to Codex")
                                    }
                                }
                            }
                            .disabled(model.isAuthenticating)
                            if let err = model.errorMessage {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                        }
                    } else if let err = model.errorMessage {
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
