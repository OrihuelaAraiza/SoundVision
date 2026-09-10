import Foundation

/// Se comprueba cada voz por separado: sumar bloques ocultaba una rama parada
/// cuando la voz de la entrada de Play seguía funcionando.
struct VoiceRenderHealth {
    private var lastBlocks: Int?
    private var lastProgressTime: TimeInterval?
    private var lastRestartTime: TimeInterval?
    private var restartAttempts = 0
    private(set) var isStalled = false

    /// Permite dos recuperaciones por interrupción de una voz. Si no funcionan,
    /// conserva el diagnóstico sin entrar en un bucle de stop/play.
    mutating func needsRestart(blocks: Int, isPlaying: Bool, now: TimeInterval) -> Bool {
        if let lastBlocks, blocks > lastBlocks, isPlaying {
            lastProgressTime = now
            restartAttempts = 0
            isStalled = false
        }
        if lastProgressTime == nil { lastProgressTime = now }
        lastBlocks = blocks
        let hasTimedOut = now - (lastProgressTime ?? now) >= 2
        isStalled = !isPlaying || hasTimedOut
        guard isStalled, restartAttempts < 2,
              now - (lastRestartTime ?? -.infinity) >= 2 else { return false }
        lastRestartTime = now
        restartAttempts += 1
        return true
    }
}
