import SwiftUI

@main
struct QuienMandaApp: App {
    init() { Task { await Coffee.finishPending() } }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - Estilo (marca Salva Tejero: "Papel" en claro, "Sótano" en oscuro)

extension Color {
    static let s100 = dyn(0xFFFFFF, 0x141110)
    static let s200 = dyn(0xF4F1EA, 0x211B17)
    static let ink = dyn(0x141110, 0xF1E6D0)
    static let muted = dyn(0x6B5A45, 0xC9B99A)
    static let verde = dyn(0x35693F, 0x6FB07C)
    static let onVerde = dyn(0xFFFFFF, 0x141110)
    static let rojo = dyn(0xB3342B, 0xE0675D)
    static let mostaza = dyn(0xD9A520, 0xE3B33A)
    static let azul = dyn(0x8FB5C9, 0x8FB5C9)
    static let line = dyn(0x141110, 0xF1E6D0, alpha: 0.14)
    static let press = dyn(0x141110, 0xF1E6D0, alpha: 0.09)

    private static func dyn(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

extension EnvironmentValues {
    /// Escala de la UI: el diseño es de 390×840 pt y se amplía hasta ×1,6 (iPad).
    @Entry var k: CGFloat = 1
    /// Pantalla apaisada y ancha (iPhone Duo abierto, iPad en horizontal): el mando va en dos columnas.
    @Entry var wide = false
}

extension Font {
    // ponytail: SF en lugar de Plus Jakarta Sans / Inter; empaquetar las fuentes si se quieren idénticas al arquetipo.
    static func display(_ size: CGFloat, _ weight: Weight = .heavy) -> Font { .system(size: size, weight: weight) }
}

/// Icono de `resources/quien-manda/iconos-ui` (24 pt, trazo de 2 pt); toma el color del texto.
struct Icon: View {
    let name: String
    var size: CGFloat = 24
    @Environment(\.k) private var k

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name).resizable().frame(width: size * k, height: size * k).accessibilityHidden(true)
    }
}

struct KeyStyle: ButtonStyle {
    enum Kind { case normal, ghost, tab, primary, danger, dark }
    var kind: Kind = .normal
    var radius: CGFloat = 8
    var outline: Color?
    @Environment(\.k) private var k
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius * k)
        return configuration.label
            .font(.system(size: 15 * k, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background(configuration.isPressed), in: shape)
            .overlay(shape.strokeBorder(outline ?? (kind == .normal ? .line : .clear), lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed && kind != .normal && kind != .ghost && kind != .tab ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .onVerde
        case .danger, .dark: .s100
        case .tab: .muted
        default: .ink
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: .verde
        case .danger: .rojo
        case .dark: .ink
        case .normal: pressed ? .press : .s200
        case .ghost, .tab: pressed ? .press : .clear
        }
    }
}

/// Tarjeta crema con borde fino, la base de casi todos los bloques.
struct Card: ViewModifier {
    var radius: CGFloat = 16
    @Environment(\.k) private var k
    func body(content: Content) -> some View {
        content
            .background(Color.s200, in: .rect(cornerRadius: radius * k))
            .overlay(RoundedRectangle(cornerRadius: radius * k).strokeBorder(Color.line))
    }
}

/// Aviso de error que sube desde abajo y se va solo a los 3 s (o al tocarlo).
struct Toast: ViewModifier {
    @Binding var message: String?
    @Environment(\.k) private var k
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.system(size: 15 * k, weight: .medium))
                        .foregroundStyle(Color.onVerde)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16 * k)
                        .padding(.vertical, 12 * k)
                        .background(Color.rojo, in: .rect(cornerRadius: 12 * k))
                        .padding(16 * k)
                        .onTapGesture { self.message = nil }
                        .task(id: message) {
                            AccessibilityNotification.Announcement(message).post()
                            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                            self.message = nil
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(Toast(message: message)) }
}

// MARK: - Conexión

struct RootView: View {
    enum Stage: String { case splash, discover, pin, remote }

