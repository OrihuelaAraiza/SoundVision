import SwiftUI

struct MusicLearningView: View {
    @EnvironmentObject private var state: CompositionState
    @AppStorage("soundvision.completedLessons") private var completedLessons = ""
    @State private var feedback: String?
    @State private var didPass = false

    private var completed: Set<String> { Set(completedLessons.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let lesson = state.activeLesson {
                HStack {
                    Label("PRÁCTICA", systemImage: lesson.icon).foregroundStyle(.cyan)
                    Spacer()
                    Button("Terminar") { state.finishLesson() }
                        .buttonStyle(.bordered)
                }
                Text(lesson.title).font(.title2.bold())
                Text(lesson.explanation).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tu reto", systemImage: "scope").font(.headline)
                    Text(lesson.challenge)
                    Button {
                        state.studioSection = .node
                    } label: {
                        Label("Editar los sonidos", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16).background(.cyan.opacity(0.08), in: .rect(cornerRadius: 16))
                Text("Escucha con Reproducir, ajusta el ejercicio y vuelve aquí para comprobarlo.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    didPass = state.lessonHasPlayed && lesson.isComplete(state.snapshot)
                    if didPass {
                        var values = completed
                        values.insert(lesson.id)
                        completedLessons = values.sorted().joined(separator: ",")
                        feedback = lesson.success
                    } else {
                        feedback = state.lessonHasPlayed
                            ? "Todavía falta un ajuste. Revisa el reto y consulta el orden de reproducción en la pestaña Reproducir."
                            : "Primero pulsa Reproducir para escuchar el ejercicio."
                    }
                } label: {
                    Label("Comprobar ejercicio", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
                if let feedback {
                    Label(feedback, systemImage: didPass ? "checkmark.circle.fill" : "lightbulb")
                        .foregroundStyle(didPass ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Reiniciar práctica") { state.beginLesson(lesson); feedback = nil }
                    Spacer()
                    if didPass, let index = MusicLesson.allCases.firstIndex(of: lesson), index + 1 < MusicLesson.allCases.count {
                        Button("Siguiente") { state.beginLesson(MusicLesson.allCases[index + 1]) }
                    }
                }
                .buttonStyle(.bordered)
                Text("Al terminar recuperas tu composición y su historial. El progreso de aprendizaje se guarda en este dispositivo.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("APRENDER HACIENDO", systemImage: "graduationcap").font(.caption.bold()).foregroundStyle(.cyan)
                Text("Escucha. Conecta. Comprende.").font(.title2.bold())
                Text("Cuatro prácticas breves para descubrir cómo funciona la música en tu espacio.")
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(completed.count), total: Double(MusicLesson.allCases.count)) {
                    Text("\(completed.count) de \(MusicLesson.allCases.count) completadas").font(.caption)
                }
                ForEach(Array(MusicLesson.allCases.enumerated()), id: \.element.id) { index, lesson in
                    Button { state.beginLesson(lesson) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: lesson.icon).font(.title2).foregroundStyle(.cyan).frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("0\(index + 1) · \(lesson.title)").font(.headline)
                                Text("Escuchar y practicar · 3 min").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: completed.contains(lesson.id) ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(completed.contains(lesson.id) ? .green : .secondary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Tu composición queda reservada mientras practicas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: state.activeLesson) { _, _ in feedback = nil; didPass = false }
    }
}
