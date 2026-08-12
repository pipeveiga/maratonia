import XCTest
@testable import Maraton

// Tests de la CALIBRACIÓN deportiva (post-auditoría del build 61).
//
// Tres bloques:
//   1. REGRESIÓN de cada P0 — cada uno reproduce el defecto tal como se
//      midió en la auditoría y verifica que ya no ocurre;
//   2. SEMÁNTICA de volumen — todos los consumidores tienen que dar el
//      mismo número;
//   3. INVARIANTES DE CATÁLOGO — recorren TODAS las semanas generables
//      de los 10 planes en TODAS las frecuencias posibles. No están
//      escritos contra la semana que encontramos rota: si mañana
//      alguien toca una progresión y desbalancea otra semana, fallan.

private let hoyTest = DiaLocal(anio: 2026, mes: 8, dia: 12)   // miércoles
private let ahoraTest = Date(timeIntervalSince1970: 1_786_536_000)

// MARK: - P0 #1 · Volumen de los bloques por tiempo

final class VolumenPlanificadoTests: XCTestCase {

    /// El caso exacto del sprint: `umbral(32′)` = 1,5 km + 32 min + 1 km.
    /// Antes contaba 2,5 km. La conversión usa el ritmo de umbral.
    func testUmbral32MinutosYaNoValeDosPuntoCinco() {
        let umbral = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "Umbral 32′",
            segmentos: [
                Segmento(nombre: "Calentamiento", distanciaKm: 1.5, ritmo: .simbolico(.facil)),
                Segmento(nombre: "Bloque", duracionSegundos: 32 * 60, ritmo: .simbolico(.umbral)),
                Segmento(nombre: "Calma", distanciaKm: 1, ritmo: .simbolico(.recuperacion)),
            ])
        XCTAssertEqual(umbral.distanciaTotalKm ?? 0, 2.5, accuracy: 0.01,
                       "la distancia DECLARADA no cambia: sigue siendo 2,5 km")
        let volumen = umbral.volumen()
        XCTAssertEqual(volumen.kmMedidos, 2.5, accuracy: 0.01)
        XCTAssertEqual(volumen.segundosPorTiempo, 32 * 60)
        XCTAssertGreaterThan(volumen.kmEquivalentes, 4,
                             "32 min a ritmo de umbral son más de 4 km")
        XCTAssertGreaterThan(volumen.totalKm, 6.5,
                             "la sesión completa supera los 6,5 km — antes valía 2,5")
        XCTAssertTrue(volumen.hayEstimacion, "sin baseline la conversión es estimada")
    }

    func testFacilPorDistanciaNoCambia() {
        let facil = DefinicionEntrenamiento(
            tipo: .facil, nombre: "Rodaje",
            segmentos: [Segmento(nombre: "Rodaje", distanciaKm: 8, ritmo: .simbolico(.facil))])
        XCTAssertEqual(facil.volumenKm(), 8, accuracy: 0.001)
        XCTAssertFalse(facil.volumen().hayEstimacion)
        XCTAssertEqual(facil.volumen().segundosPorTiempo, 0)
    }

    func testIntervalosSumanBloquesYPausas() {
        var segmentos = [Segmento(nombre: "Cal", distanciaKm: 2, ritmo: .simbolico(.facil))]
        for _ in 1...5 {
            segmentos.append(Segmento(nombre: "I", duracionSegundos: 180, ritmo: .simbolico(.intervalo)))
            segmentos.append(Segmento(nombre: "P", duracionSegundos: 120, ritmo: .simbolico(.recuperacion)))
        }
        segmentos.append(Segmento(nombre: "Calma", distanciaKm: 1, ritmo: .simbolico(.recuperacion)))
        let sesion = DefinicionEntrenamiento(tipo: .series, nombre: "5×3′", segmentos: segmentos)
        let v = sesion.volumen()
        XCTAssertEqual(v.kmMedidos, 3, accuracy: 0.01)
        XCTAssertEqual(v.segundosPorTiempo, 5 * 180 + 5 * 120)
        XCTAssertGreaterThan(v.totalKm, 7, "los intervalos y sus pausas son casi toda la sesión")
    }

    /// Un segmento con distancia Y duración se cuenta UNA vez, por
    /// distancia — la misma regla que usa `tramosEjecutables`.
    func testSegmentoMixtoNoSeCuentaDosVeces() {
        let sesion = DefinicionEntrenamiento(
            tipo: .facil, nombre: "Mixto",
            segmentos: [Segmento(nombre: "Ambos", distanciaKm: 5,
                                 duracionSegundos: 1800, ritmo: .simbolico(.facil))])
        let v = sesion.volumen()
        XCTAssertEqual(v.totalKm, 5, accuracy: 0.001)
        XCTAssertEqual(v.segundosPorTiempo, 0, "la duración se ignora si hay distancia")
    }

    func testConBaselineLaConversionUsaElRitmoRealDelCorredor() {
        let rapido = PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: ahoraTest, fuente: .test5K, distanciaMetros: 5000, segundos: 1200))
        let lento = PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: ahoraTest, fuente: .test5K, distanciaMetros: 5000, segundos: 2100))
        let bloque = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "U",
            segmentos: [Segmento(nombre: "B", duracionSegundos: 1800, ritmo: .simbolico(.umbral))])
        let kmRapido = bloque.volumenKm(baseline: rapido)
        let kmLento = bloque.volumenKm(baseline: lento)
        XCTAssertGreaterThan(kmRapido, kmLento,
                             "en 30 min el corredor rápido cubre más distancia")
        XCTAssertFalse(bloque.volumen(baseline: rapido).hayEstimacion)
        XCTAssertTrue(bloque.volumen().hayEstimacion, "sin baseline, estimado")
    }

    func testRitmoAbsolutoResueltoNoEsEstimacion() {
        let bloque = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "U",
            segmentos: [Segmento(nombre: "B", duracionSegundos: 1800,
                                 ritmo: .absoluto(minSegKm: 280, maxSegKm: 320))])
        let v = bloque.volumen()
        XCTAssertFalse(v.hayEstimacion)
        XCTAssertEqual(v.totalKm, 1800.0 / 300.0, accuracy: 0.01, "usa el punto medio")
    }

    func testRitmoLibreNoDevuelveCero() {
        // Esconder el problema devolviendo 0 es justo lo que había.
        let bloque = DefinicionEntrenamiento(
            tipo: .facil, nombre: "L",
            segmentos: [Segmento(nombre: "B", duracionSegundos: 1800, ritmo: .libre)])
        XCTAssertGreaterThan(bloque.volumenKm(), 2)
        XCTAssertTrue(bloque.volumen().hayEstimacion)
    }

    func testElRitmoDeReferenciaSaleDeLaMetodologia() {
        // No son números sueltos: salen del corredor de referencia.
        XCTAssertNotNil(RitmoDeReferencia.baseline)
        let umbral = RitmoDeReferencia.segKm(.umbral)
        let facil = RitmoDeReferencia.segKm(.facil)
        let recuperacion = RitmoDeReferencia.segKm(.recuperacion)
        XCTAssertLessThan(umbral, facil, "el umbral es más rápido que el fácil")
        XCTAssertLessThan(facil, recuperacion)
        XCTAssertGreaterThan(umbral, 200)
        XCTAssertLessThan(recuperacion, 900)
    }

    /// El volumen de la SEMANA usa la misma semántica que la sesión.
    func testVolumenSemanalSumaLoMismoQueLasSesiones() {
        let base = ContenidoPlanes.mediaMaraton()
        let plan = base.adoptar(inicio: hoyTest, fechaAdopcion: ahoraTest)
        for semana in plan.semanas {
            let suma = semana.programados.reduce(0.0) { $0 + $1.definicion.volumenKm() }
            XCTAssertEqual(semana.kmPrescritos(), suma, accuracy: 0.001)
        }
    }

    /// Las bandas del validador se derivan del volumen CORRECTO.
    func testLasReglasSemanalesUsanElVolumenCompleto() {
        let base = ContenidoPlanes.mejorar10K()
        for semana in base.semanas {
            let reglas = semana.reglasDerivadas
            let soloDistancia = semana.entrenamientos
                .flatMap(\.segmentos).compactMap(\.distanciaKm).reduce(0, +)
            guard semana.entrenamientos.contains(where: { entrenamiento in
                entrenamiento.segmentos.contains { $0.distanciaKm == nil && $0.duracionSegundos != nil }
            }) else { continue }
            XCTAssertGreaterThan(reglas.volumenObjetivoKm ?? 0, soloDistancia,
                                 "semana \(semana.numero): la banda ignoraba los bloques por tiempo")
        }
    }
}