    @State private var tv = TV()
    @State private var discovery = Discovery()
    @AppStorage("ip") private var ip = ""
    @AppStorage("psk") private var psk = ""
    @AppStorage("name") private var name = ""
    @AppStorage("tvs") private var savedRaw = ""
    @State private var showSaved = UserDefaults.standard.string(forKey: "sheet") == "tvs"
    /// Con una TV guardada se arranca en el splash mientras reconecta.
    @State private var stage: Stage = UserDefaults.standard.string(forKey: "ip")?.isEmpty == false ? .splash : .discover
    @State private var busyIP: String?
    @State private var message: String?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.25
            let k = wide ? min(geo.size.width / 790, geo.size.height / 720, 1.6) : min(geo.size.width / 390, geo.size.height / 840, 1.6)
            ZStack {
                Color.s100.ignoresSafeArea()
                Group {
                    switch stage {
                    case .splash:
                        EmptyView()
                    case .discover:
                        DiscoverView(discovery: discovery, busyIP: busyIP,
                                     onClose: tv.isConnected ? { stage = .remote } : nil,
                                     onSaved: SavedTV.decode(savedRaw).isEmpty ? nil : { showSaved = true },
                                     onPick: { pick(ip: $0.ip, name: $0.name, psk: "") },
                                     onManual: { pick(ip: $0, name: $0, psk: $1) })
                    case .pin:
                        PinView(name: name, onBack: { stage = .discover }) { await connect(pin: $0) }
                    case .remote:
                        RemoteView(tv: tv, name: name.isEmpty ? tv.ip : name) { message = nil; stage = .discover }
                    }
                }
                .frame(width: wide && stage == .remote ? geo.size.width : 390 * k)
                if stage == .splash { SplashView().transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.25), value: stage == .splash)
            .toast($message)
            .sheet(isPresented: $showSaved) {
                SavedTVsSheet(tvs: SavedTV.decode(savedRaw), current: tv.isConnected ? ip : nil,
                              onPick: { showSaved = false; pick(ip: $0.ip, name: $0.name, psk: $0.psk) },
                              onRename: rename, onRemove: remove, onClose: { showSaved = false })
                    .environment(\.k, k)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color.s100)
            }
            .foregroundStyle(Color.ink)
            .environment(\.k, k)
            .environment(\.wide, wide)
        }
        .task { // reconecta con la última IP
            // Depuración sin TV: `-screen remote|pin|discover` (y en remote `-page 0…2`, `-sheet apps|settings`, `-fail <código>`; en discover `-sheet tvs`).
            if let screen = UserDefaults.standard.string(forKey: "screen") {
                tv.demo = true
                name = String(localized: "Tele")
                stage = Stage(rawValue: screen) ?? .remote
                return
            }
            guard !ip.isEmpty else { return }
            busyIP = ip
            message = await connect(pin: nil)
            busyIP = nil
            if stage == .splash { stage = .discover }
        }
    }

    private func pick(ip: String, name: String, psk: String) {
        self.ip = ip.trimmingCharacters(in: .whitespaces)
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.psk = psk
        busyIP = self.ip
        Task {
            message = await connect(pin: nil)
            busyIP = nil
        }
    }

    private func rename(_ saved: SavedTV, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        savedRaw = SavedTV.encode(SavedTV.decode(savedRaw).map { $0.ip == saved.ip ? SavedTV(ip: $0.ip, name: newName, psk: $0.psk) : $0 })
        if saved.ip == ip { name = newName }
    }

    /// Borra la tele de la lista y su cookie del llavero. Si es la actual, se desconecta y deja de reconectar al abrir.
    private func remove(_ saved: SavedTV) {
        Keychain.save(nil, saved.ip)
        savedRaw = SavedTV.encode(SavedTV.decode(savedRaw).filter { $0.ip != saved.ip })
        if savedRaw == "[]" { showSaved = false }
        guard saved.ip == ip else { return }
        ip = ""
        psk = ""
        name = ""
        tv = TV()
        message = nil
    }

    /// Devuelve el error que hay que enseñar, o nil si ya está conectada (o pide PIN).
    private func connect(pin: String?) async -> String? {
        tv.ip = ip
        tv.psk = psk
        do {
            try await tv.connect(pin: pin)
            let list = SavedTV.saving(SavedTV(ip: ip, name: name.isEmpty ? ip : name, psk: psk), in: SavedTV.decode(savedRaw))
            savedRaw = SavedTV.encode(list)
            name = list[0].name
            stage = .remote
            return nil
        } catch TV.Failure.needsPin {
            stage = .pin
            return pin == nil ? nil : String(localized: "PIN incorrecto. Revisa el código de la tele.")
        } catch {
            return error.localizedDescription
        }
    }
}

