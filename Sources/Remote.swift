import StoreKit
import SwiftUI

struct RemoteView: View {
    let tv: TV
    let name: String
    var onDevices: () -> Void
    @Environment(\.k) private var k
    @Environment(\.wide) private var wide
    @AppStorage("fab") private var fab = true
    @State private var page = UserDefaults.standard.integer(forKey: "page")
    @State private var status = String(localized: "Lista para enviar órdenes")
    @State private var toast: String?
    @State private var volume: TV.Volume?
    @State private var input = ""
    @State private var showApps = UserDefaults.standard.string(forKey: "sheet") == "apps"
    @State private var showSettings = UserDefaults.standard.string(forKey: "sheet") == "settings"
    @State private var showKeyboard = UserDefaults.standard.string(forKey: "sheet") == "keyboard"
    @State private var taps = 0
    @State private var queue = CommandQueue()
    @Environment(\.scenePhase) private var scenePhase

    private let pages: [LocalizedStringResource] = ["Mando", "Números", "Atajos"]

    var body: some View {
        Group {
            if wide {
                // Mando fijo a la izquierda; Números y Atajos a la derecha. Cada uno centrado en su mitad (lejos del pliegue).
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 16 * k) {
                        header
                        statusRow
                        mando
                    }
                    .frame(width: 350 * k)
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 16 * k) {
                        tabs(1..<3)
                        TabView(selection: $page) {
                            numeros.padding(24 * k).tag(1)
                            atajos.padding(24 * k).tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .padding(-24 * k) // las sombras de las teclas no se recortan contra el TabView
                        dots(1..<3)
                    }
                    .frame(width: 350 * k)
                    .frame(maxWidth: .infinity)
                    .onAppear { page = max(page, 1) }
                }
            } else {
                VStack(spacing: 16 * k) {
                    header
                    tabs(0..<3)
                    statusRow
                    TabView(selection: $page) {
                        mando.padding(24 * k).tag(0)
                        numeros.padding(24 * k).tag(1)
                        atajos.padding(24 * k).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .padding(-24 * k) // margen interior y padding negativo: las sombras no se recortan
                    dots(0..<3)
                }
            }
        }
        .padding(EdgeInsets(top: 20 * k, leading: 20 * k, bottom: 24 * k, trailing: 20 * k))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .toast($toast)
        .task { await refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await refresh() } } }
        .sheet(isPresented: $showApps) {
            AppsSheet(tv: tv, onOpen: { app in run("Abrir \(app)") { try await tv.openApp(app) }; showApps = false },
                      onTVApps: { send("Apps de la tele", ["ApplicationLauncher", "Apps"]); showApps = false },
                      onSettings: { showApps = false; showSettings = true },
                      onClose: { showApps = false })
                .environment(\.k, k)
                .presentationDetents([.medium, .large])
                .glassSheet()
        }
        .sheet(isPresented: $showKeyboard) {
            KeyboardSheet(send: { try await tv.setText($0) }, enter: { try await tv.press(["Confirm"]) }, onClose: { showKeyboard = false })
                .environment(\.k, k)
                .presentationDetents([.height(230 * k)])
                .glassSheet()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(tv: tv) { showSettings = false }
                .environment(\.k, k)
        }
    }

    private var fabButton: some View {
        Button { showApps = true } label: { Icon("apps", size: 24) }
            .buttonStyle(KeyStyle(kind: .dark, radius: 28))
            .frame(width: 56 * k, height: 56 * k)
            .accessibilityLabel("Apps")
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12 * k) {
            Button(action: onDevices) { Icon("menu", size: 22) }
                .buttonStyle(KeyStyle(radius: 22))
                .frame(width: 44 * k, height: 44 * k)
                .accessibilityLabel("Elegir dispositivo")
            VStack(alignment: .leading, spacing: 0) {
                Text(tv.model).font(.display(20 * k)).lineLimit(1)
                HStack(spacing: 8 * k) {
                    Circle().fill(tv.isOn ? Color.verde : .muted).frame(width: 8 * k, height: 8 * k)
                    Text(tv.isOn ? "\(name) · Conectada" : "\(name) · En espera").lineLimit(1)
                }
                .font(.system(size: 13 * k))
                .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { run(tv.isOn ? "Apagar" : "Encender" as LocalizedStringResource) { try await tv.togglePower() } } label: {
                Icon("encender", size: 24)
            }
            .buttonStyle(KeyStyle(kind: .danger, radius: 22))
            .frame(width: 44 * k, height: 44 * k)
            .accessibilityLabel("Encender o apagar")
        }
    }

    private func tabs(_ shown: Range<Int>) -> some View {
        HStack(spacing: 4 * k) {
            ForEach(shown, id: \.self) { n in
                Button { withAnimation { page = n } } label: { Text(pages[n]) }
                    .buttonStyle(KeyStyle(kind: page == n ? .lens : .tab, radius: 22))
                    .frame(height: 44 * k)
                    .accessibilityAddTraits(page == n ? .isSelected : [])
            }
        }
        .padding(4 * k)
        .modifier(Card(radius: 26))
    }

    private var statusRow: some View {
        HStack(spacing: 12 * k) {
            Text(status).lineLimit(1).foregroundStyle(Color.muted)
            Spacer(minLength: 0)
            if let volume {
                Text(volume.muted ? "Silencio" : "Vol \(volume.level)")
                Capsule().fill(Color.line)
                    .frame(width: 56 * k, height: 4 * k)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.verde)
                            .frame(width: 56 * k * (volume.muted ? 0 : CGFloat(volume.level) / CGFloat(max(volume.max, 1))))
                    }
            }
        }
        .font(.system(size: 13 * k))
        .foregroundStyle(Color.muted)
        .frame(height: 20 * k)
    }

    private func dots(_ shown: Range<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(shown, id: \.self) { n in
                Button { withAnimation { page = n } } label: {
                    Capsule().fill(page == n ? Color.verde : .muted)
                        .frame(width: (page == n ? 20 : 8) * k, height: 8 * k)
                        .frame(width: 36 * k, height: 24 * k)
                }
                .accessibilityLabel("Pantalla \(String(localized: pages[n]))")
                .accessibilityAddTraits(page == n ? .isSelected : [])
            }
        }
        .frame(height: 24 * k)
    }

    // MARK: - Mando

    private var mando: some View {
        VStack(spacing: 16 * k) {
            HStack(spacing: 12 * k) {
                rocker("VOL", up: ("Subir volumen", "VolumeUp"), down: ("Bajar volumen", "VolumeDown"))
                VStack(spacing: 10 * k) {
                    key("Silencio", ["Mute"], icon: "silenciar", text: false, height: nil, outline: volume?.muted == true ? .rojo : nil)
                    Button { withAnimation { page = 2 } } label: { Label { Text("Entradas") } icon: { Icon("entradas", size: 20) } }
                        .buttonStyle(KeyStyle())
                    key("Guía", ["Guide", "EPG"], icon: "apps", height: nil)
                }
                rocker("CAN", up: ("Canal siguiente", "ChannelUp"), down: ("Canal anterior", "ChannelDown"))
            }
            .frame(height: 176 * k)

            dpad

            HStack(spacing: 10 * k) {
                key("Atrás", ["Return"], icon: "atras")
                key("Inicio", ["Home"], icon: "inicio")
                key("Menú", ["ActionMenu", "Options"], icon: "menu")
                key("TV", ["Tv"])
            }
            // Una sola barra de cristal; a su derecha, el FAB (56 + 12 de hueco = el margin-right: 68 del diseño).
            HStack(alignment: .top, spacing: 12 * k) {
                HStack(spacing: 0) {
                    key("Retroceder", ["Rewind"], icon: "retroceder", text: false, height: nil, kind: .ghost, radius: 22)
                    key("Reproducir", ["Play"], icon: "reproducir", text: false, height: nil, kind: .ghost, radius: 22)
                    key("Pausa", ["Pause"], icon: "pausa", text: false, height: nil, kind: .ghost, radius: 22)
                    key("Avanzar", ["Forward"], icon: "avanzar", text: false, height: nil, kind: .ghost, radius: 22)
                }
                .frame(height: 52 * k)
                .modifier(Card(radius: 26))
                if fab { fabButton.offset(y: 16 * k) } // el FAB queda 16 por debajo de la barra, como en el diseño
            }
            Spacer(minLength: 0)
        }
    }

    private func rocker(_ label: LocalizedStringResource, up: (LocalizedStringResource, String), down: (LocalizedStringResource, String)) -> some View {
        VStack(spacing: 0) {
            key(up.0, [up.1], icon: "mas", text: false, height: nil, kind: .ghost, radius: 0, repeats: true)
            Text(label).font(.system(size: 13 * k, weight: .semibold)).tracking(1).foregroundStyle(Color.muted)
            key(down.0, [down.1], icon: "menos", text: false, height: nil, kind: .ghost, radius: 0, repeats: true)
        }
        .frame(width: 84 * k)
        .clipShape(.rect(cornerRadius: 42 * k)) // primero se recorta el pulsado; el cristal (con su sombra) va por fuera
        .modifier(Card(radius: 42))
    }

    private var dpad: some View {
        let cell = (247 - 14) / 3 * k
        let arrow = { (label: LocalizedStringResource, name: String, icon: String) in
            key(label, [name], icon: icon, text: false, height: nil, kind: .ghost, radius: 40, repeats: true)
                .frame(width: cell, height: cell)
        }
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { Color.clear.frame(width: cell, height: cell); arrow("Arriba", "Up", "arriba"); Color.clear.frame(width: cell, height: cell) }
            GridRow {
                arrow("Izquierda", "Left", "izquierda")
                Button { send("OK", ["Confirm"]) } label: { Text("OK").font(.display(20 * k)) }
                    .buttonStyle(KeyStyle(kind: .primary, radius: 40))
                    .frame(width: cell, height: cell)
                    .accessibilityLabel("Aceptar")
                arrow("Derecha", "Right", "derecha")
            }
            GridRow { Color.clear.frame(width: cell, height: cell); arrow("Abajo", "Down", "abajo"); Color.clear.frame(width: cell, height: cell) }
        }
        .padding(7 * k)
        .brandGlass(radius: 124)
    }

    // MARK: - Números

    private var numeros: some View {
        VStack(spacing: 14 * k) {
            grid(spacing: 20) {
                ForEach(1..<10) { digit($0) }
                key("Info", ["Display"], height: 72)
                digit(0)
                key("Ancho", ["Wide"], height: 72)
            }
            grid {
                key("Audio", ["Audio"])
                key("Ayuda", ["Help"])
                key("TV", ["Tv"])
                key("Bajar volumen", ["VolumeDown"], icon: "menos", text: false, repeats: true)
                key("Silencio", ["Mute"], icon: "silenciar", text: false, outline: volume?.muted == true ? .rojo : nil)
                key("Subir volumen", ["VolumeUp"], icon: "mas", text: false, repeats: true)
            }
            HStack(spacing: 12 * k) {
                ForEach([("Tecla roja", "Red", Color.rojo), ("Tecla verde", "Green", .verde), ("Tecla amarilla", "Yellow", .mostaza), ("Tecla azul", "Blue", .azul)] as [(LocalizedStringResource, String, Color)], id: \.1) { label, name, color in
                    Button { send(label, [name]) } label: {
                        Capsule().fill(color).frame(width: 36 * k, height: 6 * k)
                    }
                    .buttonStyle(KeyStyle())
                    .frame(height: 44 * k)
                    .disabled(!tv.has([name]))
                    .accessibilityLabel(Text(label))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func digit(_ n: Int) -> some View {
        Button {
            send("Tecla \(n)", ["Num\(n)"])
        } label: {
            Text("\(n)").font(.display(28 * k, .bold))
        }
        .buttonStyle(KeyStyle())
        .frame(height: 72 * k)
        .disabled(!tv.has(["Num\(n)"]))
        .accessibilityLabel("Tecla \(n)")
    }

    private func grid(spacing: CGFloat = 12, @ViewBuilder _ content: () -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(spacing: spacing * k), count: 3), spacing: spacing * k, content: content)
    }

    // MARK: - Atajos

    private var atajos: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * k) {
                grid {
                    tile("Opciones", "opciones") { send("Opciones", ["Options"]) }.disabled(!tv.has(["Options"]))
                    tile("Descubrir", "descubrir") { send("Descubrir", ["Discover"]) }.disabled(!tv.has(["Discover"]))
                    tile("Teclado", "teclado") { showKeyboard = true }
                    tile("Web", "web") { send("Web", ["WebBrowser", "Internet"]) }.disabled(!tv.has(["WebBrowser", "Internet"]))
                    tile("Ajustes", "ajustes") { showSettings = true }
                    tile("Ayuda", "ayuda") { send("Ayuda", ["Help"]) }.disabled(!tv.has(["Help"]))
                }
                Text("Entradas").font(.display(24 * k, .bold)).padding(.top, 6 * k)
                VStack(spacing: 8 * k) {
                    ForEach([("HDMI 1", "Hdmi1"), ("HDMI 2", "Hdmi2"), ("HDMI 3", "Hdmi3"), ("HDMI 4", "Hdmi4"), ("TV digital", "Tv")] as [(LocalizedStringResource, String)], id: \.1) { label, name in
                        inputRow(label, name)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func tile(_ label: LocalizedStringResource, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Icon(icon)
                Spacer(minLength: 0)
                Text(label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14 * k)
        }
        .buttonStyle(KeyStyle())
        .frame(height: 88 * k)
    }

    private func inputRow(_ label: LocalizedStringResource, _ name: String) -> some View {
        let selected = input == name
        return Button {
            run("Entrada \(String(localized: label))") {
                try await tv.press([name])
                Task { try? await Task.sleep(for: .seconds(1.5)); await refreshInput() } // la TV tarda en cambiar
            }
            input = name
        } label: {
            HStack(spacing: 12 * k) {
                Group {
                    if selected {
                        Circle().fill(Color.verde).frame(width: 18 * k, height: 18 * k)
                    } else {
                        Circle().strokeBorder(Color.muted, lineWidth: 2).frame(width: 14 * k, height: 14 * k)
                    }
                }
                .frame(width: 18 * k, height: 18 * k) // mismo ancho para que los textos queden alineados
                Text(label)
                Spacer()
                if selected { Text("Activa").font(.system(size: 13 * k, weight: .semibold)).foregroundStyle(Color.verde) }
            }
            .padding(.horizontal, 16 * k)
        }
        .buttonStyle(KeyStyle(radius: 26, outline: selected ? .verde : nil))
        .frame(height: 52 * k)
        .disabled(!tv.has([name]))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Envío

    /// Tecla IRCC: la primera de `names` que tenga la TV; si no tiene ninguna, sale deshabilitada.
    private func key(_ label: LocalizedStringResource, _ names: [String], icon: String? = nil, text: Bool = true, height: CGFloat? = 52,
                     kind: KeyStyle.Kind = .normal, radius: CGFloat = 16, outline: Color? = nil, repeats: Bool = false, after: @escaping () -> Void = {}) -> some View {
        Button {
            send(label, names, coalescing: repeats)
            after()
        } label: {
            switch (icon, text) {
            case (let icon?, true): Label { Text(label) } icon: { Icon(icon, size: 20) }
            case (let icon?, false): Icon(icon, size: 24)
            default: Text(label)
            }
        }
        .buttonStyle(KeyStyle(kind: kind, radius: radius, outline: outline))
        .buttonRepeatBehavior(repeats ? .enabled : .disabled) // mantener pulsado repite (volumen, canal y cruceta)
        .frame(height: height.map { $0 * k })
        .disabled(!tv.has(names))
        .accessibilityLabel(Text(label))
    }

    private func send(_ label: LocalizedStringResource, _ names: [String], coalescing: Bool = false) {
        let audio = names.contains { ["VolumeUp", "VolumeDown", "Mute"].contains($0) }
        run(label, coalescing: coalescing) {
            try await tv.press(names)
            if audio { volume = try? await tv.volume() }
        }
    }

    private func refreshInput() async {
        if let current = await tv.currentInput() { input = current }
    }

    /// Al conectar y al volver a primer plano: volumen, encendido y entrada activa.
    private func refresh() async {
        volume = (try? await tv.volume()) ?? volume
        await tv.refreshPower()
        await refreshInput()
    }

    private func run(_ label: LocalizedStringResource, coalescing: Bool = false, _ action: @escaping () async throws -> Void) {
        taps += 1
        queue.enqueue(coalescing: coalescing) {
            do {
                try await action()
                status = String(localized: "Enviado · \(String(localized: label))")
            } catch {
                status = String(localized: "Sin enviar · \(String(localized: label))")
                toast = error.localizedDescription
            }
        }
    }
}

// MARK: - Cola

/// Ejecuta las órdenes una tras otra, en el orden en que se pulsaron («1» y «2» no pueden llegar como 21).
@MainActor
final class CommandQueue {
    private let continuation: AsyncStream<@MainActor @Sendable () async -> Void>.Continuation
    private var pending = 0

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: (@MainActor @Sendable () async -> Void).self)
        self.continuation = continuation
        Task { for await job in stream { await job() } }
    }

    deinit { continuation.finish() }

    /// `coalescing`: la repetición al mantener pulsado no apila órdenes; si ya hay una en vuelo, se descarta.
    /// ponytail: también descarta un toque manual muy rápido sobre estas teclas; subir el umbral si la TV tarda más de ~200 ms.
    func enqueue(coalescing: Bool = false, _ job: @escaping @MainActor @Sendable () async -> Void) {
        if coalescing && pending > 0 { return }
        pending += 1
        continuation.yield { [self] in
            await job()
            pending -= 1
        }
    }
}

// MARK: - Teclado

/// Escribe en la tele: lo tecleado sustituye el texto del campo abierto (setTextForm) y se envía con una pausa de 300 ms.
struct KeyboardSheet: View {
    var send: (String) async throws -> Void
    var enter: () async throws -> Void
    var onClose: () -> Void
    @Environment(\.k) private var k
    @State private var text = ""
    @State private var error: String?
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * k) {
            HStack(spacing: 4 * k) {
                Text("Teclado").font(.display(24 * k, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { Icon("cerrar", size: 22) }
                    .buttonStyle(KeyStyle(radius: 22))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Cerrar")
            }
            TextField("Escribe para la tele", text: $text)
                .font(.system(size: 17 * k))
                .focused($focused)
                .submitLabel(.go)
                .padding(14 * k)
                .brandGlass(radius: 16)
                .onSubmit { Task { await perform(enter) } }
                .onChange(of: text) {
                    pending?.cancel()
                    let current = text
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await perform { try await send(current) }
                    }
                }
            Text(error ?? String(localized: "Se envía mientras escribes y sustituye el texto del campo abierto en la tele."))
                .font(.system(size: 13 * k))
                .foregroundStyle(error == nil ? Color.muted : .rojo)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16 * k, leading: 20 * k, bottom: 20 * k, trailing: 20 * k))
        .onAppear { focused = true }
    }

    private func perform(_ action: () async throws -> Void) async {
        do { try await action(); error = nil } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Apps

/// Apps del panel en el orden elegido; se guardan una por línea: "1YouTube\n0Plex…".
struct PanelApp: Equatable {
    var name: String
    var on: Bool

    /// Hasta leer la lista de la TV.
    static let defaults = "1YouTube\n1Netflix\n1Prime Video\n1Apple TV\n1HBO\n0Disney+\n0Spotify\n0Plex"

    static func decode(_ raw: String) -> [PanelApp] {
        raw.split(separator: "\n").map { PanelApp(name: String($0.dropFirst()), on: $0.first == "1") }
    }

    static func encode(_ apps: [PanelApp]) -> String {
        apps.map { ($0.on ? "1" : "0") + $0.name }.joined(separator: "\n")
    }

    /// Ajusta el panel a las apps que tiene la TV: las guardadas conservan orden y estado y toman
    /// el título exacto de la TV; las nuevas van al final apagadas; las que la TV no tiene, fuera.
    static func merge(_ stored: [PanelApp], titles: [String]) -> [PanelApp] {
        guard !titles.isEmpty else { return stored }
        var result: [PanelApp] = []
        for app in stored {
            guard let title = titles.first(where: { $0.caseInsensitiveCompare(app.name) == .orderedSame })
                    ?? titles.first(where: { $0.localizedCaseInsensitiveContains(app.name) }),
                  !result.contains(where: { $0.name == title }) else { continue }
            result.append(PanelApp(name: title, on: app.on))
        }
        for title in titles where !result.contains(where: { $0.name == title }) {
            result.append(PanelApp(name: title, on: false))
        }
        return result
    }
}

/// Icono de la app que da la TV; mientras no llega (o si no hay), su inicial sobre fondo oscuro.
struct Monogram: View {
    let name: String
    let size: CGFloat
    var icon: URL?
    @Environment(\.k) private var k
    @State private var image: UIImage?

    private var radius: CGFloat { size * 0.32 } // 18 para 56
    /// Netflix en rojo y Spotify en verde, como en el diseño; el resto, cristal normal.
    private var tint: BrandGlass.Tint {
        let n = name.lowercased()
        return n.contains("netflix") ? .rojo : n.contains("spotify") ? .verde : .normal
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size * k, height: size * k).clipShape(.rect(cornerRadius: radius * k))
            } else {
                Text(name.prefix(1))
                    .font(.display(size * 0.36 * k))
                    .foregroundStyle(tint == .rojo ? Color.onRojo : tint == .verde ? .onVerde : .ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .brandGlass(radius: radius, tint: tint)
            }
        }
        .frame(width: size * k, height: size * k)
        .task(id: icon) { image = await Self.load(icon) }
    }

    static var memory: [URL: UIImage] = [:]
    /// Caches/iconos: sobrevive a los reinicios (iOS puede vaciarla si le falta espacio, y entonces se vuelven a bajar).
    static let folder = URL.cachesDirectory.appending(path: "iconos")
    /// Pasado un mes se vuelve a pedir a la TV, por si la app cambió de icono.
    static let maxAge: TimeInterval = 30 * 24 * 3600

    /// Memoria → disco (si no ha caducado) → TV → disco caducado. La TV responde
    /// "Content-Type: Content-Type: image/png" y AsyncImage lo descarta, así que se decodifica con UIImage(data:).
    static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let image = memory[url] { return image }
        let file = folder.appending(path: url.lastPathComponent) // nombre del paquete y actividad: único por app
        let saved = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        var data = saved.map { Date.now.timeIntervalSince($0) < maxAge } == true ? try? Data(contentsOf: file) : nil
        if data == nil, let (downloaded, _) = try? await URLSession.shared.data(from: url), UIImage(data: downloaded) != nil {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? downloaded.write(to: file)
            data = downloaded
        }
        if data == nil { data = try? Data(contentsOf: file) } // caducado y la TV no responde: mejor el viejo que la letra
        guard let image = data.flatMap(UIImage.init(data:)) else { return nil }
        memory[url] = image
        return image
    }
}