// MARK: - P0 #1b · Reducir y convertir sobre bloques por tiempo

final class AdaptacionSobreTiempoTests: XCTestCase {

    private func almacenConUmbral() -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo(); perfil.diasElegidos = [1, 3, 5, 7]
        almacen.perfil = perfil
        let umbral = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "Umbral 32′",
            segmentos: [
                Segmento(nombre: "Cal", distanciaKm: 1.5, ritmo: .simbolico(.facil)),
                Segmento(nombre: "Bloque", duracionSegundos: 32 * 60, ritmo: .simbolico(.umbral)),
                Segmento(nombre: "Calma", distanciaKm: 1, ritmo: .simbolico(.recuperacion)),
            ])
        let programado = EntrenamientoProgramado(
            definicion: umbral, dia: hoyTest,
            rolGuardado: .calidadPrincipal, adaptabilidadGuardada: .para(.calidadPrincipal))
        almacen.planActivo = PlanUsuario(nombre: "T", fechaAdopcion: ahoraTest,
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        return almacen
    }

    /// Reducir escalaba SOLO el calentamiento: un 0,8 sobre un umbral
    /// recortaba medio kilómetro y dejaba el bloque duro entero.
    func testReducirTambienAcortaElBloquePorTiempo() {
        var almacen = almacenConUmbral()
        let id = almacen.todosLosProgramados[0].id
        let antes = almacen.todosLosProgramados[0].definicion.volumenKm()
        XCTAssertTrue(almacen.reducir(programadoID: id, factor: 0.75))
        let despues = almacen.todosLosProgramados[0]
        XCTAssertEqual(despues.definicion.volumenKm() / antes, 0.75, accuracy: 0.03,
                       "la reducción real tiene que acercarse al factor pedido")
        let bloque = despues.definicion.segmentos.first { $0.duracionSegundos != nil }
        XCTAssertEqual(bloque?.duracionSegundos ?? 0, 1440, accuracy: 30,
                       "32 min × 0,75 = 24 min")
    }

    func testReducirNoDejaBloquesAbsurdamenteCortos() {
        var almacen = almacenConUmbral()
        let id = almacen.todosLosProgramados[0].id
        XCTAssertTrue(almacen.reducir(programadoID: id, factor: 0.6))
        let bloque = almacen.todosLosProgramados[0].definicion.segmentos
            .first { $0.duracionSegundos != nil }
        XCTAssertGreaterThanOrEqual(bloque?.duracionSegundos ?? 0, 30)
        XCTAssertEqual((bloque?.duracionSegundos ?? 0) % 10, 0, "redondeado a 10 s")
    }

    /// Convertir producía un rodaje de 2,5 km a partir de una sesión de
    /// más de 6: un cuarto del trabajo original.
    func testConvertirConservaElVolumenDeLaSesion() {
        var almacen = almacenConUmbral()
        let id = almacen.todosLosProgramados[0].id
        let antes = almacen.todosLosProgramados[0].definicion.volumenKm()
        XCTAssertTrue(almacen.convertirEnFacil(programadoID: id))
        let despues = almacen.todosLosProgramados[0]
        XCTAssertEqual(despues.definicion.tipo, .facil)
        XCTAssertEqual(despues.definicion.volumenKm(), antes, accuracy: 0.15,
                       "el rodaje equivalente conserva el volumen, no la distancia declarada")
        XCTAssertGreaterThan(despues.definicion.volumenKm(), 6)
    }
}

