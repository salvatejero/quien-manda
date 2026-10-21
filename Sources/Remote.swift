import SwiftUI

struct RemoteView: View {
    let tv: TV
    let name: String
    var onDevices: () -> Void
    @Environment(\.k) private var k
    @Environment(\.wide) private var wide
    @AppStorage("fab") private var fab = true
    @State private var page = UserDefaults.standard.integer(forKey: "page")
    @State private var status = "Lista para enviar órdenes"
    @State private var failed = false
    @State private var volume: TV.Volume?
    @State private var channel = ""
    @State private var input = ""
    @State private var showApps = UserDefaults.standard.string(forKey: "sheet") == "apps"
    @State private var showSettings = UserDefaults.standard.string(forKey: "sheet") == "settings"
    @State private var taps = 0

    private let pages = ["Mando", "Números", "Atajos"]

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
                    .overlay(alignment: .topTrailing) {
                        if fab { fabButton.padding(.top, 480 * k).offset(x: 16 * k) }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 16 * k) {
                        tabs(1..<3)
                        TabView(selection: $page) {
                            numeros.tag(1)
                            atajos.tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
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
                        mando.tag(0)
                        numeros.tag(1)
                        atajos.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    dots(0..<3)
                }
                .overlay(alignment: .topTrailing) {
                    if fab && page == 0 { fabButton.padding(.top, 536 * k).offset(x: 8 * k) }
                }
            }
        }
        .padding(EdgeInsets(top: 20 * k, leading: 20 * k, bottom: 24 * k, trailing: 20 * k))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .task { volume = try? await tv.volume() }
        .sheet(isPresented: $showApps) {
            AppsSheet(tv: tv, onOpen: { app in run("Abrir \(app)") { try await tv.openApp(app) }; showApps = false },
                      onTVApps: { send("Apps de la tele", ["ApplicationLauncher", "Apps"]); showApps = false },
                      onSettings: { showApps = false; showSettings = true },
                      onClose: { showApps = false })
                .environment(\.k, k)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.s100)
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
            .padding(4 * k)
            .background(Color.s100, in: .circle)
            .accessibilityLabel("Apps")
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12 * k) {
            Button(action: onDevices) { Icon("menu", size: 24) }
                .buttonStyle(KeyStyle(kind: .ghost))
                .frame(width: 44 * k, height: 44 * k)
                .accessibilityLabel("Elegir dispositivo")
            VStack(alignment: .leading, spacing: 0) {
                Text(tv.model).font(.display(20 * k)).lineLimit(1)
                HStack(spacing: 8 * k) {
                    Circle().fill(tv.isOn ? Color.verde : .muted).frame(width: 8 * k, height: 8 * k)
                    Text("\(name) · \(tv.isOn ? "Conectada" : "En espera")").lineLimit(1)
                }
                .font(.system(size: 13 * k))
                .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { run(tv.isOn ? "Apagar" : "Encender") { try await tv.togglePower() } } label: {
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
                Button(pages[n]) { withAnimation { page = n } }
                    .buttonStyle(KeyStyle(kind: page == n ? .primary : .tab))
                    .frame(height: 44 * k)
                    .accessibilityAddTraits(page == n ? .isSelected : [])
            }
        }
        .padding(4 * k)
        .modifier(Card(radius: 8))
    }

    private var statusRow: some View {
        HStack(spacing: 12 * k) {
            Text(status).lineLimit(1).foregroundStyle(failed ? Color.rojo : .muted)
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
                .accessibilityLabel("Pantalla \(pages[n])")
                .accessibilityAddTraits(page == n ? .isSelected : [])
            }
        }
        .frame(height: 24 * k)
    }

    // MARK: - Mando

    private var mando: some View {
        VStack(spacing: 14 * k) {
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
            }
            HStack(spacing: 10 * k) {
                key("Retroceder", ["Rewind"], icon: "retroceder", text: false)
                key("Reproducir", ["Play"], icon: "reproducir", text: false)
                key("Pausa", ["Pause"], icon: "pausa", text: false)
                key("Avanzar", ["Forward"], icon: "avanzar", text: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func rocker(_ label: String, up: (String, String), down: (String, String)) -> some View {
        VStack(spacing: 0) {
            key(up.0, [up.1], icon: "mas", text: false, height: nil, kind: .ghost, radius: 0)
            Text(label).font(.system(size: 13 * k, weight: .semibold)).tracking(1).foregroundStyle(Color.muted)
            key(down.0, [down.1], icon: "menos", text: false, height: nil, kind: .ghost, radius: 0)
        }
        .frame(width: 84 * k)
        .modifier(Card())
        .clipShape(.rect(cornerRadius: 16 * k))
    }

    private var dpad: some View {
        let cell = 77 * k
        let arrow = { (label: String, name: String, icon: String) in
            key(label, [name], icon: icon, text: false, height: nil, kind: .ghost, radius: 40)
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
        .padding(8 * k)
        .background(Color.s200, in: .circle)
        .overlay(Circle().strokeBorder(Color.line))
    }

    // MARK: - Números

    private var numeros: some View {
        VStack(spacing: 14 * k) {
            HStack(spacing: 8 * k) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Canal").font(.system(size: 13 * k)).foregroundStyle(Color.muted)
                    Text(channel.isEmpty ? "—" : channel).font(.display(56 * k)).frame(height: 60 * k)
                }
                Spacer()
                Button("Borrar") { channel = String(channel.dropLast()) }
                    .buttonStyle(KeyStyle(kind: .ghost, outline: .line))
                    .frame(width: 80 * k, height: 44 * k)
                key("Ir", ["Enter", "Confirm"], height: 44, kind: .primary) { channel = "" }
                    .frame(width: 60 * k)
            }
            .padding(EdgeInsets(top: 12 * k, leading: 20 * k, bottom: 12 * k, trailing: 16 * k))
            .frame(height: 96 * k)
            .modifier(Card())

            grid {
                ForEach(1..<10) { digit($0) }
                key("Info", ["Display"], height: 64)
                digit(0)
                key("Ancho", ["Wide"], height: 64)
            }
            grid {
                key("Audio", ["Audio"])
                key("Ayuda", ["Help"])
                key("TV", ["Tv"])
            }
            HStack(spacing: 12 * k) {
                ForEach([("Rojo", "Red", Color.rojo), ("Verde", "Green", .verde), ("Amarillo", "Yellow", .mostaza), ("Azul", "Blue", .azul)], id: \.0) { label, name, color in
                    Button { send("Tecla \(label.lowercased())", [name]) } label: {
                        Capsule().fill(color).frame(width: 36 * k, height: 6 * k)
                    }
                    .buttonStyle(KeyStyle())
                    .frame(height: 44 * k)
                    .disabled(!tv.has([name]))
                    .accessibilityLabel(label)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func digit(_ n: Int) -> some View {
        Button {
            send("Tecla \(n)", ["Num\(n)"])
            if channel.count < 3 { channel += "\(n)" }
        } label: {
            Text("\(n)").font(.display(28 * k, .bold))
        }
        .buttonStyle(KeyStyle())
        .frame(height: 64 * k)
        .disabled(!tv.has(["Num\(n)"]))
        .accessibilityLabel("Tecla \(n)")
    }

    private func grid(@ViewBuilder _ content: () -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(spacing: 12 * k), count: 3), spacing: 12 * k, content: content)
    }

    // MARK: - Atajos

    private var atajos: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * k) {
                grid {
                    tile("Opciones", "opciones") { send("Opciones", ["Options"]) }.disabled(!tv.has(["Options"]))
                    tile("Descubrir", "descubrir") { send("Descubrir", ["Discover"]) }.disabled(!tv.has(["Discover"]))
                    tile("Teclado", "teclado") {}.disabled(true) // ponytail: llega con setTextForm en la fase 2
                    tile("Web", "web") { send("Web", ["WebBrowser", "Internet"]) }.disabled(!tv.has(["WebBrowser", "Internet"]))
                    tile("Ajustes", "ajustes") { showSettings = true }
                    tile("Ayuda", "ayuda") { send("Ayuda", ["Help"]) }.disabled(!tv.has(["Help"]))
                }
                Text("Entradas").font(.display(24 * k, .bold)).padding(.top, 6 * k)
                VStack(spacing: 8 * k) {
                    ForEach([("HDMI 1", "Hdmi1"), ("HDMI 2", "Hdmi2"), ("HDMI 3", "Hdmi3"), ("TV digital", "Tv")], id: \.0) { label, name in
                        inputRow(label, name)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func tile(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
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

    private func inputRow(_ label: String, _ name: String) -> some View {
        let selected = input == label
        return Button {
            run("Entrada \(label)") { try await tv.press([name]) }
            input = label
        } label: {
            HStack(spacing: 12 * k) {
                Circle().strokeBorder(selected ? Color.verde : .muted, lineWidth: 2)
                    .background(selected ? Color.verde : .clear, in: .circle)
                    .frame(width: 18 * k, height: 18 * k)
                Text(label)
                Spacer()
                if selected { Text("Activa").font(.system(size: 13 * k, weight: .semibold)).foregroundStyle(Color.verde) }
            }
            .padding(.horizontal, 16 * k)
        }
        .buttonStyle(KeyStyle(outline: selected ? .verde : nil))
        .frame(height: 52 * k)
        .disabled(!tv.has([name]))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Envío

    /// Tecla IRCC: la primera de `names` que tenga la TV; si no tiene ninguna, sale deshabilitada.
    private func key(_ label: String, _ names: [String], icon: String? = nil, text: Bool = true, height: CGFloat? = 52,
                     kind: KeyStyle.Kind = .normal, radius: CGFloat = 8, outline: Color? = nil, after: @escaping () -> Void = {}) -> some View {
        Button {
            send(label, names)
            after()
        } label: {
            switch (icon, text) {
            case (let icon?, true): Label { Text(label) } icon: { Icon(icon, size: 20) }
            case (let icon?, false): Icon(icon, size: 24)
            default: Text(label)
            }
        }
        .buttonStyle(KeyStyle(kind: kind, radius: radius, outline: outline))
        .frame(height: height.map { $0 * k })
        .disabled(!tv.has(names))
        .accessibilityLabel(label)
    }

    private func send(_ label: String, _ names: [String]) {
        let audio = names.contains { ["VolumeUp", "VolumeDown", "Mute"].contains($0) }
        run(label) {
            try await tv.press(names)
            if audio { volume = try? await tv.volume() }
        }
    }

    private func run(_ label: String, _ action: @escaping () async throws -> Void) {
        taps += 1
        Task {
            do {
                try await action()
                status = "Enviado · \(label)"
                failed = false
            } catch {
                status = error.localizedDescription
                failed = true
            }
        }
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
    var body: some View {
        AsyncImage(url: icon) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(name.prefix(1))
                .font(.display(size * 0.45 * k))
                .foregroundStyle(Color.s100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ink)
        }
        .frame(width: size * k, height: size * k)
        .clipShape(.rect(cornerRadius: 8 * k))
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
                Button(action: onSettings) { Icon("ajustes") }
                    .buttonStyle(KeyStyle(kind: .ghost))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Configurar apps")
                Button(action: onClose) { Icon("cerrar") }
                    .buttonStyle(KeyStyle(kind: .ghost))
                    .frame(width: 44 * k, height: 44 * k)
                    .accessibilityLabel("Cerrar")
            }
            if apps.isEmpty {
                Text("No hay apps en el panel. Actívalas en Configuración.")
                    .font(.system(size: 15 * k))
                    .foregroundStyle(Color.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 12 * k), count: 3), spacing: 12 * k) {
                ForEach(apps, id: \.name) { app in
                    Button { onOpen(app.name) } label: {
                        VStack(spacing: 8 * k) {
                            Monogram(name: app.name, size: 44, icon: tv.icon(app.name))
                            Text(app.name).font(.system(size: 13 * k)).lineLimit(1)
                        }
                    }
                    .buttonStyle(KeyStyle())
                    .frame(height: 96 * k)
                }
            }
            Spacer(minLength: 0)
            Button(action: onTVApps) { Label { Text("Apps de la tele") } icon: { Icon("apps", size: 20) } }
                .buttonStyle(KeyStyle(kind: .primary))
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
                    Button(action: onBack) { Icon("izquierda") }
                        .buttonStyle(KeyStyle(kind: .ghost))
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
                    RoundedRectangle(cornerRadius: 8 * k).fill(Color.s200)
                        .overlay(RoundedRectangle(cornerRadius: 8 * k).strokeBorder(Color.line))
                        .padding(EdgeInsets(top: 4 * k, leading: 20 * k, bottom: 4 * k, trailing: 20 * k))
                )
            }
            .onMove { from, to in
                var list = apps
                list.move(fromOffsets: from, toOffset: to)
                raw = PanelApp.encode(list)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active)) // asas de arrastre siempre visibles
        .tint(Color.verde)
        .foregroundStyle(Color.ink)
        .background(Color.s100)
        .task {
            try? await tv.loadApps()
            raw = PanelApp.encode(PanelApp.merge(PanelApp.decode(raw), titles: tv.appTitles))
        }
    }
}
