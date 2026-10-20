import SwiftUI

@main
struct SonyMandoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @State private var tv = TV()
    @AppStorage("ip") private var ip = ""
    @AppStorage("psk") private var psk = ""
    @State private var pin = ""
    @State private var needsPin = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Group {
            if tv.isConnected {
                RemoteView(tv: tv, error: $error)
            } else {
                connectForm
            }
        }
        .task { if !ip.isEmpty { await connect() } } // reconecta con la última IP
    }

    private var connectForm: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP de la TV (p. ej. 192.0.2.20)", text: $ip)
                        .keyboardType(.decimalPad)
                    SecureField("Pre-Shared Key (opcional)", text: $psk)
                } footer: {
                    Text("iPhone y TV en la misma Wi-Fi. Sin PSK, la TV mostrará un PIN.")
                }
                if needsPin {
                    Section("PIN") {
                        TextField("PIN de 4 dígitos", text: $pin).keyboardType(.numberPad)
                    }
                }
                Button(busy ? "Conectando…" : "Conectar") { Task { await connect() } }
                    .disabled(ip.isEmpty || busy)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Conectar TV")
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        tv.ip = ip.trimmingCharacters(in: .whitespaces)
        tv.psk = psk
        do {
            try await tv.connect(pin: needsPin && !pin.isEmpty ? pin : nil)
            error = nil
            needsPin = false
        } catch TV.Failure.needsPin {
            needsPin = true
            error = TV.Failure.needsPin.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RemoteView: View {
    let tv: TV
    @Binding var error: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var taps = 0

    /// iPad: misma UI, más grande.
    private var s: CGFloat { sizeClass == .regular ? 1.6 : 1 }

    var body: some View {
        VStack(spacing: 24 * s) {
            HStack {
                key("power", "Encender/apagar", tint: .red) { try await tv.togglePower() }
                Spacer()
                key("rectangle.portrait.and.arrow.right", "Entrada") { try await tv.press("Input") }
                key("xmark.circle", "Desconectar") { tv.disconnect() }
            }

            dpad

            HStack {
                key("arrow.uturn.backward", "Atrás") { try await tv.press("Return") }
                Spacer()
                key("house", "Inicio") { try await tv.press("Home") }
                Spacer()
                key("speaker.slash", "Silencio") { try await tv.press("Mute") }
            }

            HStack {
                rocker("speaker.wave.1", "speaker.wave.3", label: "Volumen", down: "VolumeDown", up: "VolumeUp")
                Spacer()
                numpad
                Spacer()
                rocker("chevron.down", "chevron.up", label: "Canal", down: "ChannelDown", up: "ChannelUp")
            }

            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .padding(24 * s)
        .frame(maxWidth: 500 * s)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private var dpad: some View {
        Grid(horizontalSpacing: 8 * s, verticalSpacing: 8 * s) {
            GridRow { Color.clear.frame(width: 1, height: 1); keyName("chevron.up", "Arriba", "Up"); Color.clear.frame(width: 1, height: 1) }
            GridRow {
                keyName("chevron.left", "Izquierda", "Left")
                key("circle.fill", "OK", size: 72) { try await tv.press("Confirm") }
                keyName("chevron.right", "Derecha", "Right")
            }
            GridRow { Color.clear.frame(width: 1, height: 1); keyName("chevron.down", "Abajo", "Down"); Color.clear.frame(width: 1, height: 1) }
        }
    }

    private var numpad: some View {
        Grid(horizontalSpacing: 6 * s, verticalSpacing: 6 * s) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                GridRow { ForEach(row, id: \.self) { digit($0) } }
            }
            GridRow { Color.clear.frame(width: 1, height: 1); digit(0); Color.clear.frame(width: 1, height: 1) }
        }
    }

    private func digit(_ n: Int) -> some View {
        Button { run { try await tv.press("Num\(n)") } } label: {
            Text("\(n)").font(.system(size: 20 * s, weight: .medium))
                .frame(width: 44 * s, height: 44 * s)
                .background(.fill.tertiary, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func rocker(_ downIcon: String, _ upIcon: String, label: String, down: String, up: String) -> some View {
        VStack(spacing: 8 * s) {
            keyName(upIcon, "\(label) +", up)
            Text(label).font(.system(size: 12 * s)).foregroundStyle(.secondary)
            keyName(downIcon, "\(label) −", down)
        }
    }

    private func keyName(_ icon: String, _ label: String, _ name: String) -> some View {
        key(icon, label) { try await tv.press(name) }
    }

    private func key(_ icon: String, _ label: String, size: CGFloat = 56, tint: Color = .primary,
                     action: @escaping () async throws -> Void) -> some View {
        Button { run(action) } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38 * s, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size * s, height: size * s)
                .background(.fill.tertiary, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        taps += 1
        Task {
            do { try await action(); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}