// MARK: - P0 #3 · El validador conoce la fase

final class ValidadorFaseTests: XCTestCase {

    /// Semana con una calidad y una larga, en la fase que se indique.
    private func almacen(fase: TipoSemana?) -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo(); perfil.diasElegidos = [1, 3, 5, 6, 7]
        almacen.perfil = perfil
        func hacer(_ nombre: String, _ tipo: TipoEntrenamiento,
                   _ km: Double, _ dia: Int) -> EntrenamientoProgramado {
            let rol = RolSesion.para(tipo)
            return EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: tipo, nombre: nombre,
                    segmentos: [Segmento(nombre: nombre, distanciaKm: km, ritmo: .simbolico(.facil))]),
                dia: DiaLocal(anio: 2026, mes: 8, dia: dia),
                rolGuardado: rol, adaptabilidadGuardada: .para(rol))
        }
        let semana = SemanaPlan(numero: 1, programados: [
            hacer("Umbral", .umbral, 8, 12),
            hacer("Rodaje", .facil, 7, 14),
            hacer("Larga", .largo, 16, 16),
        ], reglas: ReglasSemana(fase: fase))
        almacen.planActivo = PlanUsuario(nombre: "T", fechaAdopcion: ahoraTest, semanas: [semana])
        return almacen
    }

    private func buscar(_ almacen: AlmacenV2, _ nombre: String) -> UUID {
        almacen.todosLosProgramados.first { $0.definicion.nombre == nombre }!.id
    }

    func testEnTaperNoSeConvierte() {
        let a = almacen(fase: .taper)
        let v = ValidadorDeCoach.validar(.convertirEnFacil(programadoID: buscar(a, "Umbral")),
                                         en: a, hoy: hoyTest)
        XCTAssertFalse(v.permitido, "el taper mantiene la intensidad y baja el volumen")
        XCTAssertNotNil(v.motivo)
    }

    func testEnTaperNoSeMueve() {
        let a = almacen(fase: .taper)
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: buscar(a, "Umbral"), a: DiaLocal(anio: 2026, mes: 8, dia: 15)),
            en: a, hoy: hoyTest).permitido)
    }

    func testEnSemanaDeCarreraTampocoSeMueve() {
        let a = almacen(fase: .semanaDeCarrera)
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: buscar(a, "Rodaje"), a: DiaLocal(anio: 2026, mes: 8, dia: 15)),
            en: a, hoy: hoyTest).permitido)
    }

    /// Lo REDUCTIVO sigue permitido: bajar carga nunca compromete un taper.
    func testEnTaperReducirSiguePermitido() {
        let a = almacen(fase: .taper)
        let v = ValidadorDeCoach.validar(.reducir(programadoID: buscar(a, "Umbral"), factor: 0.8),
                                         en: a, hoy: hoyTest)
        XCTAssertTrue(v.permitido, v.motivo ?? "")
    }

    func testEnTaperOmitirUnaFacilSiguePermitido() {
        let a = almacen(fase: .taper)
        XCTAssertTrue(ValidadorDeCoach.validar(.omitir(programadoID: buscar(a, "Rodaje")),
                                               en: a, hoy: hoyTest).permitido)
    }

    func testFueraDeTaperConvertirYMoverSiguenFuncionando() {
        let a = almacen(fase: .construccion)
        XCTAssertTrue(ValidadorDeCoach.validar(
            .convertirEnFacil(programadoID: buscar(a, "Umbral")), en: a, hoy: hoyTest).permitido)
        XCTAssertTrue(ValidadorDeCoach.validar(
            .reprogramar(programadoID: buscar(a, "Umbral"), a: DiaLocal(anio: 2026, mes: 8, dia: 19)),
            en: a, hoy: hoyTest).permitido)
    }

    /// Sin fase declarada la regla NO opina: nunca infiere un taper que
    /// el plan no declaró (planes viejos, catálogo de principiante).
    func testSinFaseDeclaradaLaReglaNoOpina() {
        let a = almacen(fase: nil)
        XCTAssertTrue(ValidadorDeCoach.validar(
            .convertirEnFacil(programadoID: buscar(a, "Umbral")), en: a, hoy: hoyTest).permitido)
    }

    func testLaCarreraObjetivoSigueIntocableEnCualquierFase() {
        for fase: TipoSemana in [.taper, .semanaDeCarrera, .construccion] {
            var a = almacen(fase: fase)
            let rol = RolSesion.para(.ritmoCarrera)
            a.planActivo!.semanas[0].programados.append(EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: .ritmoCarrera, nombre: "Carrera",
                    segmentos: [Segmento(nombre: "C", distanciaKm: 21.1)]),
                dia: DiaLocal(anio: 2026, mes: 8, dia: 19),
                rolGuardado: rol, adaptabilidadGuardada: .para(rol)))
            let id = buscar(a, "Carrera")
            XCTAssertFalse(ValidadorDeCoach.validar(.omitir(programadoID: id),
                                                    en: a, hoy: hoyTest).permitido)
            XCTAssertFalse(ValidadorDeCoach.validar(.reducir(programadoID: id, factor: 0.9),
                                                    en: a, hoy: hoyTest).permitido)
        }
    }
}