/// Teles a las que se ha conectado, la última primero. Van en JSON en "tvs"; la actual sigue en "ip", "psk" y "name".
struct SavedTV: Codable, Equatable, Identifiable {
    var ip: String
    var name: String
    var psk: String
    var id: String { ip }

    static func decode(_ raw: String) -> [SavedTV] {
        (try? JSONDecoder().decode([SavedTV].self, from: Data(raw.utf8))) ?? []
    }

    static func encode(_ tvs: [SavedTV]) -> String {
        String(decoding: (try? JSONEncoder().encode(tvs)) ?? Data("[]".utf8), as: UTF8.self)
    }

    /// Pone `tv` la primera. Si ya estaba (misma IP), conserva el nombre que le dio el usuario.
    static func saving(_ tv: SavedTV, in list: [SavedTV]) -> [SavedTV] {
        var tv = tv
        if let old = list.first(where: { $0.ip == tv.ip }) { tv.name = old.name }
        return [tv] + list.filter { $0.ip != tv.ip }
    }
}

/// Continúa la pantalla de lanzamiento (fondo e icono en el mismo sitio) y añade nombre y firma.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("Fondo")
            Image("Splash")
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.line))
            Text("Quién Manda")
                .font(.display(40))
                .offset(y: 66 + 24 + 22)
            VStack(spacing: 2) {
                Text("Hecha por").foregroundStyle(Color.muted)
                Text("Salva Tejero Software Company").fontWeight(.semibold)
            }
            .font(.system(size: 13))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 48)
        }
        .foregroundStyle(Color.ink)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }
}

