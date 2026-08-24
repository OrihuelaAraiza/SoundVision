import UIKit
import XCTest
@testable import SoundVision

/// Comprueba que cada texto cabe en el recuadro que lo contiene, midiéndolo con
/// las métricas reales de su fuente.
///
/// Los anchos fijos son cómodos hasta que alguien alarga una etiqueta y el texto
/// se recorta en silencio. Estas pruebas fallan en ese momento, no cuando
/// alguien lo detecta a ojo con las gafas puestas.
final class LayoutFitTests: XCTestCase {
    /// Margen sobre el ancho declarado. Las métricas de la prueba y el trazado
    /// real de SwiftUI no coinciden al píxel, así que se exige holgura.
    private let tolerance: CGFloat = 0.94

    // MARK: - Consola

    func testAxisTitlesFitTheirColumn() {
        let column: CGFloat = 116
        let font = UIFont.preferredFont(forTextStyle: .caption2)

        for title in ["Izquierda · Derecha", "Abajo · Arriba", "Lejos · Cerca"] {
            assertFits(title, font: font, within: column, label: "columna de eje")
        }
    }

    func testAxisValuesFitTheirColumn() {
        let column: CGFloat = 46
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .regular
        )
        // Los extremos del rango, con signo y dos decimales.
        for value in ["-2.40", "+2.40", "-0.05"] {
            assertFits(value, font: font, within: column, label: "valor de eje")
        }
    }

    func testTempoValueFitsItsColumn() {
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
            weight: .regular
        )
        for bpm in ["50", "120", "180"] {
            assertFits(bpm, font: font, within: 38, label: "tempo")
        }
    }

    /// Las filas del inspector no tienen ancho fijo, pero etiqueta y valor
    /// comparten una fila de 436 pt dentro de la tarjeta.
    func testInspectorRowsFitTheCard() {
        let available: CGFloat = 436
        let labelFont = UIFont.preferredFont(forTextStyle: .caption1)
        let valueFont = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold
        )

        let rows: [(String, String)] = [
            ("Altura · Nota", "Sol♯5  (+24 st)"),
            ("Profundidad · Volumen", "100 %"),
            ("Distancia · Duración", "8.00 beats"),
            ("Rotación X · Reverb", "100 %"),
            ("Rotación Y · Delay", "100 %"),
            ("Rotación Z · Distorsión", "100 %")
        ]

        for (title, value) in rows {
            let total = width(title, font: labelFont) + width(value, font: valueFont) + 16
            XCTAssertLessThan(
                total, available,
                "La fila \"\(title)\" mide \(Int(total)) pt y la tarjeta da \(Int(available))"
            )
        }
    }

    /// El nombre más largo del cajón, en una rejilla de dos columnas.
    func testInstrumentNamesFitTheGrid() {
        // 468 pt de contenido, dos columnas con 10 de separación, menos el
        // icono y el relleno del botón.
        let perButton: CGFloat = (468 - 10) / 2 - 62
        let font = UIFont.preferredFont(forTextStyle: .callout)

        for type in SoundNodeType.allCases {
            assertFits(
                SoundNodeType.displayName(for: type),
                font: font,
                within: perButton,
                label: "botón de instrumento"
            )
        }
    }

    // MARK: - Etiqueta espacial

    /// La etiqueta 3D se dibuja en un marco de 0.58 m. Se mide a un cuerpo mil
    /// veces mayor para esquivar la precisión en tamaños diminutos.
    func testSpatialReadoutFitsItsFrame() {
        let frameWidth: CGFloat = 0.58
        let font = UIFont.monospacedSystemFont(ofSize: 34, weight: .semibold)

        for type in SoundNodeType.allCases {
            // Peor caso: nombre más largo, pitch de dos cifras con signo y
            // volumen de tres cifras.
            let text = String(
                format: "%@   %+.0f st   %d%%",
                SoundNodeType.displayName(for: type),
                -24.0,
                100
            )
            let metres = width(text, font: font) / 1_000
            XCTAssertLessThan(
                metres, frameWidth,
                "\"\(text)\" mide \(metres) m y el marco da \(frameWidth) m"
            )
        }
    }

    // MARK: - Utilidades

    private func width(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func assertFits(
        _ text: String,
        font: UIFont,
        within available: CGFloat,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let measured = width(text, font: font)
        XCTAssertLessThan(
            measured, available * tolerance,
            "\"\(text)\" mide \(Int(measured)) pt y la \(label) da \(Int(available))",
            file: file,
            line: line
        )
    }
}
