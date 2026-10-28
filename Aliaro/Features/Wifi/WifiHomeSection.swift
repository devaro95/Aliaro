import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

/// Home's Wi-Fi section: the family's networks with the password (hidden
/// until tapped), copy and a QR code guests can scan to join. With none
/// saved, a small card invites to add the home Wi-Fi.
struct WifiHomeSection: View {
    @Query(sort: [SortDescriptor(\WifiNetwork.position), SortDescriptor(\WifiNetwork.createdAt)])
    private var networks: [WifiNetwork]

    @State private var showAdd = false
    @State private var networkToEdit: WifiNetwork?
    @State private var networkForQR: WifiNetwork?

    var body: some View {
        VStack(spacing: 10) {
            if networks.isEmpty {
                emptyCard
            } else {
                ForEach(networks) { network in
                    WifiCard(
                        network: network,
                        onQR: {
                            Track.event("wifi_qr_open")
                            networkForQR = network
                        },
                        onEdit: { networkToEdit = network }
                    )
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            WifiEditorSheet(networkToEdit: nil)
        }
        .sheet(item: $networkToEdit) { network in
            WifiEditorSheet(networkToEdit: network)
        }
        .sheet(item: $networkForQR) { network in
            WifiQRSheet(network: network)
        }
    }

    private var emptyCard: some View {
        Button {
            Track.event("wifi_add_tap", ["source": "home_empty"])
            showAdd = true
        } label: {
            HStack(spacing: 12) {
                WifiIcon()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your home Wi-Fi")
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text("Everyone (and your guests) will have the password at hand.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ALIColors.mutedInk)
            }
            .padding(14)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Round Wi-Fi badge.
private struct WifiIcon: View {
    var body: some View {
        Image(systemName: "wifi")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(ALIColors.onAccent)
            .frame(width: 42, height: 42)
            .background(ALIColors.wifiAccent)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// One network: name, SSID, password (tap the eye to show), copy, QR.
private struct WifiCard: View {
    let network: WifiNetwork
    let onQR: () -> Void
    let onEdit: () -> Void

    @State private var revealed = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WifiIcon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.displayName)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                    if !network.label.isEmpty {
                        Text(network.ssid)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit"))
            }

            if network.securityType == .none {
                Text("Open network, no password")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
            } else {
                HStack(spacing: 8) {
                    Text(revealed ? network.password : String(repeating: "•", count: min(max(network.password.count, 8), 16)))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    smallButton(revealed ? "eye.slash" : "eye", label: revealed ? "Hide password" : "Show password") {
                        revealed.toggle()
                        if revealed { Track.event("wifi_password_reveal") }
                    }
                    smallButton(copied ? "checkmark" : "doc.on.doc", label: "Copy password") {
                        UIPasteboard.general.string = network.password
                        Track.event("wifi_password_copy")
                        withAnimation { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { copied = false }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: onQR) {
                Label("Show QR for guests", systemImage: "qrcode")
                    .font(ALITypography.labelLarge.weight(.semibold))
                    .foregroundStyle(ALIColors.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(ALIColors.wifiAccent.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func smallButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 34, height: 34)
                .background(ALIColors.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Big QR with the network: any phone camera joins by scanning it.
struct WifiQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    let network: WifiNetwork

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = Self.renderQR(network.qrPayload) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(maxWidth: 280)
                }
                VStack(spacing: 6) {
                    Text(network.displayName)
                        .font(ALITypography.headlineMedium)
                        .foregroundStyle(ALIColors.ink)
                    Text("Scan it with the phone's camera to join the Wi-Fi.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(ALIColors.background)
            .navigationTitle("Wi-Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .trackScreen("wifi_qr")
    }

    static func renderQR(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Add or edit a network: name (optional), SSID, password and security.
struct WifiEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @Query private var networks: [WifiNetwork]

    let networkToEdit: WifiNetwork?

    @State private var label = ""
    @State private var ssid = ""
    @State private var password = ""
    @State private var security: WifiNetwork.Security = .wpa
    @State private var showDelete = false

    private var canSave: Bool {
        !ssid.trimmed.isEmpty && (security == .none || !password.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ALITextField(placeholder: "Name (e.g. Home)", text: $label)
                        .onChange(of: label) { _, new in if new.count > WifiNetwork.maxLabelLength { label = String(new.prefix(WifiNetwork.maxLabelLength)) } }
                    ALITextField(placeholder: "Network name (SSID)", text: $ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: ssid) { _, new in if new.count > WifiNetwork.maxSSIDLength { ssid = String(new.prefix(WifiNetwork.maxSSIDLength)) } }

                    Picker("Security", selection: $security) {
                        Text("WPA/WPA2").tag(WifiNetwork.Security.wpa)
                        Text("WEP").tag(WifiNetwork.Security.wep)
                        Text("No password").tag(WifiNetwork.Security.none)
                    }
                    .pickerStyle(.segmented)

                    if security != .none {
                        ALITextField(placeholder: "Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: password) { _, new in if new.count > WifiNetwork.maxPasswordLength { password = String(new.prefix(WifiNetwork.maxPasswordLength)) } }
                    }

                    Text("Everyone in the family group will see it on Home.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ALIPrimaryButton(text: "Save", enabled: canSave, accent: ALIColors.wifiAccent) { save() }

                    if networkToEdit != nil {
                        ALITextButton(text: "Delete network", color: ALIColors.error) { showDelete = true }
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(networkToEdit == nil ? "Add Wi-Fi" : "Edit Wi-Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard let network = networkToEdit else { return }
                label = network.label
                ssid = network.ssid
                password = network.password
                security = network.securityType
            }
            .aliDeleteConfirmDialog(isPresented: $showDelete, itemName: networkToEdit?.displayName ?? "") {
                delete()
            }
        }
        .presentationDetents([.large])
        .trackScreen("wifi_editor")
    }

    private func save() {
        guard let familyID = familySession.familyID else { return }
        let actorName = familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
        let network: WifiNetwork
        if let existing = networkToEdit {
            existing.label = label.trimmed
            existing.ssid = ssid.trimmed
            existing.password = security == .none ? "" : password
            existing.security = security.rawValue
            existing.updatedAt = .now
            network = existing
        } else {
            network = WifiNetwork(
                label: label.trimmed, ssid: ssid.trimmed, password: security == .none ? "" : password, security: security,
                position: (networks.map(\.position).max() ?? -1) + 1,
                createdByID: familySession.memberID, createdByName: actorName
            )
            modelContext.insert(network)
        }
        try? modelContext.save()
        dataSync.pushWifiNetwork(network, familyID: familyID)
        Track.event(networkToEdit == nil ? "wifi_new" : "wifi_edited", ["security": security.rawValue])
        dataSync.logActivity(
            entityType: "wifi", entityName: String(network.displayName.prefix(60)), action: networkToEdit == nil ? "created" : "updated",
            actorID: familySession.memberID, actorName: actorName, familyID: familyID, modelContext: modelContext
        )
        dismiss()
    }

    private func delete() {
        guard let network = networkToEdit else { return }
        let id = network.id
        let name = network.displayName
        modelContext.delete(network)
        try? modelContext.save()
        dataSync.deleteWifiNetwork(id: id)
        Track.event("wifi_deleted")
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "wifi", entityName: String(name.prefix(60)), action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
        dismiss()
    }
}
