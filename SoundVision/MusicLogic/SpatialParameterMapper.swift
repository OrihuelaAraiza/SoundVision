import Foundation
import simd

enum SpatialParameterMapper {
    static let neutralHeight: Float = 1.25

    /// Pentatónica menor. Cualquier combinación de estas notas suena bien junta,
    /// que es lo que hace falta cuando se colocan organismos a ojo en el aire:
    /// la afinación deja de depender de la puntería.
    static let scaleSemitones = [0, 3, 5, 7, 10]

    /// Altura de cada grado de la escala. A ~11 cm por nota, el rango vertical
    /// útil cubre unas cuatro octavas sin exigir precisión.
    static let degreeSpacing: Float = 0.11

    /// La altura salta de nota en nota en vez de deslizarse. Antes devolvía
    /// semitonos continuos, así que un nodo podía quedar a +7.3 semitonos y la
    /// pieza entera sonaba microtonal por muy buena que fuese la síntesis.
    static func pitch(forHeight height: Float) -> Float {
        let degree = Int(((height - neutralHeight) / degreeSpacing).rounded())
        return Float(clamp(semitones(forDegree: degree), min: -24, max: 24))
    }

    static func semitones(forDegree degree: Int) -> Int {
        let count = scaleSemitones.count
        // Division floor para que los grados negativos bajen de octava bien.
        let octave = Int(floor(Double(degree) / Double(count)))
        let index = degree - octave * count
        return octave * 12 + scaleSemitones[index]
    }

    /// Nombre de la nota resultante, para que el inspector hable en términos
    /// musicales y no solo en semitonos.
    static func noteName(forSemitones semitones: Float) -> String {
        let names = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        let rounded = Int(semitones.rounded())
        // La referencia es La central: el 0 de la escala.
        let absolute = rounded + 9
        let octave = Int(floor(Double(absolute) / 12)) + 4
        let index = absolute - Int(floor(Double(absolute) / 12)) * 12
        return "\(names[index])\(octave)"
    }

    /// En coordenadas locales, un Z mayor está más cerca del usuario.
    static func volume(forDepth depth: Float) -> Float {
        clamp(0.72 + depth * 0.22, min: 0.12, max: 1)
    }

    static func durationBeats(from source: SIMD3<Float>, to destination: SIMD3<Float>) -> Double {
        let horizontal = simd_distance(SIMD2(source.x, source.z), SIMD2(destination.x, destination.z))
        return Double(clamp(horizontal * 2, min: 0.25, max: 8))
    }

    static func effects(from rotation: SIMD3<Float>) -> (reverb: Float, delay: Float, distortion: Float) {
        (
            normalizedAngle(rotation.x),
            normalizedAngle(rotation.y),
            normalizedAngle(rotation.z)
        )
    }

    private static func normalizedAngle(_ angle: Float) -> Float {
        clamp(abs(angle) / .pi, min: 0, max: 1)
    }

    private static func clamp<T: Comparable>(_ value: T, min minimum: T, max maximum: T) -> T {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
