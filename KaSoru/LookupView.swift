import SwiftUI

struct LookupView: View {
    @ObservedObject var model: LookupViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            transcript
            Divider()
            inputBar
        }
        .frame(width: 360)
        .frame(minHeight: 120, maxHeight: 420)
        .background(VisualEffectBackground(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { idx, turn in
                        TurnRow(turn: turn).id(idx)
                    }
                    if let err = model.errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.turns.count) {
                proxy.scrollTo(model.turns.count - 1, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a follow-up", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { model.submitFollowUp() }
                .disabled(model.isWaiting)
            Button {
                model.submitFollowUp()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isWaiting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }
}

private struct TurnRow: View {
    let turn: LookupTurn
    var body: some View {
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
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