// MARK: - P0 #5 · Recorte por días

final class RecorteYRedistribucionTests: XCTestCase {

    private func volumen(_ semana: SemanaBase) -> Double {
        CalculoVolumen.volumen(semana.entrenamientos.flatMap(\.segmentos).map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
        }).totalKm
    }

    private func larga(_ semana: SemanaBase) -> Double {
        semana.entrenamientos.filter { $0.tipo == .largo }
            .map { entrenamiento in
                CalculoVolumen.volumen(entrenamiento.segmentos.map {
                    CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                           duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
                }).totalKm
            }.max() ?? 0
    }

    /// El recorte ya no tira el volumen fácil: lo reparte.
    func testRecortarConservaVolumenRedistribuyendo() {
        let base = ContenidoPlanes.maraton()
        let cinco = MotorPlanificacion.recortar(base, aDias: 5)
        let cuatro = MotorPlanificacion.recortar(base, aDias: 4)
        // Semana de pico (la más cargada de construcción).
        let indice = 12
        let v5 = volumen(cinco.semanas[indice])
        let v4 = volumen(cuatro.semanas[indice])
        XCTAssertGreaterThan(v4, v5 * 0.9,
                             "pasar de 5 a 4 días no puede evaporar el 20 % de la semana")
        XCTAssertEqual(larga(cinco.semanas[indice]), larga(cuatro.semanas[indice]),
                       accuracy: 0.01, "la tirada larga no cambia al recortar")
    }

    func testUnaSesionFacilNoCreceSinControl() {
        let base = ContenidoPlanes.maraton()
        let tres = MotorPlanificacion.recortar(base, aDias: 3)
        for semana in tres.semanas {
            for entrenamiento in semana.entrenamientos where entrenamiento.tipo == .facil {
                let km = entrenamiento.segmentos.compactMap(\.distanciaKm).reduce(0, +)
                XCTAssertLessThan(km, 25, "semana \(semana.numero): un «rodaje suave» de \(km) km")
            }
        }
    }

    func testLaCarreraObjetivoNoAbsorbeVolumen() {
        let base = ContenidoPlanes.maraton()
        let recortado = MotorPlanificacion.recortar(base, aDias: 3)
        let ultima = recortado.semanas.last!
        let carrera = ultima.entrenamientos.first { $0.tipo == .ritmoCarrera }
        XCTAssertEqual(carrera?.segmentos.compactMap(\.distanciaKm).reduce(0, +) ?? 0,
                       42.195, accuracy: 0.01)
    }

    func testRecortarNoDuplicaNiPierdeSesiones() {
        for (_, base) in CatalogoDePrueba.todos {
            for dias in 2...6 {
                let recortado = MotorPlanificacion.recortar(base, aDias: dias)
                for (original, resultado) in zip(base.semanas, recortado.semanas) {
                    XCTAssertEqual(resultado.entrenamientos.count,
                                   min(dias, original.entrenamientos.count))
                    XCTAssertEqual(Set(resultado.entrenamientos.map(\.nombre)).count,
                                   resultado.entrenamientos.count,
                                   "no puede haber dos sesiones iguales en la semana")
                }
            }
        }
    }
}