struct AppsSheet: View {
    let tv: TV
    var onOpen: (String) -> Void
    var onTVApps: () -> Void
    var onSettings: () -> Void
    var onClose: () -> Void
    @Environment(\.k) private var k
    @AppStorage("panelApps") private var raw = PanelApp.defaults

    var body: some View {
        let apps = PanelApp.decode(raw).filter(\.on)
        VStack(alignment: .leading, spacing: 16 * k) {
            HStack(spacing: 4 * k) {
                Text("Apps").font(.display(24 * k, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onSettings) { Icon("ajustes", size: 22) }
                    .buttonStyle(KeyStyle(radius: 22))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Configurar apps")
                Button(action: onClose) { Icon("cerrar", size: 22) }
                    .buttonStyle(KeyStyle(radius: 22))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Cerrar")
            }
            if apps.isEmpty {
                Text("No hay apps en el panel. Actívalas en Configuración.")
                    .font(.system(size: 15 * k))
                    .foregroundStyle(Color.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 8 * k), count: 4), spacing: 14 * k) {
                ForEach(apps, id: \.name) { app in
                    Button { onOpen(app.name) } label: {
                        VStack(spacing: 6 * k) {
                            Monogram(name: app.name, size: 56, icon: tv.icon(app.name))
                            Text(app.name).font(.system(size: 13 * k, weight: .regular)).lineLimit(1)
                        }
                    }
                    .buttonStyle(KeyStyle(kind: .ghost))
                }
            }
            Spacer(minLength: 0)
            Button(action: onTVApps) { Label { Text("Apps de la tele") } icon: { Icon("apps", size: 20) } }
                .buttonStyle(KeyStyle(kind: .dark, radius: 26))
                .frame(height: 52 * k)
        }
        .padding(EdgeInsets(top: 16 * k, leading: 20 * k, bottom: 28 * k, trailing: 20 * k))
        .foregroundStyle(Color.ink)
        .task {
            try? await tv.loadApps()
            raw = PanelApp.encode(PanelApp.merge(PanelApp.decode(raw), titles: tv.appTitles))
        }
    }
}

