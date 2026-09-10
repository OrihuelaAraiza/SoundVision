import RealityKit
import UIKit

/// Color y orden de los efectos, compartidos por el gizmo y por el indicador
/// del cuerpo: el mismo efecto se lee igual mire donde mire la persona.
@MainActor
enum EffectIndicatorStyle {
    /// Los tres efectos que antes se leían por el giro del organismo. El
    /// volumen se queda fuera del cuerpo: ya tiene su lectura en la etiqueta
    /// espacial y su dial en el gizmo, y una barra siempre encendida en los 32
    /// organismos sería ruido en vez de información.
    static let bodyParameters: [SoundParameter] = [.reverb, .delay, .distortion]

    static func color(for parameter: SoundParameter) -> UIColor {
        switch parameter {
        case .reverb: .systemPurple
        case .delay: .systemCyan
        case .distortion: .systemOrange
        case .volume: .systemMint
        }
    }
}

/// Una barra por efecto sobre el organismo.
///
/// Antes reverb, delay y distorsión se leían por la inclinación del cuerpo:
/// subir un efecto tumbaba el modelo. Eso gastaba la orientación —que es del
/// espacio, no del sonido— en un dato que además se volvía ambiguo, porque dos
/// giros distintos podían dejar el organismo con el mismo aspecto. Ahora cada
/// efecto tiene su propia barra, que sube y baja con el valor y solo aparece
/// cuando ese efecto está en juego.
@MainActor
enum NodeEffectMeter {
    static let containerName = "node-effect-meter"
    /// Por debajo de esto el efecto no se dibuja: un organismo seco se ve
    /// limpio, y encender un efecto hace aparecer su indicador.
    static let threshold: Float = 0.02
    static let barHeight: Float = 0.085
    static let barSpacing: Float = 0.042
    /// Altura sobre el centro del organismo: por encima del cuerpo más alto
    /// —la atmósfera del Pad llega a 0.26 en su pulso— y por debajo de la
    /// etiqueta espacial, que se aparta hacia arriba. El indicador permanente
    /// se queda pegado al organismo y la lectura pasajera flota más lejos.
    static let elevation: Float = 0.33

    /// Una barra viva. Guardar las referencias al construir evita buscarlas por
    /// nombre en cada cambio de valor.
    struct Bar {
        let parameter: SoundParameter
        let group: Entity
        let fill: ModelEntity
    }

    static func make() -> (container: Entity, bars: [Bar]) {
        let container = Entity()
        container.name = containerName
        container.position = [0, elevation, 0]
        // Mira a la persona por su cuenta. La contrarrotación del cuerpo la
        // aplica `NodeAnimationSystem`; aquí solo hace falta que el texto y las
        // barras no queden de canto desde ningún sitio de la sala.
        container.components.set(BillboardComponent())

        let count = EffectIndicatorStyle.bodyParameters.count
        let bars = EffectIndicatorStyle.bodyParameters.enumerated().map { index, parameter -> Bar in
            let color = EffectIndicatorStyle.color(for: parameter)
            let group = Entity()
            group.name = "effect-bar-\(parameter.rawValue)"
            group.position = [(Float(index) - Float(count - 1) / 2) * barSpacing, 0, 0]
            group.isEnabled = false
            container.addChild(group)

            let track = ModelEntity(
                mesh: .generateBox(width: 0.017, height: barHeight, depth: 0.005),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.16))]
            )
            track.name = "effect-bar-track"
            group.addChild(track)

            // La malla mide la pista entera y se escala en Y: subir el efecto
            // solo cambia una transformada, nunca tesela una malla nueva.
            let fill = ModelEntity(
                mesh: .generateBox(width: 0.017, height: barHeight, depth: 0.006),
                materials: [UnlitMaterial(color: color)]
            )
            fill.name = "effect-bar-fill"
            group.addChild(fill)
            return Bar(parameter: parameter, group: group, fill: fill)
        }
        return (container, bars)
    }

    /// `levels` llega en porcentaje entero, que es la resolución del gizmo y de
    /// la consola: así el indicador solo se toca cuando el valor cambia de
    /// verdad, no en cada frame de un arrastre.
    static func update(bars: [Bar], levels: SIMD3<Int32>) {
        for (index, bar) in bars.enumerated() where index < 3 {
            let value = max(0, min(Float(levels[index]) / 100, 1))
            let isVisible = value >= threshold
            if bar.group.isEnabled != isVisible { bar.group.isEnabled = isVisible }
            guard isVisible else { continue }
            bar.fill.scale.y = value
            bar.fill.position.y = -barHeight / 2 + value * barHeight / 2
        }
    }

    /// Porcentaje entero de los tres efectos del nodo.
    static func levels(reverb: Float, delay: Float, distortion: Float) -> SIMD3<Int32> {
        func percent(_ value: Float) -> Int32 {
            guard value.isFinite else { return 0 }
            return Int32((max(0, min(value, 1)) * 100).rounded())
        }
        return SIMD3(percent(reverb), percent(delay), percent(distortion))
    }
}
