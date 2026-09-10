import SwiftUI

/// Vocabulario visual compartido. Sin desenfoques animados ni tareas por tarjeta.
enum StudioDesign {
    static let ink = Color(red: 0.025, green: 0.045, blue: 0.10)
    static let accent = Color(red: 0.3, green: 0.9, blue: 0.95)
}

struct StudioBackdrop: View {
    var body: some View {
        LinearGradient(colors: [StudioDesign.ink.opacity(0.93), Color(red: 0.09, green: 0.075, blue: 0.17).opacity(0.85)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                RadialGradient(colors: [.cyan.opacity(0.10), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 350)
            }
            .allowsHitTesting(false)
    }
}

struct StudioCard<Content: View>: View {
    var tint: Color = .cyan
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(tint.opacity(0.055), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.09), lineWidth: 1) }
    }
}

struct StudioHeading: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(StudioDesign.accent)
            Text(title).font(.system(.title2, design: .rounded).weight(.bold))
            if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Ilustración del carácter del timbre; no simula un medidor de audio.
struct InstrumentGlyph: View {
    let type: SoundNodeType
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let seed = Double(VoiceSynthesis.seed(for: type) % 17 + 2)
            for index in 0...80 {
                let x = Double(index) / 80
                let envelope = VoiceSynthesis.isPercussive(type) ? exp(-x * 3.5) : sin(x * .pi)
                let y = sin(x * .pi * seed) * envelope * 0.35
                let point = CGPoint(x: x * size.width, y: size.height * (0.5 + y))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Color(uiColor: NodeVisualStyle.style(for: type).color)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct SoundLibraryView: View {
    @EnvironmentObject private var state: CompositionState
    @AppStorage("soundvision.favoriteSounds") private var storedFavorites = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var family: SoundFamily?
    @State private var search = ""
    @State private var onlyFavorites = false

    private var favorites: Set<String> { Set(storedFavorites.split(separator: ",").map(String.init)) }
    private var results: [SoundNodeType] {
        SoundNodeType.allCases.filter { type in
            (family == nil || type.family == family)
                && (!onlyFavorites || favorites.contains(type.rawValue))
                && (search.isEmpty || SoundNodeType.displayName(for: type).localizedStandardContains(search)
                    || type.character.localizedStandardContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioHeading(eyebrow: "Biblioteca · \(SoundNodeType.allCases.count) timbres", title: "Encuentra tu sonido",
                          detail: "Percusión, melodías y atmósferas para construir tu próxima idea.")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar un sonido", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Borrar búsqueda")
                }
                Button { onlyFavorites.toggle() } label: {
                    Image(systemName: onlyFavorites ? "star.fill" : "star")
                        .foregroundStyle(onlyFavorites ? .yellow : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel(onlyFavorites ? "Mostrar todos los sonidos" : "Mostrar favoritos")
            }
            .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 16))

            Picker("Familia", selection: $family) {
                Text("Todos").tag(nil as SoundFamily?)
                ForEach(SoundFamily.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.menu)

            if results.isEmpty {
                ContentUnavailableView(onlyFavorites ? "Sin favoritos aquí" : "No encontramos ese sonido",
                    systemImage: onlyFavorites ? "star" : "magnifyingglass",
                    description: Text("Prueba otra familia o cambia la búsqueda."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 175), spacing: 12)], spacing: 12) {
                ForEach(results, id: \.self) { type in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: SoundNodeType.icon(for: type))
                                .foregroundStyle(Color(uiColor: NodeVisualStyle.style(for: type).color))
                            Spacer()
                            Button {
                                var values = favorites
                                if values.contains(type.rawValue) { values.remove(type.rawValue) } else { values.insert(type.rawValue) }
                                storedFavorites = values.sorted().joined(separator: ",")
                            } label: {
                                Image(systemName: favorites.contains(type.rawValue) ? "star.fill" : "star")
                                    .foregroundStyle(favorites.contains(type.rawValue) ? .yellow : .secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(favorites.contains(type.rawValue) ? "Quitar de" : "Añadir a") favoritos: \(SoundNodeType.displayName(for: type))")
                        }
                        Button {
                            state.createNode(of: type)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                InstrumentGlyph(type: type).frame(height: 36)
                                Text(SoundNodeType.displayName(for: type)).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                                Text(type.character).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Text("Añadir").font(.caption.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(StudioDesign.accent)
                                }.padding(.top, 5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).hoverEffect(.highlight)
                        .disabled(state.nodes.count >= SoundNode.maximumCount)
                        .accessibilityLabel("Añadir \(SoundNodeType.displayName(for: type))")
                    }
                    .padding(14)
                    .background(.white.opacity(0.045), in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.09), lineWidth: 1) }
                }
            }
            if state.nodes.count >= SoundNode.maximumCount {
                Label("32 sonidos en el espacio. Retira uno para añadir otro.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let node = state.selectedNode {
                StudioCard {
                    Text("Última selección · \(node.name)").font(.callout.bold())
                    HStack {
                        Button { state.previewSelectedNode() } label: { Label("Escuchar solo", systemImage: "speaker.wave.2") }
                            .disabled(!node.isActive || state.graphTransport.isPlaying)
                        Spacer()
                        Button("Editar") { state.studioSection = .node }
                    }.buttonStyle(.bordered)
                    if state.graphTransport.isPlaying {
                        Text("El sonido de la pista se edita en vivo desde Nodo.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct StudioEmblem: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            for ring in [0.68, 1.0] {
                let r = radius * ring
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.14)), lineWidth: 1)
            }
            for index in 0..<6 {
                let angle = Double(index) / 6 * .pi * 2 - .pi / 2
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                var line = Path(); line.move(to: center); line.addLine(to: point)
                context.stroke(line, with: .color(.cyan.opacity(0.25)), lineWidth: 1.5)
                let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: rect), with: .color(index.isMultiple(of: 2) ? .cyan : .purple))
            }
            let core = CGRect(x: center.x - 25, y: center.y - 25, width: 50, height: 50)
            context.fill(Path(ellipseIn: core), with: .color(.cyan.opacity(0.12)))
            context.stroke(Path(ellipseIn: core), with: .color(.cyan.opacity(0.7)), lineWidth: 1.5)
            var play = Path()
            play.move(to: CGPoint(x: center.x - 5, y: center.y - 9))
            play.addLine(to: CGPoint(x: center.x + 10, y: center.y))
            play.addLine(to: CGPoint(x: center.x - 5, y: center.y + 9)); play.closeSubpath()
            context.fill(play, with: .color(.cyan))
        }.accessibilityHidden(true)
    }
}
