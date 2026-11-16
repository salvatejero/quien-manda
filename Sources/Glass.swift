import SwiftUI

// Liquid Glass con la marca (Papel / Sótano). Valores del lienzo «Quién Manda — Prototipo iPhone»,
// tableros «Liquid Glass · Mando» y «Liquid Glass · Atajos y Apps».

extension Color {
    static let ground = glassDyn((0xF4F1EA, 1), (0x141110, 1))
    static let glassFill = glassDyn((0xFFFFFF, 0.52), (0xF1E6D0, 0.09))
    static let glassSheet = glassDyn((0xFFFFFF, 0.62), (0x211B17, 0.62))
    static let glassLens = glassDyn((0xFFFFFF, 0.82), (0xF1E6D0, 0.2))
    static let glassEdge = glassDyn((0xFFFFFF, 0.85), (0xF1E6D0, 0.2))
    static let glassSpec = glassDyn((0xFFFFFF, 0.95), (0xF1E6D0, 0.3))
    static let glassSpec2 = glassDyn((0x2A2118, 0.06), (0x000000, 0.25))
    static let glassShadow = glassDyn((0x2A2118, 0.14), (0x000000, 0.45))
    static let verdeGlass = glassDyn((0x35693F, 0.88), (0x6FB07C, 0.9))
    static let rojoGlass = glassDyn((0xB3342B, 0.9), (0xE0675D, 0.92))
    static let inkGlass = glassDyn((0x141110, 0.86), (0xF1E6D0, 0.9))
    static let onRojo = glassDyn((0xFFFFFF, 1), (0x141110, 1))

    private static func glassDyn(_ light: (UInt32, CGFloat), _ dark: (UInt32, CGFloat)) -> Color {
        func ui(_ c: (UInt32, CGFloat)) -> UIColor {
            UIColor(red: CGFloat(c.0 >> 16 & 0xFF) / 255, green: CGFloat(c.0 >> 8 & 0xFF) / 255, blue: CGFloat(c.0 & 0xFF) / 255, alpha: c.1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// Cristal de marca. iOS 26+: `glassEffect` nativo con el tinte de la marca. iOS 17-18: material + tinte + borde con brillo + sombra
/// (la receta del lienzo). Con «Reducir transparencia»: color plano con borde fino.
struct BrandGlass: ViewModifier {
    enum Tint { case normal, lens, sheet, verde, rojo, ink }
    var radius: CGFloat
    var tint: Tint = .normal
    var outline: Color?
    @Environment(\.k) private var k
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius * k)
        if reduceTransparency {
            content
                .background(solid, in: shape)
                .overlay(shape.strokeBorder(outline ?? .line, lineWidth: 1))
        } else if #available(iOS 26, *) {
            content
                .glassEffect(tint == .normal ? .regular : .regular.tint(fill), in: shape)
                .overlay { if let outline { shape.strokeBorder(outline, lineWidth: 1) } }
        } else {
            content
                .background(fill, in: shape) // el tinte va sobre el material (el último .background queda detrás)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(outline.map { AnyShapeStyle($0) }
                    ?? AnyShapeStyle(LinearGradient(colors: [.glassSpec, .glassEdge, .glassSpec2], startPoint: .top, endPoint: .bottom)), lineWidth: 1))
                .shadow(color: .glassShadow, radius: 12 * k, y: 8 * k)
        }
    }

    private var fill: Color {
        switch tint {
        case .normal: .glassFill
        case .lens: .glassLens
        case .sheet: .glassSheet
        case .verde: .verdeGlass
        case .rojo: .rojoGlass
        case .ink: .inkGlass
        }
    }

    private var solid: Color {
        switch tint {
        case .normal, .lens, .sheet: .s200
        case .verde: .verde
        case .rojo: .rojo
        case .ink: .ink
        }
    }
}

extension View {
    func brandGlass(radius: CGFloat, tint: BrandGlass.Tint = .normal, outline: Color? = nil) -> some View {
        modifier(BrandGlass(radius: radius, tint: tint, outline: outline))
    }
}

/// Fondo de pantalla: el color base y tres manchas difuminadas (verde, mostaza y azul) que se ven a través del cristal.
struct GlassBackground: View {
    @Environment(\.k) private var k
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.ground
                blob(.verde, 260, x: -70, y: -60, opacity: dark ? 0.34 : 0.38)
                blob(.mostaza, 280, x: geo.size.width / k - 280 + 90, y: 300, opacity: dark ? 0.26 : 0.42)
                blob(.azul, 300, x: -80, y: geo.size.height / k - 300 + 60, opacity: dark ? 0.3 : 0.5)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, _ size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle().fill(color).opacity(opacity)
            .frame(width: size * k, height: size * k)
            .blur(radius: 46 * k)
            .offset(x: x * k, y: y * k)
    }
}
