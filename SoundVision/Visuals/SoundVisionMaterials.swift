import RealityKit
import UIKit

/// Paleta única del laboratorio. Mantenerla aquí evita que cada entidad invente
/// su propio lenguaje de color, brillo y transparencia.
enum SoundVisionMaterials {
    static func nodeSurface(for type: SoundNodeType, isActive: Bool, isTriggered: Bool = false) -> RealityKit.Material {
        let accent = NodeVisualStyle.style(for: type).color
        if isTriggered {
            return UnlitMaterial(color: UIColor.white.withAlphaComponent(0.98))
        }
        if isActive {
            return SimpleMaterial(color: accent.withAlphaComponent(0.88), roughness: 0.16, isMetallic: true)
        }
        return SimpleMaterial(color: UIColor(red: 0.28, green: 0.31, blue: 0.38, alpha: 0.2), roughness: 0.72, isMetallic: false)
    }

    static func accentGlow(for type: SoundNodeType, alpha: CGFloat = 0.72) -> RealityKit.Material {
        UnlitMaterial(color: NodeVisualStyle.style(for: type).color.withAlphaComponent(alpha))
    }

    static func translucentAccent(for type: SoundNodeType, alpha: CGFloat = 0.1) -> RealityKit.Material {
        SimpleMaterial(color: NodeVisualStyle.style(for: type).color.withAlphaComponent(alpha), roughness: 0.08, isMetallic: false)
    }

    static func ring(isMajor: Bool = false) -> RealityKit.Material {
        SimpleMaterial(
            color: UIColor(red: 0.72, green: 0.9, blue: 1, alpha: isMajor ? 0.48 : 0.16),
            roughness: 0.2,
            isMetallic: true
        )
    }

    static func pulse(isOnActiveStep: Bool) -> RealityKit.Material {
        UnlitMaterial(color: (isOnActiveStep ? UIColor.white : UIColor.systemCyan).withAlphaComponent(0.96))
    }

    static func core(intensity: Float) -> RealityKit.Material {
        let level = CGFloat(max(0.4, min(intensity, 1)))
        return UnlitMaterial(color: UIColor(red: 0.72, green: 0.96, blue: 1, alpha: level))
    }

    static func connection(for type: SoundNodeType, highlighted: Bool) -> RealityKit.Material {
        let alpha: CGFloat = highlighted ? 0.6 : 0.16
        return UnlitMaterial(color: NodeVisualStyle.style(for: type).color.withAlphaComponent(alpha))
    }
}