// MARK: - Catálogo de prueba compartido

enum CatalogoDePrueba {
    /// Los 10 planes con su rango de días declarado.
    static var todos: [(arquetipo: PlanArquetipo, base: PlanBase)] {
        BibliotecaArquetipos.v1().compactMap { arquetipo in
            arquetipo.contenido.map { (arquetipo, $0) }
        }
    }

    static func volumen(_ semana: SemanaBase) -> Double {
        CalculoVolumen.volumen(semana.entrenamientos.flatMap(\.segmentos).map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
        }).totalKm
    }

    static func larga(_ semana: SemanaBase) -> Double {
        semana.entrenamientos.filter { $0.tipo == .largo }
            .map { entrenamiento in
                CalculoVolumen.volumen(entrenamiento.segmentos.map {
                    CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                           duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
                }).totalKm
            }.max() ?? 0
    }
}

// MARK: - INVARIANTES DE CATÁLOGO (§22)

/// Recorren TODAS las semanas de TODOS los planes en TODAS las
/// frecuencias soportadas. No están escritos contra un caso puntual.
final class InvariantesCatalogoTests: XCTestCase {

    /// Tope de proporción de la tirada larga. DECISIÓN MARATONIA: el
    /// consenso de entrenamiento ubica la larga en 30-35 % del volumen
    /// semanal; 45 % es el techo que el catálogo actual puede sostener
    /// sin reescribir progresiones que SÍ pasaron la auditoría de
    /// saltos de sesión. Es una mejora por etapas, no el estado final.
    static let topeProporcionLarga = 0.45
    /// Por debajo de este volumen la proporción no significa nada: en
    /// una semana de 9 km, una "larga" de 4,5 km es inofensiva.
    static let volumenMinimoParaProporcion = 25.0

    func testLaLargaNuncaDominaLaSemanaDeConstruccion() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for semana in plan.semanas {
                    // Taper y semana de carrera quedan fuera: ahí una
                    // larga proporcionalmente alta es exactamente lo
                    // que corresponde.
                    guard semana.fase?.esDeConstruccion ?? true else { continue }
                    let total = CatalogoDePrueba.volumen(semana)
                    let larga = CatalogoDePrueba.larga(semana)
                    guard total >= Self.volumenMinimoParaProporcion, larga > 0 else { continue }
                    let proporcion = larga / total
                    if proporcion > Self.topeProporcionLarga {
                        fallos.append(String(format: "%@ %dd sem %d: %.0f%% (%.1f/%.1f km)",
                                             arquetipo.id, dias, semana.numero,
                                             proporcion * 100, larga, total))
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "la tirada larga domina la semana en:\n" + fallos.joined(separator: "\n"))
    }

