import AppKit
import SwiftUI

struct CardDetailView: View {
    @ObservedObject var model: AppModel
    let card: WalletCard
    let openStudio: () -> Void
    @State private var entries: [CardHistoryEntry] = []
    @State private var renameText = ""
    @State private var isRenaming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                historySection
                limitsNote
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(card.name)
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
                    model.status = "Hash copiado."
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
    }

    private func reload() {
        entries = model.history(for: card)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            CardThumbnail(image: model.cardThumbnails[card.hash], width: 340)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
            VStack(alignment: .leading, spacing: 10) {
                Text(card.name)
                    .font(.largeTitle.weight(.semibold))
                Label {
                    Text(card.hash).font(.callout.monospaced()).textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                }
                .foregroundStyle(.secondary)
                Label("Vista \(card.hits) veces · última \(card.lastSeen.formatted(.relative(presentation: .named)))", systemImage: "clock")
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
                Text("Aún no has aplicado un diseño a esta tarjeta desde AirCard. Cada vez que lo hagas se guardará aquí una copia con la miniatura, los 11 archivos y el .\(SkinDocument.fileExtension).")
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