struct SettingsView: View {
    let tv: TV
    var onBack: () -> Void
    @Environment(\.k) private var k
    @AppStorage("fab") private var fab = true
    @AppStorage("panelApps") private var raw = PanelApp.defaults

    var body: some View {
        let apps = PanelApp.decode(raw)
        List {
            Group {
                HStack(spacing: 8 * k) {
                    Button(action: onBack) { Icon("izquierda", size: 22) }
                        .buttonStyle(KeyStyle(radius: 22))
                        .frame(width: 44 * k, height: 44 * k)
                        .accessibilityLabel("Volver")
                    Text("Configuración").font(.display(24 * k, .bold))
                }

                Toggle(isOn: $fab) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Botón flotante").font(.system(size: 15 * k, weight: .semibold))
                        Text("Mostrar Apps sobre el mando").font(.system(size: 13 * k)).foregroundStyle(Color.muted)
                    }
                }
                .padding(EdgeInsets(top: 12 * k, leading: 16 * k, bottom: 12 * k, trailing: 12 * k))
                .modifier(Card())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Apps del panel").font(.system(size: 17 * k, weight: .semibold))
                    Text("Activa las que quieras y arrástralas para ordenarlas.").font(.system(size: 13 * k)).foregroundStyle(Color.muted)
                }
                .padding(.top, 8 * k)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8 * k, leading: 20 * k, bottom: 8 * k, trailing: 20 * k))

            ForEach(apps, id: \.name) { app in
                HStack(spacing: 12 * k) {
                    Monogram(name: app.name, size: 36, icon: tv.icon(app.name))
                    Text(app.name).font(.system(size: 15 * k, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Mostrar \(app.name)", isOn: Binding(get: { app.on }, set: { on in
                        raw = PanelApp.encode(apps.map { $0.name == app.name ? PanelApp(name: $0.name, on: on) : $0 })
                    }))
                    .labelsHidden()
                }
                .padding(.vertical, 4 * k)
                .listRowInsets(EdgeInsets(top: 4 * k, leading: 32 * k, bottom: 4 * k, trailing: 20 * k))
                .listRowSeparator(.hidden)
                .listRowBackground(
                    Color.clear.brandGlass(radius: 16)
                        .padding(EdgeInsets(top: 4 * k, leading: 20 * k, bottom: 4 * k, trailing: 20 * k))
                )
            }
            .onMove { from, to in
                var list = apps
                list.move(fromOffsets: from, toOffset: to)
                raw = PanelApp.encode(list)
            }

            CoffeeSection()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 24 * k, leading: 20 * k, bottom: 24 * k, trailing: 20 * k))
                .moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active)) // asas de arrastre siempre visibles
        .tint(Color.verde)
        .foregroundStyle(Color.ink)
        .background { GlassBackground() }
        .task {
            try? await tv.loadApps()
            raw = PanelApp.encode(PanelApp.merge(PanelApp.decode(raw), titles: tv.appTitles))
        }
    }
}