    func testNingunaSemanaTieneMasDeUnaTiradaLarga() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                for semana in MotorPlanificacion.recortar(base, aDias: dias).semanas {
                    XCTAssertLessThanOrEqual(
                        semana.entrenamientos.filter { $0.tipo == .largo }.count, 1,
                        "\(arquetipo.id) \(dias)d sem \(semana.numero)")
                }
            }
        }
    }

    func testLaCarreraObjetivoApareceUnaSolaVezYAlFinal() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let carreras = base.semanas.flatMap { semana in
                semana.entrenamientos.filter { $0.tipo == .ritmoCarrera }.map { _ in semana.numero }
            }
            XCTAssertEqual(carreras.count, 1, "\(arquetipo.id): \(carreras.count) carreras objetivo")
            XCTAssertEqual(carreras.first, base.semanas.last?.numero,
                           "\(arquetipo.id): la carrera no está en la última semana")
        }
    }

    func testTodaSesionTieneAlgoEjecutable() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for semana in base.semanas {
                for entrenamiento in semana.entrenamientos {
                    let util = entrenamiento.segmentos.contains {
                        ($0.distanciaKm ?? 0) > 0 || ($0.duracionSegundos ?? 0) > 0
                    }
                    XCTAssertTrue(util, "\(arquetipo.id) sem \(semana.numero): «\(entrenamiento.nombre)» sin distancia ni duración")
                }
            }
        }
    }

    func testNingunVolumenNegativoNiNoFinito() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                for semana in MotorPlanificacion.recortar(base, aDias: dias).semanas {
                    let v = CatalogoDePrueba.volumen(semana)
                    XCTAssertTrue(v.isFinite, "\(arquetipo.id) sem \(semana.numero): no finito")
                    XCTAssertGreaterThanOrEqual(v, 0)
                    for entrenamiento in semana.entrenamientos {
                        for segmento in entrenamiento.segmentos {
                            XCTAssertGreaterThanOrEqual(segmento.distanciaKm ?? 0, 0)
                            XCTAssertGreaterThanOrEqual(segmento.duracionSegundos ?? 0, 0)
                        }
                    }
                }
            }
        }
    }

    func testElTaperSiempreBajaElVolumen() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let plan = MotorPlanificacion.recortar(base, aDias: arquetipo.diasMaximos)
            let pico = plan.semanas
                .filter { $0.fase?.esDeConstruccion ?? true }
                .map(CatalogoDePrueba.volumen).max() ?? 0
            for semana in plan.semanas where semana.fase == .taper {
                XCTAssertLessThan(CatalogoDePrueba.volumen(semana), pico,
                                  "\(arquetipo.id) sem \(semana.numero): el taper no baja")
            }
        }
    }

    /// La coherencia que el bug de elegibilidad rompía: un requisito de
    /// entrada no puede superar lo que el propio plan pide.
    func testLosRequisitosNoSuperanAlPlanQueHabilitan() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
            let plan = MotorPlanificacion.recortar(base, aDias: arquetipo.diasMinimos)
            let construccion = plan.semanas.filter { $0.fase?.esDeConstruccion ?? true }
            let pico = construccion.map(CatalogoDePrueba.volumen).max() ?? 0
            let largaMaxima = plan.semanas.map(CatalogoDePrueba.larga).max() ?? 0
            let primera = CatalogoDePrueba.volumen(plan.semanas[0])

            XCTAssertLessThanOrEqual(requisitos.kmSemanales, pico,
                "\(arquetipo.id): pide \(requisitos.kmSemanales) km/sem y el plan pica en \(pico)")
            XCTAssertLessThanOrEqual(requisitos.kmSemanales, primera * 1.05,
                "\(arquetipo.id): el requisito debería poder sostenerse el día uno " +
                "(pide \(requisitos.kmSemanales), la primera semana son \(primera))")
            XCTAssertLessThanOrEqual(requisitos.tiradaLargaKm, largaMaxima,
                "\(arquetipo.id): exige una larga previa de \(requisitos.tiradaLargaKm) km " +
                "y la más larga del plan es \(largaMaxima)")
            XCTAssertEqual(requisitos.diasPorSemana, arquetipo.diasMinimos,
                "\(arquetipo.id): elegibilidad y catálogo no coinciden en días mínimos")
        }
    }

    func testTodaSesionCaeEnUnDiaValido() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let elegidos = OnboardingDeportivo.diasSugeridos(para: dias)
                let plan = MotorPlanificacion.distribuir(
                    MotorPlanificacion.recortar(base, aDias: dias), enDias: elegidos)
                for semana in plan.semanas {
                    for entrenamiento in semana.entrenamientos {
                        XCTAssertTrue(elegidos.contains(entrenamiento.diaDeSemana),
                                      "\(arquetipo.id) \(dias)d sem \(semana.numero): día \(entrenamiento.diaDeSemana) fuera de \(elegidos)")
                    }
                    XCTAssertEqual(Set(semana.entrenamientos.map(\.diaDeSemana)).count,
                                   semana.entrenamientos.count,
                                   "\(arquetipo.id) \(dias)d sem \(semana.numero): dos sesiones el mismo día")
                }
            }
        }
    }
}

