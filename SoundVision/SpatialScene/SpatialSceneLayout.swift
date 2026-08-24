import Foundation
import simd

enum SpatialSceneLayout {
    /// El origen de ImmersiveSpace está a nivel del suelo. Los nodos ya guardan
    /// alturas humanas, por lo que la raíz no debe volver a bajarlos.
    static let rootPosition = SIMD3<Float>(0, 0, -1.65)

    /// Orientación de un tramo que va de un punto a otro.
    ///
    /// `simd_quatf(from:to:)` con un vector degenerado devuelve un cuaternión
    /// con NaN, y una entidad con NaN en su transformada revienta RealityKit en
    /// cuanto entra en la simulación. Y ocurre con solo colocar un organismo
    /// exactamente encima del núcleo Play —algo que los sliders de posición
    /// permiten hacer sin esfuerzo—, así que aquí se devuelve una orientación
    /// neutra en vez de propagar el veneno.
    static func segmentOrientation(from source: SIMD3<Float>, to destination: SIMD3<Float>) -> simd_quatf {
        let vector = destination - source
        let length = simd_length(vector)
        guard length > 0.0005, vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else {
            return simd_quatf(angle: 0, axis: [0, 1, 0])
        }
        return simd_quatf(from: [0, 1, 0], to: vector / length)
    }

    /// Longitud utilizable de ese mismo tramo: nunca cero, para que escalar la
    /// geometría no colapse la malla.
    static func segmentLength(from source: SIMD3<Float>, to destination: SIMD3<Float>) -> Float {
        let length = simd_length(destination - source)
        return length.isFinite ? max(length, 0.001) : 0.001
    }
}
