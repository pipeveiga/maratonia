import SwiftUI
import HealthKit

// Pestaña PROGRESO (primera versión): resumen semanal, consistencia y
// volumen, calculados SIEMPRE al vuelo desde Salud (HKWorkout es la
// fuente de lo corrido — cuenta también lo que registraron otras apps)
// y desde el calendario V2 (cumplimiento del plan). Acá no se persiste
// ningún derivado: si se puede recalcular, se recalcula.
// Sin métricas fisiológicas inventadas (readiness/recovery: no).

// MARK: - Lógica pura (testeable sin Salud)

/// Una sesión reducida a lo que el progreso necesita.
struct SesionMetrica: Equatable {
    var fecha: Date
    var metros: Double
    var segundos: Double
}

/// Los números de una semana calendario.
struct ResumenSemana: Equatable, Identifiable {
    var inicio: Date          // arranque de la semana (según Calendar)
    var metros: Double = 0
    var segundos: Double = 0
    var carreras: Int = 0

    var id: Date { inicio }
    var km: Double { metros / 1000 }
}

enum CalculoProgreso {

    /// Las últimas `cuantas` semanas calendario TERMINANDO en la semana
    /// de `hoy`, más viejas primero, incluyendo las semanas en cero
    /// (una semana sin correr es un dato, no un hueco).
    static func semanas(sesiones: [SesionMetrica], cuantas: Int,
                        hoy: Date, calendario: Calendar = .current) -> [ResumenSemana] {
        guard cuantas > 0,
              let semanaActual = calendario.dateInterval(of: .weekOfYear, for: hoy)
        else { return [] }

        var resultado: [ResumenSemana] = []
        var inicio = semanaActual.start
        for _ in 0..<cuantas {
            resultado.append(ResumenSemana(inicio: inicio))
            guard let anterior = calendario.date(byAdding: .weekOfYear, value: -1, to: inicio)
            else { break }
            inicio = anterior
        }
        resultado.reverse()

        for sesion in sesiones {
            guard let semana = calendario.dateInterval(of: .weekOfYear, for: sesion.fecha),
                  let indice = resultado.firstIndex(where: { $0.inicio == semana.start })
            else { continue }
            resultado[indice].metros += sesion.metros
            resultado[indice].segundos += sesion.segundos
            resultado[indice].carreras += 1
        }
        return resultado
    }

    /// Racha de semanas CONSECUTIVAS con al menos una carrera,
    /// terminando en la semana actual (una semana actual sin carreras
    /// todavía no corta la racha: puede completarse).
    static func rachaSemanas(_ semanas: [ResumenSemana]) -> Int {
        guard !semanas.isEmpty else { return 0 }
        var racha = 0
        var esLaActual = true
        for semana in semanas.reversed() {
            if semana.carreras > 0 {
                racha += 1
            } else if esLaActual {
                // la semana en curso vacía no corta — se saltea
            } else {
                break
            }
            esLaActual = false
        }
        return racha
    }

    /// Cumplimiento del plan: de los programados cuya fecha YA PASÓ,
    /// cuántos quedaron cumplidos o parciales. El de HOY solo cuenta si
    /// ya se resolvió — un pendiente de hoy a la mañana no es deuda.
    /// Los futuros no cuentan (no se puede cumplir el martes que viene).
    static func cumplimiento(almacen: AlmacenV2, hoy: DiaLocal) -> (hechos: Int, total: Int) {
        let computables = almacen.todosLosProgramados.filter { programado in
            guard let dia = programado.dia else { return false }
            if dia < hoy { return true }
            return dia == hoy && programado.resolucion != .pendiente
        }
        let hechos = computables.filter {
            $0.resolucion == .cumplido || $0.resolucion == .parcial
        }.count
        return (hechos, computables.count)
    }

    /// La salida más larga y la de mejor ritmo promedio (mínimo 1 km
    /// para que un sprint de 200 m no figure como "mejor ritmo").
    static func destacados(_ sesiones: [SesionMetrica])
        -> (masLarga: SesionMetrica?, mejorRitmo: SesionMetrica?) {
        let masLarga = sesiones.max { $0.metros < $1.metros }
        let conRitmo = sesiones.filter { $0.metros >= 1000 && $0.segundos > 0 }
        let mejorRitmo = conRitmo.min {
            $0.segundos / $0.metros < $1.segundos / $1.metros
        }
        return (masLarga, mejorRitmo)
    }
}

// MARK: - Lector de Salud (solo lectura, al vuelo)

/// Trae las carreras (de CUALQUIER app) de las últimas semanas.
final class LectorProgreso: ObservableObject {
    @Published var sesiones: [SesionMetrica] = []
    @Published var autorizado = true   // optimista hasta saber lo contrario
    @Published var cargando = false

    private let healthStore = HKHealthStore()

    func cargar(semanas: Int = 12) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        cargando = true
        let tipos: Set<HKObjectType> = [.workoutType()]
        healthStore.requestAuthorization(toShare: [], read: tipos) { [weak self] _, _ in
            self?.consultar(semanas: semanas)
        }
    }

    private func consultar(semanas: Int) {
        let desde = Calendar.current.date(byAdding: .weekOfYear, value: -semanas, to: Date())
            ?? Date.distantPast
        let predicado = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: desde, end: nil),
        ])
        let consulta = HKSampleQuery(
            sampleType: .workoutType(), predicate: predicado, limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                               ascending: true)]) { [weak self] _, muestras, error in
            let carreras = (muestras as? [HKWorkout] ?? []).map { workout in
                SesionMetrica(
                    fecha: workout.endDate,
                    metros: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter()) ?? 0,
                    segundos: workout.duration)
            }
            DispatchQueue.main.async {
                self?.sesiones = carreras
                self?.cargando = false
                // Sin permiso, la consulta vuelve vacía sin error claro:
                // solo se avisa si tampoco hay error explícito.
                self?.autorizado = error == nil
            }
        }
        healthStore.execute(consulta)
    }
}

