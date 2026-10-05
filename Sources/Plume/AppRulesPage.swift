import AppKit
import PlumeKit
import SwiftUI

/// La page « Applications » : pour chaque app, l'allure du texte dicté, l'envoi avec Entrée,
/// la mise au propre par l'IA et la méthode d'insertion. Une seule liste, sans « modes » à
/// configurer : Plume reconnaît l'app au premier plan et applique sa règle.
struct ApplicationsPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: tr("Applications"),
                    subtitle: tr("Plume adapte la dictée à l'app dans laquelle tu parles : un message sur Slack n'a pas la tenue d'un mail.")
                ) {
                    HStack(spacing: 6) {
                        if !settings.rules.contains(where: { $0.bundleID == "*" }) {
                            PlumeButton(title: tr("Toutes les autres"), icon: .layoutGrid) {
                                withAnimation(UI.spring) { settings.addDefaultRule() }
                            }
                        }
                        PlumeButton(title: tr("Ajouter une app"), icon: .plus, kind: .primary) { settings.addRule() }
                    }
                }
                .rise(0)

                if settings.rules.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("Aucune règle pour l'instant")).font(UI.sans(14, .medium))
                            Text(
                                tr("Sans règle, chaque dictée est collée telle quelle. Ajoute Slack ou Messages pour écrire sans point final, ")
                                    + tr("ton app de mail pour une mise au propre par l'IA, ou ton terminal pour valider avec Entrée.")
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

                Text(tr("Les styles : Standard garde majuscules et ponctuation ; Message retire le point final ; Décontracté retire aussi la majuscule de début de phrase. « Toutes les autres » s'applique aux apps sans règle."))
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

/// Une règle : l'app en tête, ses quatre réglages en dessous.
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
                            Text(rule.bundleID).font(UI.mono(11)).foregroundStyle(UI.text3)
                        }
                    }
                    Spacer()
                    Picker("", selection: $rule.style) {
                        ForEach(DictationStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .help(rule.style.detail)
                    Button(action: remove) {
                        Icon(.x, size: 12)
                            .foregroundStyle(UI.text3)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help(tr("Retirer cette règle"))
                    .opacity(hovering ? 1 : 0.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    "Valider avec Entrée", detail: tr("Le message part dès que le texte est collé."), isOn: $rule.pressReturn)
                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    tr("Mettre au propre par l'IA locale"),
                    detail: ai.isAvailable ? tr("Ponctuation, faux départs et auto-corrections repris par Apple Intelligence.") : (ai.reason ?? ""),
                    isOn: $rule.polish
                )
                .disabled(!ai.isAvailable)
                if rule.polish, ai.isAvailable {
                    HStack(spacing: 10) {
                        Text(tr("Consignes")).font(UI.sans(13)).foregroundStyle(UI.text2)
                        TextField(tr("tutoie, pas d'émojis, ton direct…"), text: $rule.instructions)
                            .textFieldStyle(.plain)
                            .font(UI.sans(13))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                RuleToggle(
                    tr("Taper le texte au lieu de le coller"),
                    detail: tr("Pour les apps qui refusent ⌘V (bureau à distance, certains terminaux)."), isOn: $rule.typeText)
            }
        }
        .onHover { hovering = $0 }
        .animation(UI.quick, value: hovering)
        .animation(UI.quick, value: rule.polish)
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