// MARK: - Invítame a un café

/// Propina con StoreKit 2: tres consumibles que no desbloquean nada (PLAN §3).
enum Coffee {
    static let ids = ["cafe", "cafebollo", "desayuno"].map { "es.julia.angela.app.quienmanda." + $0 }

    /// Termina las compras que lleguen fuera de la vista (Ask to Buy, otra sesión…); si no, se repetirían.
    static func finishPending() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update { await transaction.finish() }
        }
    }
}

struct CoffeeSection: View {
    @Environment(\.k) private var k
    @State private var thanks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * k) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Invítame a un café").font(.system(size: 17 * k, weight: .semibold))
                Text("Quién Manda es gratis y lo seguirá siendo. Si te ahorra levantarte del sofá, puedes invitarme a algo. No desbloquea nada.")
                    .font(.system(size: 13 * k))
                    .foregroundStyle(Color.muted)
            }
            ForEach(Coffee.ids, id: \.self) { id in
                ProductView(id: id)
                    .productViewStyle(CoffeeStyle(k: k))
                    .padding(EdgeInsets(top: 10 * k, leading: 16 * k, bottom: 10 * k, trailing: 12 * k))
                    .modifier(Card())
            }
            if thanks {
                Text("¡Gracias por el café!")
                    .font(.system(size: 15 * k, weight: .semibold))
                    .foregroundStyle(Color.verde)
            }
        }
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(.verified(let transaction))) = result else { return }
            await transaction.finish()
            thanks = true
        }
    }
}

/// Fila de un café con los colores de la app: nombre, descripción y precio en el botón verde.
struct CoffeeStyle: ProductViewStyle {
    let k: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12 * k) {
            if let product = configuration.product {
                VStack(alignment: .leading, spacing: 0) {
                    Text(product.displayName).font(.system(size: 15 * k, weight: .semibold))
                    Text(product.description).font(.system(size: 13 * k)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(product.displayPrice, action: configuration.purchase)
                    .buttonStyle(KeyStyle(kind: .primary, radius: 22))
                    .frame(width: 88 * k, height: 44 * k)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44 * k)
            }
        }
    }
}
