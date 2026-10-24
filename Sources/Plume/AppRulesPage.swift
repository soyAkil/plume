import AppKit
import PlumeKit
import SwiftUI

/// The "Applications" page: for each app, the style of the dictated text, sending with Return,
/// the AI clean-up and the insertion method. A single list, with no "modes" to
/// configure: Plume recognizes the frontmost app and applies its rule.
struct ApplicationsPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: tr("Applications"),
                    subtitle: tr("Plume adapts the dictation to the app you are talking in: a Slack message doesn't have the polish of an email.")
                ) {
                    HStack(spacing: 6) {
                        if !settings.rules.contains(where: { $0.bundleID == "*" }) {
                            PlumeButton(title: tr("All others"), icon: .layoutGrid) {
                                withAnimation(UI.spring) { settings.addDefaultRule() }
                            }
                        }
                        PlumeButton(title: tr("Add an app"), icon: .plus, kind: .primary) { settings.addRule() }
                    }
                }
                .rise(0)

                if settings.rules.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("No rules yet")).font(UI.sans(14, .medium))
                            Text(
                                tr("Without a rule, each dictation is pasted as is. Add Slack or Messages to write without a final period, ")
                                    + tr("your mail app for an AI clean-up, or your terminal to confirm with Return.")
                            )
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .rise(1)
                }

                ForEach(Array($settings.rules.enumerated()), id: \.element.id) { index, $rule in
                    RuleCard(rule: $rule, icon: settings.icon(for: rule), ai: settings.ai) {
                        Sounds.play(.toggleOff)
                        withAnimation(UI.spring) { settings.rules.removeAll { $0.id == rule.id } }
                    }
                    .rise(index + 1)
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }

                Text(tr("Styles: Standard keeps capitals and punctuation; Message drops the final period; Casual also drops the capital at the start of a sentence. “All others” applies to apps without a rule."))
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .rise(settings.rules.count + 1)
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { settings.refreshAI() }
    }
}

/// A rule: the app on top, its four settings below.
private struct RuleCard: View {
    @Binding var rule: AppRule
    var icon: NSImage?
    var ai: LocalAI.Availability
    var remove: () -> Void
    @State private var hovering = false

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let icon {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    } else {
                        Icon(.layoutGrid, size: 16)
                            .foregroundStyle(UI.text2)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.hover))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.name).font(UI.sans(14, .medium))
                        if rule.bundleID != "*" {
                            Text(rule.bundleID + (rule.isBuiltIn ? " · " + tr("built in") : "")).font(UI.mono(11)).foregroundStyle(UI.text3)
                        }
                    }
                    Spacer()
                    Picker("", selection: $rule.style) {
                        ForEach(DictationStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .help(rule.style.detail)
                    if !rule.isBuiltIn {
                        Button(action: remove) {
                            Icon(.x, size: 12)
                                .foregroundStyle(UI.text3)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .help(tr("Remove this rule"))
                        .opacity(hovering ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    tr("Send with Return"), detail: tr("The message is sent as soon as the text is pasted."), isOn: $rule.pressReturn)
                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleKey(
                    tr("Key to press first"), detail: tr("Pressed before pasting, to open the field: T opens the Minecraft chat."),
                    key: $rule.openKey, delay: $rule.openDelay)
                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    tr("Clean up with the local AI"),
                    detail: ai.isAvailable ? tr("Punctuation, false starts and self-corrections fixed by Apple Intelligence.") : (ai.reason ?? ""),
                    isOn: $rule.polish
                )
                .disabled(!ai.isAvailable)
                if rule.polish, ai.isAvailable {
                    HStack(spacing: 10) {
                        Text(tr("Instructions")).font(UI.sans(13)).foregroundStyle(UI.text2)
                        TextField(tr("informal tone, no emojis, be direct…"), text: $rule.instructions)
                            .textFieldStyle(.plain)
                            .font(UI.sans(13))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    tr("Type the text instead of pasting it"),
                    detail: tr("For apps that refuse ⌘V (remote desktop, some terminals)."), isOn: $rule.typeText)
            }
        }
        .onHover { hovering = $0 }
        .animation(UI.quick, value: hovering)
        .animation(UI.quick, value: rule.polish)
    }
}

/// One letter, pressed before the paste; empty for none.
private struct RuleKey: View {
    var title: String
    var detail: String
    @Binding var key: String
    /// Seconds; shown and typed in milliseconds.
    @Binding var delay: Double

    init(_ title: String, detail: String, key: Binding<String>, delay: Binding<Double>) {
        self.title = title
        self.detail = detail
        _key = key
        _delay = delay
    }

    private var milliseconds: Binding<String> {
        Binding(
            get: { String(Int((delay * 1000).rounded())) },
            set: { if let value = Int($0.filter(\.isNumber)) { delay = Double(value) / 1000 } })
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.sans(14))
                Text(detail).font(UI.sans(13)).foregroundStyle(UI.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !key.isEmpty {
                Text(tr("then wait")).font(UI.sans(13)).foregroundStyle(UI.text2)
                TextField("", text: milliseconds)
                    .textFieldStyle(.plain)
                    .font(UI.mono(13))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.hover))
                Text("ms").font(UI.sans(13)).foregroundStyle(UI.text2)
            }
            TextField(tr("none"), text: $key)
                .textFieldStyle(.plain)
                .font(UI.mono(13))
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.hover))
                .onChange(of: key) { _, new in
                    let letter = String(new.trimmingCharacters(in: .whitespaces).uppercased().prefix(1))
                    if letter != new { key = letter }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct RuleToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.sans(14))
                Text(detail).font(UI.sans(13)).foregroundStyle(UI.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(PlumeSwitch())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(enabled ? 1 : 0.45)
    }
}
