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
                    Text("Wallet card skin · Swift Concurrency · v0.1.4")
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
                        Text("Se ajusta al lienzo conservando los bordes y se genera el PNG/PDF que espera Wallet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ColorPicker("Color de números y etiquetas", selection: $model.cardTextColor, supportsOpacity: false)
                        Text("No necesitas un .passthm: se actualizan foregroundColor y labelColor del pass.")
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

            GroupBox("5. Teclado de código (opcional)") {
                HStack(spacing: 16) {
                    Group {
                        if let image = model.passcodePreview {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 150, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.quaternary, lineWidth: 1)
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 150, height: 100)
                                .overlay { Text("Sin tema").foregroundStyle(.secondary) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Button("Elegir .passthm…") { model.choosePasscodeTheme() }
                            Text(model.passcodeThemeName.isEmpty ? "Tema de teclado" : model.passcodeThemeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 14) {
                            ColorPicker("Color", selection: $model.passcodeColor, supportsOpacity: false)
                                .frame(width: 170)
                                .onChange(of: model.passcodeColor) { _, _ in
                                    model.recolorPasscodePreview()
                                }
                            Picker("Caché", selection: $model.passcodeTargetVersion) {
                                Text("TelephonyUI-10").tag("TelephonyUI-10")
                                Text("TelephonyUI-9").tag("TelephonyUI-9")
                                Text("TelephonyUI-8").tag("TelephonyUI-8")
                            }
                            .frame(width: 170)
                            .onChange(of: model.passcodeTargetVersion) { _, _ in
                                model.recolorPasscodePreview()
                            }
                        }
                        Text("Solo necesitas esta sección si también quieres cambiar el teclado de código; para los números de Wallet usa el selector de arriba.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Aplicar color al teclado") { model.flashPasscodeTheme() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || model.devices.isEmpty || model.passcodeTheme == nil)
                    }
                }
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