// MARK: - Inercia del adaptador (§17)

final class InerciaAdaptadorTests: XCTestCase {

    private func almacenBase() -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo(); perfil.diasElegidos = [1, 3, 5, 7]
        almacen.perfil = perfil
        func hacer(_ nombre: String, _ tipo: TipoEntrenamiento,
                   _ km: Double, _ dia: Int) -> EntrenamientoProgramado {
            let rol = RolSesion.para(tipo)
            return EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: tipo, nombre: nombre,
                    segmentos: [Segmento(nombre: nombre, distanciaKm: km, ritmo: .simbolico(.facil))]),
                dia: DiaLocal(anio: 2026, mes: 8, dia: dia),
                rolGuardado: rol, adaptabilidadGuardada: .para(rol))
        }
        var lunes = hacer("Recuperación", .recuperacion, 4, 10)
        lunes.resolucion = .cumplido
        almacen.planActivo = PlanUsuario(nombre: "T", fechaAdopcion: ahoraTest, semanas: [
            SemanaPlan(numero: 1, programados: [
                lunes, hacer("Umbral", .umbral, 8, 12),
                hacer("Rodaje", .facil, 7, 14), hacer("Larga", .largo, 16, 16),
            ], reglas: ReglasSemana(fase: .construccion)),
        ])
        return almacen
    }

    private func analisis(_ almacen: AlmacenV2, sensacion: SensacionEsfuerzo?,
                          cumplimiento: Double = 1.0, molestia: Bool = false) -> AnalisisPostCarrera {
        AnalisisPostCarrera(sesionID: UUID(), fecha: ahoraTest, km: 8 * cumplimiento,
                            minutos: 48, ritmoSegKm: 360,
                            programadoID: almacen.todosLosProgramados.first {
                                $0.definicion.nombre == "Umbral" }?.id,
                            kmPrescritos: 8, estructuraCompleta: cumplimiento >= 1,
                            sensacion: sensacion, conMolestia: molestia)
    }

    func testUnMuyExigidoAisladoNoCambiaElPlan() {
        let almacen = almacenBase()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoyTest, almacen: almacen, analisis: analisis(almacen, sensacion: .muyExigido)))
        XCTAssertFalse(eventos.contains { if case .esfuerzoMuyAlto = $0 { return true }; return false },
                       "una señal suelta no puede degradar la próxima calidad")
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos))
    }

    func testDosSenalesConsecutivasSiAdaptan() {
        var almacen = almacenBase()
        // Señal previa REAL en el historial: una sesión marcada exigida.
        let previa = UUID()
        almacen.registrarSesionLibre(sesionID: previa,
                                     fecha: ahoraTest.addingTimeInterval(-3 * 86_400))
        almacen.registrarSensacion(sesionID: previa, sensacion: .muyExigido, conMolestia: false)
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoyTest, almacen: almacen, analisis: analisis(almacen, sensacion: .muyExigido)))
        XCTAssertTrue(eventos.contains { if case .esfuerzoMuyAlto = $0 { return true }; return false })
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testMuyExigidoMasParcialSignificativaAdapta() {
        let almacen = almacenBase()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoyTest, almacen: almacen,
            analisis: analisis(almacen, sensacion: .muyExigido, cumplimiento: 0.6)))
        XCTAssertTrue(eventos.contains { if case .esfuerzoMuyAlto = $0 { return true }; return false },
                      "sentirse muy exigido Y no poder terminarla son dos señales coherentes")
    }

    func testLaMolestiaNoEsperaConfirmacion() {
        let almacen = almacenBase()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoyTest, almacen: almacen,
            analisis: analisis(almacen, sensacion: .bien, molestia: true)))
        XCTAssertTrue(eventos.contains { if case .molestiaReportada = $0 { return true }; return false })
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testMuyBienNuncaGeneraNada() {
        let almacen = almacenBase()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoyTest, almacen: almacen, analisis: analisis(almacen, sensacion: .muyBien)))
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos))
        XCTAssertTrue(PropuestaLocal.proponer(para: eventos, en: almacen, hoy: hoyTest).isEmpty)
    }

    func testUnaSesionPerdidaAisladaNoReescribeLaSemana() {
        var almacen = almacenBase()
        let rol = RolSesion.para(.facil)
        almacen.planActivo!.semanas[0].programados.append(EntrenamientoProgramado(
            definicion: DefinicionEntrenamiento(
                tipo: .facil, nombre: "Perdida",
                segmentos: [Segmento(nombre: "R", distanciaKm: 5)]),
            dia: DiaLocal(anio: 2026, mes: 8, dia: 11),
            rolGuardado: rol, adaptabilidadGuardada: .para(rol)))
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoyTest, almacen: almacen))
        XCTAssertTrue(eventos.contains { if case .sesionPerdida = $0 { return true }; return false })
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos),
                       "perder un rodaje suelto es parte de entrenar")
    }

    func testVariasPerdidasSiAdaptan() {
        var almacen = almacenBase()
        for (indice, dia) in [9, 11].enumerated() {
            let rol = RolSesion.para(.facil)
            almacen.planActivo!.semanas[0].programados.append(EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: .facil, nombre: "Perdida \(indice)",
                    segmentos: [Segmento(nombre: "R", distanciaKm: 5)]),
                dia: DiaLocal(anio: 2026, mes: 8, dia: dia),
                rolGuardado: rol, adaptabilidadGuardada: .para(rol)))
        }
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoyTest, almacen: almacen))
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testElHistorialDeSensacionesSeLeeDeVerdad() {
        var almacen = almacenBase()
        XCTAssertEqual(Senales.sesionesDuras(en: almacen, hoy: hoyTest), 0)
        let id = UUID()
        almacen.registrarSesionLibre(sesionID: id, fecha: ahoraTest.addingTimeInterval(-86_400))
        almacen.registrarSensacion(sesionID: id, sensacion: .exigido, conMolestia: false)
        XCTAssertEqual(Senales.sesionesDuras(en: almacen, hoy: hoyTest), 1)
        // Fuera de la ventana no cuenta.
        let viejo = UUID()
        almacen.registrarSesionLibre(sesionID: viejo, fecha: ahoraTest.addingTimeInterval(-40 * 86_400))
        almacen.registrarSensacion(sesionID: viejo, sensacion: .muyExigido, conMolestia: false)
        XCTAssertEqual(Senales.sesionesDuras(en: almacen, hoy: hoyTest), 1)
    }
}