// MARK: - Pestaña Progreso

struct ProgresoTab: View {
    @ObservedObject var almacen: AlmacenStore
    @StateObject private var lector = LectorProgreso()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DV2.Espacio.xl) {
                    let semanas = CalculoProgreso.semanas(sesiones: lector.sesiones,
                                                          cuantas: 8, hoy: Date())
                    heroSemana(semanas)
                    tarjetaVolumen(semanas)
                    tarjetaPlan
                    tarjetaConsistencia(semanas)
                    tarjetaDestacados

                    if lector.sesiones.isEmpty && !lector.cargando {
                        Text("Cuando corras (con Maratonia, el reloj o cualquier app que guarde en Salud), acá aparece tu progreso.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Progreso")
            .onAppear { lector.cargar() }
            .refreshable { lector.cargar() }
        }
    }

    // MARK: Esta semana (hero tipográfico: números grandes, sin caja)

    private func heroSemana(_ semanas: [ResumenSemana]) -> some View {
        let actual = semanas.last ?? ResumenSemana(inicio: Date())
        let anterior = semanas.dropLast().last
        return VStack(alignment: .leading, spacing: DV2.Espacio.s) {
            EncabezadoSeccionV2(texto: "Esta semana")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", actual.km))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("km")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: DV2.Espacio.xl) {
                MetricaV2(titulo: "tiempo", valor: formatearDuracion(actual.segundos))
                MetricaV2(titulo: actual.carreras == 1 ? "carrera" : "carreras",
                          valor: "\(actual.carreras)")
            }
            if let anterior, anterior.metros > 0 || actual.metros > 0 {
                Text(comparacion(actual: actual, anterior: anterior))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plan (cumplimiento)

    @ViewBuilder
    private var tarjetaPlan: some View {
        let (hechos, total) = CalculoProgreso.cumplimiento(almacen: almacen.almacen,
                                                           hoy: DiaLocal(fecha: Date()))
        if total > 0 {
            TarjetaV2 {
                VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                    EncabezadoSeccionV2(texto: "Plan")
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(hechos) de \(total)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("entrenamientos hechos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(hechos), total: Double(total))
                        .tint(.green)
                    Text("Cumplidos o parciales, sobre los que ya vencieron.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func comparacion(actual: ResumenSemana, anterior: ResumenSemana) -> String {
        let delta = actual.km - anterior.km
        if abs(delta) < 0.1 {
            return "Igual que la semana pasada (\(String(format: "%.1f", anterior.km)) km)."
        }
        let signo = delta > 0 ? "+" : "−"
        return "\(signo)\(String(format: "%.1f", abs(delta))) km vs. semana pasada (\(String(format: "%.1f", anterior.km)) km)."
    }

    // MARK: Volumen (8 semanas)

    private func tarjetaVolumen(_ semanas: [ResumenSemana]) -> some View {
        let maximo = max(semanas.map(\.km).max() ?? 0, 0.1)
        return TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Volumen · 8 semanas")
                HStack(alignment: .bottom, spacing: DV2.Espacio.s) {
                    ForEach(semanas) { semana in
                        VStack(spacing: 3) {
                            Text(semana.km >= 10
                                 ? "\(Int(semana.km.rounded()))"
                                 : String(format: "%.1f", semana.km))
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .opacity(semana.km > 0 ? 1 : 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(semana.id == semanas.last?.id
                                      ? Color.accentColor
                                      : Color.accentColor.opacity(0.35))
                                .frame(height: max(4, CGFloat(semana.km / maximo) * 80))
                            Text(etiquetaSemana(semana.inicio))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func etiquetaSemana(_ inicio: Date) -> String {
        FormatoFecha.numerica(inicio)
    }

    // MARK: Consistencia (racha)

    @ViewBuilder
    private func tarjetaConsistencia(_ semanas: [ResumenSemana]) -> some View {
        let racha = CalculoProgreso.rachaSemanas(semanas)
        if racha > 0 {
            TarjetaV2 {
                HStack(spacing: DV2.Espacio.m) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(racha == 1 ? "1 semana seguida corriendo"
                                        : "\(racha) semanas seguidas corriendo")
                            .font(.headline)
                        Text("La semana en curso todavía no corta la racha.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Destacados

    @ViewBuilder
    private var tarjetaDestacados: some View {
        let (masLarga, mejorRitmo) = CalculoProgreso.destacados(lector.sesiones)
        if masLarga != nil || mejorRitmo != nil || almacen.almacen.referenciaVigente != nil {
            TarjetaV2 {
                VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                    EncabezadoSeccionV2(texto: "Marcas · 12 semanas")
                    HStack(spacing: DV2.Espacio.xl) {
                        if let masLarga {
                            MetricaV2(titulo: "salida más larga",
                                      valor: String(format: "%.1f km", masLarga.metros / 1000))
                        }
                        if let mejorRitmo, mejorRitmo.metros > 0 {
                            MetricaV2(titulo: "mejor ritmo",
                                      valor: formatearRitmo(Int(mejorRitmo.segundos / mejorRitmo.metros * 1000)) + " /km")
                        }
                    }
                    if let referencia = almacen.almacen.referenciaVigente {
                        Text("Referencia vigente: \(String(format: "%.1f km", referencia.distanciaMetros / 1000)) en \(formatearDuracion(TimeInterval(referencia.segundos)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