struct DiscoverView: View {
    let discovery: Discovery
    let busyIP: String?
    var onClose: (() -> Void)?
    var onSaved: (() -> Void)?
    var onPick: (FoundTV) -> Void
    var onManual: (_ ip: String, _ psk: String) -> Void
    @Environment(\.k) private var k
    @State private var manual = false
    @State private var manualIP = ""
    @State private var manualPSK = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * k) {
            HStack {
                if let onSaved {
                    Button(action: onSaved) { Icon("menu") }
                        .buttonStyle(KeyStyle(kind: .ghost))
                        .frame(width: 44 * k, height: 44 * k)
                        .accessibilityLabel("Mis teles")
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) { Icon("cerrar") }
                        .buttonStyle(KeyStyle(kind: .ghost))
                        .frame(width: 44 * k, height: 44 * k)
                        .accessibilityLabel("Cerrar")
                }
            }
            .frame(height: 44 * k)

            VStack(alignment: .leading, spacing: 8 * k) {
                Text("Busca tu tele").font(.display(32 * k))
                Text(scanText)
                    .font(.system(size: 17 * k))
                    .foregroundStyle(Color.muted)
            }

            Radar(scanning: discovery.isScanning)
                .frame(width: 176 * k, height: 176 * k)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(spacing: 8 * k) {
                    ForEach(discovery.tvs) { found in
                        Button { onPick(found) } label: { row(found) }
                            .buttonStyle(KeyStyle())
                            .frame(height: 68 * k)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: discovery.tvs)
            }
            .disabled(busyIP != nil)

            VStack(spacing: 12 * k) {
                Button(action: discovery.start) {
                    Label { Text("Buscar de nuevo") } icon: { Icon("actualizar", size: 20) }
                }
                .buttonStyle(KeyStyle())
                .frame(height: 52 * k)
                .disabled(discovery.isScanning)
                Button("Escribir la IP") { manual = true }
                    .buttonStyle(KeyStyle(kind: .ghost))
                    .frame(height: 44 * k)
                Text("¿No aparece tu tele? Comprueba que está encendida y conectada a la misma red Wi-Fi.")
                    .font(.system(size: 13 * k))
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(EdgeInsets(top: 20 * k, leading: 20 * k, bottom: 24 * k, trailing: 20 * k))
        .onAppear(perform: discovery.start)
        .onDisappear(perform: discovery.stop)
        .alert("Escribir la IP", isPresented: $manual) {
            TextField("192.0.2.20", text: $manualIP).keyboardType(.decimalPad)
            SecureField("Pre-Shared Key (opcional)", text: $manualPSK)
            Button("Conectar") { onManual(manualIP, manualPSK) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Sin PSK, la tele mostrará un PIN.")
        }
    }

    private var scanText: String {
        let n = discovery.tvs.count
        if discovery.isScanning {
            return switch n {
            case 0: String(localized: "Buscando televisores en tu red Wi-Fi…")
            case 1: String(localized: "Buscando… 1 encontrada")
            default: String(localized: "Buscando… \(n) encontradas")
            }
        }
        return switch n {
        case 0: String(localized: "No se ha encontrado ninguna tele en esta red.")
        case 1: String(localized: "1 tele encontrada. Elige la tuya.")
        default: String(localized: "\(n) teles encontradas. Elige la tuya.")
        }
    }

    private func row(_ found: FoundTV) -> some View {
        HStack(spacing: 12 * k) {
            Icon("tele", size: 22)
                .foregroundStyle(Color.s100)
                .frame(width: 44 * k, height: 44 * k)
                .background(Color.ink, in: .rect(cornerRadius: 8 * k))
            VStack(alignment: .leading, spacing: 0) {
                Text(found.name).font(.system(size: 15 * k, weight: .semibold))
                Text(found.ip).font(.system(size: 13 * k)).foregroundStyle(Color.muted)
            }
            Spacer()
            if busyIP == found.ip { ProgressView() } else { Icon("derecha") }
        }
        .padding(.horizontal, 12 * k)
    }
}

/// Teles guardadas: tocar conecta; deslizar renombra o borra.
struct SavedTVsSheet: View {
    let tvs: [SavedTV]
    let current: String?
    var onPick: (SavedTV) -> Void
    var onRename: (SavedTV, String) -> Void
    var onRemove: (SavedTV) -> Void
    var onClose: () -> Void
    @Environment(\.k) private var k
    @State private var renaming: SavedTV?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            HStack {
                Text("Mis teles").font(.display(24 * k, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { Icon("cerrar") }
                    .buttonStyle(KeyStyle(kind: .ghost))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Cerrar")
            }
            .padding(.horizontal, 20 * k)
            Text("Toca una para conectarte. Desliza a la izquierda para renombrarla u olvidarla.")
                .font(.system(size: 13 * k))
                .foregroundStyle(Color.muted)
                .padding(.horizontal, 20 * k)
            List(tvs) { saved in
                Button { onPick(saved) } label: { row(saved) }
                    .buttonStyle(KeyStyle())
                    .frame(height: 68 * k)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4 * k, leading: 20 * k, bottom: 4 * k, trailing: 20 * k))
                    .swipeActions {
                        Button("Olvidar", role: .destructive) { onRemove(saved) }
                        Button("Renombrar") { newName = saved.name; renaming = saved }.tint(Color.verde)
                    }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 16 * k)
        .foregroundStyle(Color.ink)
        .alert("Renombrar", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Guardar") { if let renaming { onRename(renaming, newName) } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func row(_ saved: SavedTV) -> some View {
        HStack(spacing: 12 * k) {
            Icon("tele", size: 22)
                .foregroundStyle(Color.s100)
                .frame(width: 44 * k, height: 44 * k)
                .background(Color.ink, in: .rect(cornerRadius: 8 * k))
            VStack(alignment: .leading, spacing: 0) {
                Text(saved.name).font(.system(size: 15 * k, weight: .semibold)).lineLimit(1)
                Text(saved.ip == current ? "\(saved.ip) · Conectada" : "\(saved.ip)")
                    .font(.system(size: 13 * k)).foregroundStyle(Color.muted)
            }
            Spacer()
            Icon("derecha")
        }
        .padding(.horizontal, 12 * k)
    }
}