// MARK: - Arranque conservador con semántica real (§12)

final class ArranqueConservadorTests: XCTestCase {

    func testConservadorArrancaMasAbajoQueNormal() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let normal = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 25,
                                                       conservador: false)
        let conservador = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 25,
                                                            conservador: true)
        XCTAssertLessThan(conservador.factor, normal.factor,
                          "«conservador» tiene que significar algo en el plan, no solo en el texto")
        let v = { (plan: PlanBase) in CatalogoDePrueba.volumen(plan.semanas[0]) }
        XCTAssertLessThan(v(conservador.base), v(normal.base))
    }

    func testConservadorNoSuperaElVolumenActualEnLaPrimeraSemana() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let (plan, _) = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 25,
                                                          conservador: true)
        XCTAssertLessThanOrEqual(CatalogoDePrueba.volumen(plan.semanas[0]), 25 * 1.02)
    }

    func testElArranqueUsaElVolumenCompletoNoSoloLasDistancias() {
        // Con el cálculo viejo la primera semana parecía más chica y la
        // atenuación se calculaba contra un número equivocado.
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 4)
        let soloDistancia = base.semanas[0].entrenamientos
            .flatMap(\.segmentos).compactMap(\.distanciaKm).reduce(0, +)
        XCTAssertGreaterThan(CatalogoDePrueba.volumen(base.semanas[0]), soloDistancia)
        let (plan, factor) = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 20, conservador: false)
        XCTAssertLessThan(factor, 1)
        XCTAssertLessThanOrEqual(CatalogoDePrueba.volumen(plan.semanas[0]), 20 * 1.25)
    }

    func testSinDatosDeVolumenElArranqueNoSeToca() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.maraton(), aDias: 4)
        let (plan, factor) = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: nil)
        XCTAssertEqual(factor, 1)
        XCTAssertEqual(plan, base)
    }

    func testElArranqueNuncaEscalaHaciaArriba() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let (plan, factor) = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 200)
        XCTAssertEqual(factor, 1)
        XCTAssertEqual(CatalogoDePrueba.volumen(plan.semanas[0]),
                       CatalogoDePrueba.volumen(base.semanas[0]), accuracy: 0.001)
    }
}
