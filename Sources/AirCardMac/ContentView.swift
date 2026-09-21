import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AirCard macOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Wallet card skin · port nativo con Swift Concurrency")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Actualizar dispositivos") { model.refreshDevices() }
                    .disabled(model.isBusy)
            }

            GroupBox("1. iPhone") {
                HStack {
                    Picker("Dispositivo", selection: $model.selectedDeviceID) {
                        Text("Seleccionar…").tag("")
                        ForEach(model.devices) { device in
                            Text(device.summary).tag(device.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if model.devices.isEmpty {
                        Text("Sin dispositivo")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("2. Tarjeta") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Hash de la tarjeta (Base64)", text: $model.cardHash)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(model.isScanning ? "Detener escaneo" : "Escanear desde Wallet") {
                            model.toggleScan()
                        }
                        .disabled(model.devices.isEmpty || model.isBusy)
                        Text("También puedes pegar el hash manualmente.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("3. Artwork") {
                HStack(spacing: 16) {
                    Group {
                        if let image = model.artworkPreview {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 280, height: 176)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 280, height: 176)
                                .overlay { Text("Sin imagen") .foregroundStyle(.secondary) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Elegir imagen…") { model.chooseArtwork() }
                        Text(model.imageName.isEmpty ? "PNG, JPG o WebP" : model.imageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Se recorta al centro y se genera el PNG/PDF que espera Wallet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Antes de aplicar: iPhone desbloqueado y Apple Books abierto al menos una vez.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button(model.isBusy ? "Cancelar" : "Aplicar skin") {
                    model.isBusy ? model.cancel() : model.flashSkin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isBusy && (model.selectedDeviceID.isEmpty || model.cardHash.isEmpty || model.artwork == nil))
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            DisclosureGroup("Registro") {
                ScrollView {
                    Text(model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 680)
    }
}