/// Ondas verdes que salen de la tele mientras se busca.
struct Radar: View {
    let scanning: Bool
    @Environment(\.k) private var k
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if scanning {
                if reduceMotion {
                    Circle().strokeBorder(Color.verde, lineWidth: 2).opacity(0.25)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3) { i in
                                let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                Circle().strokeBorder(Color.verde, lineWidth: 2)
                                    .scaleEffect(0.3 + 0.7 * p)
                                    .opacity(0.7 * (1 - p))
                            }
                        }
                    }
                }
            }
            Icon("tele", size: 32)
                .foregroundStyle(Color.onVerde)
                .frame(width: 72 * k, height: 72 * k)
                .background(Color.verde, in: .circle)
        }
        .accessibilityHidden(true)
    }
}

struct PinView: View {
    let name: String
    var onBack: () -> Void
    /// Devuelve el error, o nil si el PIN vale.
    var onSubmit: (String) async -> String?
    @Environment(\.k) private var k
    @State private var pin = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * k) {
            Button(action: onBack) { Icon("izquierda") }
                .buttonStyle(KeyStyle(kind: .ghost))
                .frame(width: 44 * k, height: 44 * k)
                .accessibilityLabel("Volver")

            VStack(alignment: .leading, spacing: 8 * k) {
                Text("Introduce el PIN").font(.display(32 * k))
                Text("Mira la pantalla de **\(name)**: te mostrará un código de 4 dígitos.")
                    .font(.system(size: 17 * k))
                    .foregroundStyle(Color.muted)
            }

            HStack(spacing: 12 * k) {
                ForEach(0..<4) { i in
                    Text(i < pin.count ? String(Array(pin)[i]) : "")
                        .font(.display(32 * k))
                        .frame(maxWidth: .infinity)
                        .frame(height: 72 * k)
                        .background(Color.s200, in: .rect(cornerRadius: 8 * k))
                        .overlay(RoundedRectangle(cornerRadius: 8 * k).strokeBorder(boxColor(i), lineWidth: 2))
                }
            }
            .accessibilityElement()
            .accessibilityLabel("PIN: \(pin.count) de 4 dígitos")

            Text(checking ? "Conectando…" : error ?? "Escríbelo tal y como aparece.")
                .font(.system(size: 15 * k))
                .foregroundStyle(error == nil ? Color.muted : .rojo)
                .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: 0)

            LazyVGrid(columns: Array(repeating: GridItem(spacing: 12 * k), count: 3), spacing: 12 * k) {
                ForEach(1..<10) { pad(String($0)) }
                Color.clear
                pad("0")
                Button { pin = String(pin.dropLast()); error = nil } label: { Icon("borrar") }
                    .buttonStyle(KeyStyle(kind: .ghost))
                    .frame(height: 60 * k)
                    .accessibilityLabel("Borrar")
            }
            .disabled(checking)
        }
        .padding(EdgeInsets(top: 20 * k, leading: 20 * k, bottom: 24 * k, trailing: 20 * k))
    }

    private func boxColor(_ i: Int) -> Color {
        if error != nil { return .rojo }
        return !checking && i == pin.count ? .verde : .line
    }

    private func pad(_ d: String) -> some View {
        Button {
            if error != nil { pin = ""; error = nil }
            guard pin.count < 4 else { return }
            pin += d
            guard pin.count == 4 else { return }
            checking = true
            Task {
                error = await onSubmit(pin)
                checking = false
                if error != nil { pin = "" }
            }
        } label: {
            Text(d).font(.display(28 * k, .bold))
        }
        .buttonStyle(KeyStyle())
        .frame(height: 60 * k)
        .accessibilityLabel("Tecla \(d)")
    }
}
