import AppKit
import SwiftUI

struct CardDetailView: View {
    @ObservedObject var model: AppModel
    let card: WalletCard
    let openStudio: () -> Void
    @State private var entries: [CardHistoryEntry] = []
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var showColorWarning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                historySection
                cardTextColorSection
                limitsNote
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AirCardL10n.cardName(card.name))
        .navigationSubtitle(card.shortHash)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    renameText = card.name
                    isRenaming = true
                } label: {
                    Label("Renombrar", systemImage: "pencil")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.hash, forType: .string)
                    model.status = AirCardL10n.text("Hash copiado.")
                } label: {
                    Label("Copiar hash", systemImage: "doc.on.doc")
                }
                Button {
                    openStudio()
                } label: {
                    Label("Diseñar", systemImage: "paintpalette")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: card.hash) { _, _ in reload() }
        .onChange(of: model.historyRevision) { _, _ in reload() }
        .alert("Renombrar tarjeta", isPresented: $isRenaming) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") { model.renameCard(card, to: renameText) }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog(
            "Cambiar el color de los números",
            isPresented: $showColorWarning,
            titleVisibility: .visible
        ) {
            Button("Aplicar color") {
                model.selectCard(card)
                model.flashCardTextColor()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se intentará cambiar foregroundColor en pass.json. iOS puede rechazarlo o ignorarlo.")
        }
    }

    private func reload() {
        entries = model.history(for: card)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            CardThumbnail(image: model.cardThumbnails[card.hash], width: 340)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
            VStack(alignment: .leading, spacing: 10) {
                Text(AirCardL10n.cardName(card.name))
                    .font(.largeTitle.weight(.semibold))
                Label {
                    Text(card.hash).font(.callout.monospaced()).textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                }
                .foregroundStyle(.secondary)
                Label(
                    AirCardL10n.format(
                        "Vista %d veces · última %@",
                        card.hits,
                        card.lastSeen.formatted(.relative(presentation: .named).locale(AirCardL10n.locale))
                    ),
                    systemImage: "clock"
                )
                    .foregroundStyle(.secondary)
                if model.selectedCard?.hash == card.hash {
                    Label("Tarjeta destino de «Aplicar»", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                if let latest = entries.first {
                    HStack {
                        Button {
                            model.exportBackup(latest, card: card)
                        } label: {
                            Label("Guardar respaldo…", systemImage: "externaldrive.badge.plus")
                        }
                        .controlSize(.large)
                        Button {
                            model.openInStudio(latest)
                            openStudio()
                        } label: {
                            Label("Abrir en el estudio", systemImage: "paintpalette")
                        }
                        .controlSize(.large)
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historial de skins aplicados")
                .font(.title3.weight(.semibold))
            if entries.isEmpty {
                Text(AirCardL10n.format("Aún no has aplicado un diseño a esta tarjeta desde AirCard. Cada vez que lo hagas se guardará aquí una copia con la miniatura, los 11 archivos y el .%@.", SkinDocument.fileExtension))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(entries) { entry in
                        HistoryTile(entry: entry) {
                            model.exportBackup(entry, card: card)
                        } open: {
                            model.openInStudio(entry)
                            openStudio()
                        }
                    }
                }
            }
        }
    }

    private var limitsNote: some View {
        Label {
            Text("AirCard no puede leer el diseño original de Apple o del banco desde el iPhone; el respaldo contiene solo lo que aplicaste con la app. Para volver al original, quita la tarjeta de Wallet y vuelve a añadirla.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var cardTextColorSection: some View {
        GroupBox("Texto de los números") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Control experimental del color del texto de esta tarjeta. No usa archivos .passthm ni modifica el diseño de fondo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        colorPicker
                        readColorButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        colorPicker
                        readColorButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        applyColorButton
                        clearCacheButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        applyColorButton
                        clearCacheButton
                    }
                }

                Text(model.cardTextColorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var colorPicker: some View {
        ColorPicker("Color del texto", selection: $model.cardTextColor, supportsOpacity: false)
            .frame(maxWidth: 260, alignment: .leading)
    }

    private var readColorButton: some View {
        Button("Leer color") {
            model.selectCard(card)
            model.readCardTextColor()
        }
        .disabled(model.isBusy || model.selectedDevice == nil)
    }

    private var applyColorButton: some View {
        Button("Intentar cambio de color") {
            model.selectCard(card)
            showColorWarning = true
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy || model.selectedDevice == nil)
    }

    private var clearCacheButton: some View {
        Button("Regenerar caché") {
            model.selectCard(card)
            model.clearWalletCardCache()
        }
        .help("Elimina los renders guardados de esta tarjeta para que Wallet los genere otra vez.")
        .disabled(model.isBusy || model.selectedDevice == nil)
    }
}

private struct HistoryTile: View {
    let entry: CardHistoryEntry
    let backup: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardThumbnail(image: NSImage(contentsOf: entry.thumbnailURL), width: 200)
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.weight(.medium))
            HStack {
                Button("Abrir", action: open)
                Button("Respaldo…", action: backup)
            }
            .controlSize(.small)
        }
        .contextMenu {
            Button("Abrir en el estudio", action: open)
            Button("Guardar respaldo…", action: backup)
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
    }
}

struct ActivityView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(20)
            }
            .onChange(of: model.logs.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
        .navigationTitle("Actividad")
        .toolbar {
            ToolbarItem {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logs.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copiar registro", systemImage: "doc.on.doc")
                }
            }
        }
        .overlay {
            if model.logs.isEmpty {
                ContentUnavailableView("Sin actividad", systemImage: "list.bullet.rectangle", description: Text("Aquí verás lo que hace la app con el iPhone."))
            }
        }
    }
}
