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
        // 25′ del corredor de referencia: 15′ a ritmo de intervalo
        // (~5:50/km) y 10′ de pausa trotada (~8:49/km) son ~3,7 km. La
        // propiedad es que los bloques por tiempo pesan MÁS que los
        // 3 km declarados — antes valían 0.
        XCTAssertGreaterThan(v.kmEquivalentes, v.kmMedidos,
                             "los intervalos y sus pausas son casi toda la sesión")
        XCTAssertGreaterThan(v.totalKm, 6.5)
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

    /// Un rodaje no puede volverse una segunda tirada larga al absorber
    /// el volumen de las sesiones recortadas. Se evalúa en las
    /// frecuencias que el arquetipo DECLARA soportar: recortar Primera
    /// Maratón a 3 días es una semana que la app nunca genera
    /// (`diasMinimos` = 4) y medir ahí no dice nada del producto.
    func testUnaSesionFacilNoCreceSinControl() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for semana in plan.semanas {
                    for entrenamiento in semana.entrenamientos
                    where entrenamiento.tipo == .facil {
                        let km = entrenamiento.segmentos.compactMap(\.distanciaKm).reduce(0, +)
                        XCTAssertLessThan(km, 25, "\(arquetipo.id) \(dias)d semana \(semana.numero): un «rodaje» de \(km) km")
                    }
                }
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

    /// La IDENTIDAD de una sesión del template es su día de la semana,
    /// no su nombre: el catálogo repite nombres a propósito (dos
    /// "Rodaje" de 4 km en la misma semana de Rumbo a 10K son dos
    /// salidas iguales y está bien que lo sean). Lo que el recorte no
    /// puede hacer es quedarse dos veces con la MISMA sesión ni
    /// inventar una que el template no tenía.
    func testRecortarNoDuplicaNiPierdeSesiones() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let id = arquetipo.id
            for dias in 2...6 {
                let recortado = MotorPlanificacion.recortar(base, aDias: dias)
                for (original, resultado) in zip(base.semanas, recortado.semanas) {
                    let dias0 = original.entrenamientos.map(\.diaDeSemana)
                    let diasRecorte = resultado.entrenamientos.map(\.diaDeSemana)
                    XCTAssertEqual(resultado.entrenamientos.count,
                                   min(dias, original.entrenamientos.count),
                                   "\(id) \(dias)d semana \(original.numero)")
                    XCTAssertEqual(Set(diasRecorte).count, diasRecorte.count,
                                   "\(id) \(dias)d semana \(original.numero): la misma sesión dos veces")
                    XCTAssertTrue(Set(diasRecorte).isSubset(of: Set(dias0)),
                                  "\(id) \(dias)d semana \(original.numero): sesión que el template no tenía")
                    XCTAssertEqual(diasRecorte, diasRecorte.sorted(),
                                   "\(id) \(dias)d semana \(original.numero): el orden de los días no se conserva")
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

    /// Volumen de UNA sesión, con su tope de duración aplicado.
    /// Sesión por sesión: el tope es por sesión, así que sumar los
    /// segmentos de la semana entera lo haría desaparecer.
    static func volumen(_ entrenamiento: EntrenamientoBase,
                        baseline: PerformanceBaseline? = nil) -> Double {
        CalculoVolumen.volumen(entrenamiento.segmentos.map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
        }, tope: entrenamiento.topeDuracionSegundos, baseline: baseline).totalKm
    }

    /// Duración prevista de UNA sesión, ya recortada por su tope.
    static func duracion(_ entrenamiento: EntrenamientoBase,
                         baseline: PerformanceBaseline? = nil) -> Double {
        let entradas = entrenamiento.segmentos.map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos, ritmo: $0.ritmo)
        }
        let factor = CalculoVolumen.factorDeTope(
            entradas, tope: entrenamiento.topeDuracionSegundos, baseline: baseline)
        return entradas.reduce(0.0) { total, entrada in
            if let km = entrada.distanciaKm {
                return total + km * factor
                    * Double(CalculoVolumen.ritmo(de: entrada.ritmo, baseline: baseline).segKm)
            }
            return total + Double(entrada.duracionSegundos ?? 0)
        }
    }

    static func volumen(_ semana: SemanaBase,
                        baseline: PerformanceBaseline? = nil) -> Double {
        semana.entrenamientos.reduce(0) { $0 + volumen($1, baseline: baseline) }
    }

    static func larga(_ semana: SemanaBase,
                      baseline: PerformanceBaseline? = nil) -> Double {
        semana.entrenamientos.filter { $0.tipo == .largo }
            .map { volumen($0, baseline: baseline) }.max() ?? 0
    }

    /// Los cuatro corredores con los que se auditó el contenido 42K:
    /// del recreativo rápido al que corre 5 km en 33 minutos. Es donde
    /// el tope de duración cambia de "no muerde" a "manda".
    static let corredores: [(nombre: String, baseline: PerformanceBaseline)] = {
        [("5K 20:00", 1200), ("5K 25:00", 1500),
         ("5K 30:00", 1800), ("5K 33:00", 1980)].compactMap { nombre, segundos in
            PerformanceBaseline(referencia: ReferenciaRendimiento(
                fecha: Date(timeIntervalSince1970: 0), fuente: .estimacionInicial,
                distanciaMetros: 5000, segundos: segundos)).map { (nombre, $0) }
        }
    }()

    /// Los tres planes de maratón, que son los que declaran tope.
    static var maratones: [(arquetipo: PlanArquetipo, base: PlanBase)] {
        todos.filter { $0.base.distanciaObjetivoKm > 42 }
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
            // Propiedad ESTRUCTURAL del catálogo: el taper y el pico se
            // miden con la misma vara, así que alcanza con el corredor
            // de REFERENCIA (baseline nil → `RitmoDeReferencia`). El
            // tope de duración comprime los dos lados en la misma
            // dirección y la comparación no cambia de signo — lo
            // verifiqué para los cuatro corredores antes de dejarlo así.
            // La cobertura del tope por corredor vive en Contenido42KTests.
            let pico = plan.semanas
                .filter { $0.fase?.esDeConstruccion ?? true }
                .map { CatalogoDePrueba.volumen($0) }.max() ?? 0
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

            // Contra CADA corredor, no contra uno solo. Los requisitos
            // son kilómetros absolutos, pero desde el build 63 lo que el
            // plan prescribe depende del ritmo: el tope de duración
            // recorta la larga de quien corre lento. El caso que manda
            // es justamente ese —el tope solo puede ACHICAR el plan, así
            // que el corredor más lento es el que menos margen deja—, y
            // medir solo con el de referencia dejaría sin probar el
            // borde que el tope introdujo.
            for (corredor, baseline) in CatalogoDePrueba.corredores {
                let pico = construccion
                    .map { CatalogoDePrueba.volumen($0, baseline: baseline) }.max() ?? 0
                let largaMaxima = plan.semanas
                    .map { CatalogoDePrueba.larga($0, baseline: baseline) }.max() ?? 0
                let primera = CatalogoDePrueba.volumen(plan.semanas[0], baseline: baseline)
                let quien = "\(arquetipo.id) · \(corredor)"

                XCTAssertLessThanOrEqual(requisitos.kmSemanales, pico,
                    "\(quien): pide \(requisitos.kmSemanales) km/sem y el plan pica en \(pico)")
                XCTAssertLessThanOrEqual(requisitos.kmSemanales, primera * 1.05,
                    "\(quien): el requisito debería poder sostenerse el día uno " +
                    "(pide \(requisitos.kmSemanales), la primera semana son \(primera))")
                XCTAssertLessThanOrEqual(requisitos.tiradaLargaKm, largaMaxima,
                    "\(quien): exige una larga previa de \(requisitos.tiradaLargaKm) km " +
                    "y la más larga del plan es \(largaMaxima)")
            }
            // Los días no dependen del ritmo: se comprueban una sola vez.
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
        let ajuste = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 25,
                                                        conservador: true)
        XCTAssertLessThanOrEqual(CatalogoDePrueba.volumen(ajuste.base.semanas[0]), 25 * 1.02)
    }

    func testElArranqueUsaElVolumenCompletoNoSoloLasDistancias() {
        // Con el cálculo viejo la primera semana parecía más chica y la
        // atenuación se calculaba contra un número equivocado.
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 4)
        let soloDistancia = base.semanas[0].entrenamientos
            .flatMap(\.segmentos).compactMap(\.distanciaKm).reduce(0, +)
        XCTAssertGreaterThan(CatalogoDePrueba.volumen(base.semanas[0]), soloDistancia)
        let ajuste = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 20, conservador: false)
        XCTAssertLessThan(ajuste.factor, 1)
        XCTAssertLessThanOrEqual(CatalogoDePrueba.volumen(ajuste.base.semanas[0]),
                                 20 * MotorPlanificacion.factorEntradaMaximo)
    }

    func testSinDatosDeVolumenElArranqueNoSeToca() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.maraton(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: nil)
        XCTAssertEqual(ajuste.factor, 1)
        XCTAssertEqual(ajuste.base, base)
        XCTAssertEqual(ajuste.diagnostico, .sinVolumenPrevio)
    }

    func testElArranqueNuncaEscalaHaciaArriba() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 200)
        XCTAssertEqual(ajuste.factor, 1)
        XCTAssertEqual(CatalogoDePrueba.volumen(ajuste.base.semanas[0]),
                       CatalogoDePrueba.volumen(base.semanas[0]), accuracy: 0.001)
        XCTAssertTrue(ajuste.diagnostico.cumpleElTecho)
        if case .noHizoFalta = ajuste.diagnostico {} else {
            XCTFail("con 200 km/sem el template ya entra: \(ajuste.diagnostico)")
        }
    }
}

// MARK: - El arranque DICE si pudo cumplir el techo

/// `ajustarArranque` puede quedarse sin margen: el factor tiene un piso
/// y los segmentos el suyo. Cuando eso pasa, la primera semana queda
/// por encima del techo prometido. Estos tests NO fijan qué hay que
/// hacer al respecto — esa decisión está abierta. Fijan que el
/// resultado sea DECIBLE y que lo que dice sea cierto.
final class DiagnosticoArranqueTests: XCTestCase {

    /// El caso conocido: mejorar 10K a 5 días contra un corredor que
    /// entra justo por el piso de elegibilidad (0,4 × 22 = 8,8).
    func testDiceCuandoNoLlegaAlTecho() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 5)
        let ajuste = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 8.8, conservador: true)

        guard case .excedeElTecho(let permitido, let resultante) = ajuste.diagnostico else {
            return XCTFail("el techo no se cumple; el diagnóstico tiene que decirlo, dijo \(ajuste.diagnostico)")
        }
        XCTAssertEqual(permitido, 8.8, accuracy: 0.001)
        XCTAssertGreaterThan(resultante, permitido)
        XCTAssertFalse(ajuste.diagnostico.cumpleElTecho)
        XCTAssertGreaterThan(ajuste.diagnostico.excesoKm, 10)
        // Se agotó el piso: no es que la bisección haya elegido mal.
        XCTAssertEqual(ajuste.factor, MotorPlanificacion.factorArranqueMinimo)
    }

    func testDiceCuandoSiLlegaAlTecho() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 20, conservador: false)

        guard case .dentroDelTecho(let permitido, let resultante) = ajuste.diagnostico else {
            return XCTFail("el techo se cumple; el diagnóstico dijo \(ajuste.diagnostico)")
        }
        XCTAssertEqual(permitido, 20 * MotorPlanificacion.factorEntradaMaximo, accuracy: 0.001)
        XCTAssertLessThanOrEqual(resultante, permitido)
        XCTAssertTrue(ajuste.diagnostico.cumpleElTecho)
        XCTAssertEqual(ajuste.diagnostico.excesoKm, 0)
        XCTAssertGreaterThan(ajuste.factor, MotorPlanificacion.factorArranqueMinimo)
    }

    /// Sin atenuación no hay techo que reportar.
    /// El template ya entra: hay techo, se cumple, y no hizo falta
    /// tocar nada. Los tres hechos son distintos y se reportan aparte.
    func testNoHizoFaltaCuandoElTemplateYaEntra() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: 200)
        guard case .noHizoFalta(let permitido, let resultante) = ajuste.diagnostico else {
            return XCTFail("el template ya entra: \(ajuste.diagnostico)")
        }
        XCTAssertEqual(permitido, 200 * MotorPlanificacion.factorEntradaMaximo, accuracy: 0.001)
        XCTAssertLessThan(resultante, permitido)
        XCTAssertEqual(ajuste.factor, 1)
        XCTAssertTrue(ajuste.diagnostico.cumpleElTecho)
        XCTAssertTrue(ajuste.diagnostico.hayTecho)
        XCTAssertEqual(ajuste.diagnostico.excesoKm, 0)
    }

    /// Sin volumen previo NO hay techo: `cumpleElTecho` ahí es vacío,
    /// y `hayTecho` es lo que lo distingue de haberlo cumplido.
    func testSinVolumenPrevioNoAfirmaCumplimiento() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(base, kmSemanalesActuales: nil)
        XCTAssertEqual(ajuste.diagnostico, .sinVolumenPrevio)
        XCTAssertFalse(ajuste.diagnostico.hayTecho)
        XCTAssertNil(ajuste.diagnostico.permitidoKm)
        XCTAssertNil(ajuste.diagnostico.resultanteKm)
    }

    /// EL invariante: el diagnóstico no miente. Sobre los 10 planes ×
    /// todas sus frecuencias × el corredor que entra por el piso de
    /// elegibilidad, lo que el resultado AFIRMA tiene que coincidir con
    /// lo que la semana MIDE. No dice que el techo deba cumplirse —
    /// dice que si el resultado declara haberlo cumplido, es verdad.
    func testElDiagnosticoCoincideConLaSemanaQueQueda() {
        for (arquetipo, contenido) in CatalogoDePrueba.todos {
            let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
            // Barre desde el piso de elegibilidad hacia arriba: cubre
            // los dos lados de la frontera en el mismo recorrido.
            let piso = max(1, requisitos.kmSemanales * RequisitosObjetivo.fraccionPiso)
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let base = MotorPlanificacion.recortar(contenido, aDias: dias)
                for multiplo in [1.0, 1.5, 2.0, 3.0, 5.0] {
                    let actuales = piso * multiplo
                    for conservador in [true, false] {
                        let ajuste = MotorPlanificacion.ajustarArranque(
                            base, kmSemanalesActuales: actuales, conservador: conservador)
                        let real = CatalogoDePrueba.volumen(ajuste.base.semanas[0])
                        let caso = "\(arquetipo.id) \(dias)d actuales=\(actuales) conservador=\(conservador)"

                        switch ajuste.diagnostico {
                        case .sinVolumenPrevio:
                            XCTFail("\(caso): había volumen previo y lo reporta como sin medida")
                        case .noHizoFalta(let permitido, let resultante):
                            XCTAssertEqual(ajuste.factor, 1, "\(caso): noHizoFalta con factor ≠ 1")
                            XCTAssertEqual(resultante, real, accuracy: 0.001, "\(caso)")
                            XCTAssertLessThanOrEqual(resultante, permitido + 0.001,
                                                     "\(caso): dice que no hizo falta y excede")
                        case .dentroDelTecho(let permitido, let resultante):
                            XCTAssertEqual(resultante, real, accuracy: 0.001,
                                           "\(caso): el diagnóstico reporta un volumen distinto del real")
                            XCTAssertLessThanOrEqual(
                                resultante, permitido + 0.001,
                                "\(caso): declara cumplir el techo y no lo cumple")
                        case .excedeElTecho(let permitido, let resultante):
                            XCTAssertEqual(resultante, real, accuracy: 0.001,
                                           "\(caso): el diagnóstico reporta un volumen distinto del real")
                            XCTAssertGreaterThan(
                                resultante, permitido,
                                "\(caso): declara exceder el techo y no lo excede")
                            XCTAssertEqual(ajuste.factor,
                                           MotorPlanificacion.factorArranqueMinimo,
                                           "\(caso): excede el techo sin haber agotado el piso")
                        }
                    }
                }
            }
        }
    }

    /// La señal viaja por el camino real hasta la propuesta. Nadie la
    /// lee todavía: se transporta para que la decisión de producto se
    /// tome con el dato a la vista en vez de a ciegas.
    func testLaPropuestaTransportaElDiagnostico() {
        var lunes = Calendar(identifier: .gregorian); lunes.firstWeekday = 2
        let referencia = ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                               distanciaMetros: 5000, segundos: 1470)
        // Corredor que entra JUSTO por el piso de elegibilidad de
        // maratón (0,4 × 40 = 16): el plan no puede achicarse hasta ahí.
        let pedido = PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            diasConcretos: [2, 4, 6, 7], referencia: referencia,
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 10),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 16,
                                       tiradaLargaKm: 12, mesesCorriendoRegular: 6))
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        XCTAssertFalse(p.arranque.cumpleElTecho,
                       "el techo no se cumple y la propuesta lo tiene que transportar")
        XCTAssertGreaterThan(p.arranque.excesoKm, 0)
        // Y sigue siendo el mismo plan: la señal no bloquea nada.
        XCTAssertFalse(p.planUsuario.semanas.isEmpty)
    }
}

// MARK: - Los 3 casos donde NINGÚN factor alcanza

/// Hay combinaciones donde el techo de entrada es inalcanzable por
/// escalado: aunque el factor bajara a 0, el piso de 1 km por segmento
/// y los bloques por tiempo (un umbral de 18′ dura 18′) dejan la semana
/// por encima de lo permitido. Son los tres de acá, medidos contra el
/// corredor que entra JUSTO por el piso de elegibilidad.
///
/// DECISIÓN: el plan se entrega igual. Lo que NO se hace es decir que
/// el techo se cumplió. Estos tests fijan las dos mitades.
final class ArranqueIrreducibleTests: XCTestCase {

    /// Los tres, con el volumen previo que los produce.
    private static let casos: [(nombre: String, plan: () -> PlanBase,
                                dias: Int, previo: Double)] = [
        ("mejorar-5k · 4d", ContenidoPlanes.mejorar5K, 4, 18 * 0.4),
        ("mejorar-5k · 5d", ContenidoPlanes.mejorar5K, 5, 18 * 0.4),
        ("mejorar-10k · 5d", ContenidoPlanes.mejorar10K, 5, 22 * 0.4),
    ]

    func testLosIrreduciblesReportanQueExcedenElTecho() {
        for caso in Self.casos {
            let base = MotorPlanificacion.recortar(caso.plan(), aDias: caso.dias)
            let ajuste = MotorPlanificacion.ajustarArranque(
                base, kmSemanalesActuales: caso.previo, conservador: true)

            guard case .excedeElTecho(let permitido, let resultante) = ajuste.diagnostico else {
                XCTFail("\(caso.nombre): el techo no se cumple y el diagnóstico dice \(ajuste.diagnostico)")
                continue
            }
            XCTAssertEqual(permitido, caso.previo, accuracy: 0.001, caso.nombre)
            XCTAssertGreaterThan(resultante, permitido, caso.nombre)
            XCTAssertFalse(ajuste.diagnostico.cumpleElTecho, caso.nombre)
            XCTAssertTrue(ajuste.diagnostico.hayTecho, caso.nombre)
            XCTAssertGreaterThan(ajuste.diagnostico.excesoKm, 0, caso.nombre)
            // Se agotó el piso del factor: no es que la bisección
            // haya elegido mal.
            XCTAssertEqual(ajuste.factor, MotorPlanificacion.factorArranqueMinimo,
                           accuracy: 1e-12, caso.nombre)
        }
    }

    /// Ni siquiera bajando el factor a cero entrarían: por eso son
    /// irreducibles y no un problema de haberse quedado corto.
    func testElConflictoSobreviveAlLimiteDelEscalado() {
        for caso in Self.casos {
            let base = MotorPlanificacion.recortar(caso.plan(), aDias: caso.dias)
            // Límite factor→0: cada segmento por distancia en su piso
            // de 1 km, los bloques por tiempo intactos.
            let minimo = base.semanas[0].entrenamientos.reduce(0.0) { total, e in
                guard e.tipo != .ritmoCarrera else {
                    return total + CatalogoDePrueba.volumen(e)
                }
                var m = e
                m.segmentos = e.segmentos.map { s in
                    guard s.distanciaKm != nil else { return s }
                    var n = s; n.distanciaKm = 1.0; return n
                }
                return total + CatalogoDePrueba.volumen(m)
            }
            XCTAssertGreaterThan(minimo, caso.previo,
                                 "\(caso.nombre): si el mínimo entra, el caso no es irreducible")
        }
    }

    /// El plan se CONSERVA: no se bloquea, no se vacía, no se recorta
    /// por la ventana. Exceder el techo no puede costarle el plan al
    /// corredor.
    func testElPlanSobreviveAlConflicto() {
        for caso in Self.casos {
            let base = MotorPlanificacion.recortar(caso.plan(), aDias: caso.dias)
            let ajuste = MotorPlanificacion.ajustarArranque(
                base, kmSemanalesActuales: caso.previo, conservador: true)
            XCTAssertEqual(ajuste.base.semanas.count, base.semanas.count, caso.nombre)
            XCTAssertEqual(ajuste.base.semanas[0].entrenamientos.count,
                           base.semanas[0].entrenamientos.count, caso.nombre)
            XCTAssertGreaterThan(CatalogoDePrueba.volumen(ajuste.base.semanas[0]), 0,
                                 caso.nombre)
            // Y se atenuó todo lo que se pudo: entregar el template sin
            // tocar sería peor que entregar el piso.
            XCTAssertLessThan(CatalogoDePrueba.volumen(ajuste.base.semanas[0]),
                              CatalogoDePrueba.volumen(base.semanas[0]), caso.nombre)
        }
    }

    /// La vista de la propuesta muestra el aviso de arranque SOLO
    /// cuando hubo atenuación (`factorArranque < 1`), y adentro elige
    /// el texto según `cumpleElTecho`. Si alguna vez se pudiera exceder
    /// el techo SIN atenuar, el aviso desaparecería en silencio justo
    /// en el caso que más importa. Este test ata las dos cosas.
    func testExcederElTechoImplicaHaberAtenuado() {
        for (arquetipo, contenido) in CatalogoDePrueba.todos {
            let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
            let piso = max(1, requisitos.kmSemanales * RequisitosObjetivo.fraccionPiso)
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let base = MotorPlanificacion.recortar(contenido, aDias: dias)
                for multiplo in [0.25, 0.5, 1.0, 2.0, 5.0] {
                    for conservador in [true, false] {
                        let ajuste = MotorPlanificacion.ajustarArranque(
                            base, kmSemanalesActuales: piso * multiplo,
                            conservador: conservador)
                        guard !ajuste.diagnostico.cumpleElTecho else { continue }
                        XCTAssertLessThan(
                            ajuste.factor, 1,
                            "\(arquetipo.id) \(dias)d: excede el techo sin atenuar, la vista no lo avisaría")
                    }
                }
            }
        }
    }

    /// La contracara: los mismos planes con un corredor que SÍ tiene
    /// base cumplen el techo y lo reportan como corresponde.
    func testLosMismosPlanesConBaseSuficienteCumplenElTecho() {
        for caso in Self.casos {
            let base = MotorPlanificacion.recortar(caso.plan(), aDias: caso.dias)
            let holgado = CatalogoDePrueba.volumen(base.semanas[0])
            let ajuste = MotorPlanificacion.ajustarArranque(
                base, kmSemanalesActuales: holgado, conservador: true)
            XCTAssertTrue(ajuste.diagnostico.cumpleElTecho, caso.nombre)
            XCTAssertEqual(ajuste.diagnostico.excesoKm, 0, caso.nombre)
            if let resultante = ajuste.diagnostico.resultanteKm,
               let permitido = ajuste.diagnostico.permitidoKm {
                XCTAssertLessThanOrEqual(resultante, permitido + 0.001, caso.nombre)
            } else {
                XCTFail("\(caso.nombre): había techo y no lo reporta")
            }
        }
    }
}

// MARK: - Aceptar el modo conservador produce un plan conservador

/// `aceptaConservador` es lo que el corredor marca tras leer «falta
/// base». Cruzaba la puerta pero el plan salía en su variante NORMAL:
/// `esConservador` solo es true para `.elegibleConservador`, nunca para
/// `.requiereFaseBase`. Resultado: el corredor con menos base recibía
/// el techo más alto (1,2 en vez de 1,0) y la rampa más corta (3
/// semanas en vez de 5).
final class AceptaConservadorTests: XCTestCase {

    private var lunes: Calendar {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c
    }

    /// Corredor con volumen suficiente (40 = el requisito de maratón)
    /// pero fondo demasiado corto: `requiereFaseBase` por fondoCorto.
    /// Sirve como discriminador porque con techo 1,2 la semana 1 del
    /// template (47,9) entra sola y NO se atenúa nada, mientras que con
    /// el techo conservador (1,0) sí hay que bajarla a 40.
    private func pedidoQueInsiste(aceptaConservador: Bool) -> PedidoDePlan {
        PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            diasConcretos: [2, 4, 6, 7],
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1470),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 10),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 40,
                                       tiradaLargaKm: 4, mesesCorriendoRegular: 6),
            aceptaConservador: aceptaConservador)
    }

    /// Sin aceptar, la puerta sigue cerrada: el arreglo no abre nada.
    func testSinAceptarSigueBloqueado() {
        guard case .requiereBase(let motivos, _) = MotorPlanificacion.proponer(
            pedidoQueInsiste(aceptaConservador: false), calendario: lunes) else {
            return XCTFail("sin aceptar tiene que pedir base")
        }
        XCTAssertTrue(motivos.contains(.fondoCorto))
    }

    /// Aceptando, hay plan Y el plan es el conservador.
    func testAceptarProduceElArranqueConservador() {
        guard case .propuesta(let p) = MotorPlanificacion.proponer(
            pedidoQueInsiste(aceptaConservador: true), calendario: lunes) else {
            return XCTFail("aceptando tiene que haber propuesta")
        }
        // Con el techo permisivo (1,2 × 40 = 48) la semana 1 entraba
        // sola y el factor quedaba en 1: el plan NO era conservador.
        XCTAssertLessThan(p.factorArranque, 1,
                          "aceptar conservador tiene que atenuar el arranque")
        XCTAssertEqual(p.arranque.permitidoKm ?? 0,
                       40 * MotorPlanificacion.factorEntradaConservador, accuracy: 0.001,
                       "el techo aplicado tiene que ser el conservador, no el permisivo")
        XCTAssertTrue(p.arranque.cumpleElTecho)
    }

    /// La otra mitad de «conservador»: la rampa larga. Con la rampa
    /// normal (3) la semana 4 ya es el template; con la conservadora
    /// (5) todavía está atenuada.
    func testAceptarUsaLaRampaConservadora() {
        guard case .propuesta(let p) = MotorPlanificacion.proponer(
            pedidoQueInsiste(aceptaConservador: true), calendario: lunes) else {
            return XCTFail("aceptando tiene que haber propuesta")
        }
        let base = MotorPlanificacion.recortar(ContenidoPlanes.maraton(), aDias: 4)
        let ajuste = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 40, conservador: true)
        XCTAssertGreaterThan(MotorPlanificacion.semanasDeRampaConservador,
                             MotorPlanificacion.semanasDeRampa)
        let cuarta = MotorPlanificacion.semanasDeRampa // índice 3 = semana 4
        XCTAssertLessThan(
            CatalogoDePrueba.volumen(ajuste.base.semanas[cuarta]),
            CatalogoDePrueba.volumen(base.semanas[cuarta]),
            "con rampa conservadora la semana \(cuarta + 1) sigue atenuada")
        XCTAssertFalse(p.planUsuario.semanas.isEmpty)
    }

    /// El corredor que ya era `.elegibleConservador` no cambia: el
    /// arreglo toca SOLO el camino de requiereFaseBase.
    func testElConservadorNormalNoCambia() {
        let pedido = PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            diasConcretos: [2, 4, 6, 7],
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1470),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 10),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 30,
                                       tiradaLargaKm: 12, mesesCorriendoRegular: 6))
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        XCTAssertTrue(p.veredicto.esConservador)
        XCTAssertEqual(p.arranque.permitidoKm ?? 0,
                       30 * MotorPlanificacion.factorEntradaConservador, accuracy: 0.001)
    }
}

// MARK: - INVARIANTES DEL CONTENIDO 42K (sprint de contenido)

/// Estos recorren los TRES planes de maratón × todas sus frecuencias ×
/// los cuatro corredores de referencia. Un plan de maratón no es el
/// mismo objeto para quien corre 5 km en 20:00 que para quien los corre
/// en 33:00: la misma tirada de 30 km son 2:45 o 4:30. Los invariantes
/// que no se evalúan contra un ritmo concreto no dicen nada.
final class Contenido42KTests: XCTestCase {

    /// HEURÍSTICA MARATONIA — NO es evidencia. La tirada larga no puede
    /// ser más de 2,2 veces la segunda sesión más larga de la semana.
    /// No sale de ningún paper: sale de mirar el propio catálogo y
    /// decidir que un salto de 11 km a 30 km (2,7×) deja al corredor
    /// sin nada en el medio. El número exacto es arbitrario dentro de
    /// un rango razonable; lo que no es arbitrario es que exista un
    /// techo. Ver METODOLOGIA.md.
    static let topeLargaSobreSegunda = 2.2

    /// El tope declarado por cada plan, en segundos.
    private func tope(_ base: PlanBase) -> Int? {
        base.semanas.flatMap(\.entrenamientos).compactMap(\.topeDuracionSegundos).max()
    }

    func testTodosLosPlanesDeMaratonDeclaranTope() {
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            let sinTope = base.semanas.flatMap(\.entrenamientos)
                .filter { $0.tipo != .ritmoCarrera && $0.topeDuracionSegundos == nil }
            XCTAssertTrue(sinTope.isEmpty,
                          "\(arquetipo.id): \(sinTope.count) sesiones sin tope de duración")
        }
    }

    /// El invariante central del sprint: NINGUNA sesión de entrenamiento
    /// deja al corredor en la calle más tiempo del que el plan declara.
    func testNingunaSesionSuperaElTopeDeDuracion() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            guard let tope = tope(base) else { continue }
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for (nombre, baseline) in CatalogoDePrueba.corredores {
                    for semana in plan.semanas {
                        for entrenamiento in semana.entrenamientos
                        where entrenamiento.tipo != .ritmoCarrera {
                            let duracion = CatalogoDePrueba.duracion(entrenamiento,
                                                                    baseline: baseline)
                            if duracion > Double(tope) + 1 {
                                fallos.append(String(
                                    format: "%@ %dd %@ sem %d %@: %.0f min (tope %d)",
                                    arquetipo.id, dias, nombre, semana.numero,
                                    entrenamiento.nombre, duracion / 60, tope / 60))
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "sesiones por encima del tope:\n" + fallos.joined(separator: "\n"))
    }

    /// La larga no puede ser un abismo respecto del resto de la semana.
    /// Solo en semanas de construcción: en taper que la larga domine es
    /// exactamente lo que corresponde.
    func testLaLargaNoDuplicaMasDe2Punto2ALaSegunda() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for (nombre, baseline) in CatalogoDePrueba.corredores {
                    for semana in plan.semanas {
                        guard semana.fase?.esDeConstruccion ?? false else { continue }
                        let kms = semana.entrenamientos
                            .map { CatalogoDePrueba.volumen($0, baseline: baseline) }
                            .sorted(by: >)
                        guard kms.count >= 2, kms[1] > 0 else { continue }
                        let razon = kms[0] / kms[1]
                        if razon > Self.topeLargaSobreSegunda {
                            fallos.append(String(format: "%@ %dd %@ sem %d: %.2f× (%.1f/%.1f km)",
                                                 arquetipo.id, dias, nombre, semana.numero,
                                                 razon, kms[0], kms[1]))
                        }
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "larga desproporcionada:\n" + fallos.joined(separator: "\n"))
    }

    /// Progresión de la SESIÓN más larga: nunca más de un 10 % (o +2 km,
    /// lo que sea mayor) sobre el fondo más largo de las cuatro semanas
    /// previas —~30 días—. El criterio de la sesión aislada es el que
    /// tiene respaldo (BJSM/JOSPT); el +2 km existe porque a 12 km un
    /// 10 % son 1,2 km y ahí el porcentaje deja de significar algo.
    func testElFondoNoPegaSaltosEnTreintaDias() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for (nombre, baseline) in CatalogoDePrueba.corredores {
                    let largas = plan.semanas.map {
                        CatalogoDePrueba.larga($0, baseline: baseline)
                    }
                    for (indice, larga) in largas.enumerated() {
                        let previas = largas[max(0, indice - 4)..<indice]
                        guard let maximo = previas.max(), maximo > 0 else { continue }
                        let permitido = max(maximo * 1.10, maximo + 2)
                        if larga > permitido + 0.05 {
                            fallos.append(String(format: "%@ %dd %@ sem %d: %.1f km (máx 30 d %.1f)",
                                                 arquetipo.id, dias, nombre,
                                                 plan.semanas[indice].numero, larga, maximo))
                        }
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "saltos de fondo:\n" + fallos.joined(separator: "\n"))
    }

    /// Desde el pico hasta la carrera el fondo SOLO baja. Antes había
    /// planes que prescribían 18 km en la última semana de construcción
    /// y 20 km en la primera de taper.
    func testElFondoNuncaCreceDesdeElPico() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for (nombre, baseline) in CatalogoDePrueba.corredores {
                    let descenso = plan.semanas
                        .filter { $0.fase == .pico || $0.fase == .taper }
                        .map { ($0.numero, CatalogoDePrueba.larga($0, baseline: baseline)) }
                    for (previa, siguiente) in zip(descenso, descenso.dropFirst())
                    where siguiente.1 > previa.1 + 0.05 {
                        fallos.append(String(format: "%@ %dd %@: sem %d %.1f → sem %d %.1f km",
                                             arquetipo.id, dias, nombre,
                                             previa.0, previa.1, siguiente.0, siguiente.1))
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "el fondo crece en el taper:\n" + fallos.joined(separator: "\n"))
    }

    /// Salir de una descarga no puede dejarte por encima de donde
    /// estabas ANTES de ella. Comparar contra la descarga misma no dice
    /// nada —para eso existe la descarga—; lo que importa es que la
    /// semana siguiente retome la progresión, no que la invente.
    func testSalirDeUnaDescargaRetomaLaProgresion() {
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.maratones {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = MotorPlanificacion.recortar(base, aDias: dias)
                for (nombre, baseline) in CatalogoDePrueba.corredores {
                    for (indice, semana) in plan.semanas.enumerated() {
                        guard semana.fase == .descarga, indice > 0,
                              indice + 1 < plan.semanas.count else { continue }
                        let antes = CatalogoDePrueba.volumen(plan.semanas[indice - 1],
                                                             baseline: baseline)
                        let despues = CatalogoDePrueba.volumen(plan.semanas[indice + 1],
                                                               baseline: baseline)
                        guard antes > 0 else { continue }
                        if despues / antes > 1.15 {
                            fallos.append(String(format: "%@ %dd %@ descarga sem %d: %.1f → %.1f km (+%.0f%%)",
                                                 arquetipo.id, dias, nombre, semana.numero,
                                                 antes, despues, (despues / antes - 1) * 100))
                        }
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty, "rebote de descarga:\n" + fallos.joined(separator: "\n"))
    }

    /// El tope viaja con la sesión: convertir una larga en rodaje fácil
    /// no puede devolver una sesión SIN techo de duración. Era una
    /// puerta trasera real — `convertirEnFacil` construía una
    /// definición nueva desde cero.
    ///
    /// La sesión que se convierte es de CALIDAD: la tirada larga no se
    /// convierte por contrato (`Adaptabilidad.para(.tiradaLarga)`), se
    /// mueve o se acorta. El invariante de acá es el tope, no el rol.
    func testConvertirEnFacilConservaElTope() {
        var almacen = AlmacenV2()
        let definicion = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "Umbral 30′",
            segmentos: [Segmento(nombre: "Calentamiento", distanciaKm: 2,
                                 ritmo: .simbolico(.facil)),
                        Segmento(nombre: "Bloque", duracionSegundos: 30 * 60,
                                 ritmo: .simbolico(.umbral))],
            topeDuracionSegundos: 180 * 60)
        let programado = EntrenamientoProgramado(
            definicion: definicion, dia: DiaLocal(anio: 2026, mes: 8, dia: 10),
            rolGuardado: .calidadPrincipal,
            adaptabilidadGuardada: .para(.calidadPrincipal))
        almacen.planActivo = PlanUsuario(
            nombre: "Prueba", origen: .personalizado, fechaAdopcion: Date(),
            semanas: [SemanaPlan(numero: 1, programados: [programado])])

        XCTAssertTrue(almacen.convertirEnFacil(programadoID: programado.id))
        let resultado = almacen.planActivo?.semanas[0].programados[0].definicion
        XCTAssertEqual(resultado?.topeDuracionSegundos, 180 * 60,
                       "convertir en fácil no puede quitar el tope de duración")
    }

    /// El contrato del otro lado: la larga NO se convierte en rodaje.
    func testLaLargaNoSeConvierteEnFacil() {
        var almacen = AlmacenV2()
        let definicion = DefinicionEntrenamiento(
            tipo: .largo, nombre: "Tirada larga",
            segmentos: [Segmento(nombre: "Larga cómoda", distanciaKm: 30,
                                 ritmo: .simbolico(.facil))],
            topeDuracionSegundos: 180 * 60)
        let programado = EntrenamientoProgramado(
            definicion: definicion, dia: DiaLocal(anio: 2026, mes: 8, dia: 10),
            rolGuardado: .tiradaLarga, adaptabilidadGuardada: .para(.tiradaLarga))
        almacen.planActivo = PlanUsuario(
            nombre: "Prueba", origen: .personalizado, fechaAdopcion: Date(),
            semanas: [SemanaPlan(numero: 1, programados: [programado])])

        XCTAssertFalse(almacen.convertirEnFacil(programadoID: programado.id))
        XCTAssertEqual(almacen.planActivo?.semanas[0].programados[0].definicion, definicion,
                       "una conversión rechazada no puede tocar la sesión")
    }

    /// Reducir tampoco lo pierde (y solo puede achicar: el factor es < 1
    /// por contrato, así que jamás puede empujar una sesión al tope).
    func testReducirConservaElTope() {
        var almacen = AlmacenV2()
        let definicion = DefinicionEntrenamiento(
            tipo: .largo, nombre: "Tirada larga",
            segmentos: [Segmento(nombre: "Larga cómoda", distanciaKm: 30,
                                 ritmo: .simbolico(.facil))],
            topeDuracionSegundos: 180 * 60)
        let programado = EntrenamientoProgramado(
            definicion: definicion, dia: DiaLocal(anio: 2026, mes: 8, dia: 10),
            rolGuardado: .tiradaLarga, adaptabilidadGuardada: .para(.tiradaLarga))
        almacen.planActivo = PlanUsuario(
            nombre: "Prueba", origen: .personalizado, fechaAdopcion: Date(),
            semanas: [SemanaPlan(numero: 1, programados: [programado])])

        XCTAssertTrue(almacen.reducir(programadoID: programado.id, factor: 0.8))
        XCTAssertEqual(almacen.planActivo?.semanas[0].programados[0]
            .definicion.topeDuracionSegundos, 180 * 60)
    }
}

// MARK: - Semántica del tope (dominio)

final class TopeDeDuracionTests: XCTestCase {

    /// El corredor de referencia (5 km en 30:00) corre fácil a ~7:56/km.
    private var baseline: PerformanceBaseline? {
        PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: Date(timeIntervalSince1970: 0), fuente: .estimacionInicial,
            distanciaMetros: 5000, segundos: 1800))
    }

    private func larga(_ km: Double, tope: Int?) -> DefinicionEntrenamiento {
        DefinicionEntrenamiento(
            tipo: .largo, nombre: "Tirada larga",
            segmentos: [Segmento(nombre: "Larga cómoda", distanciaKm: km,
                                 ritmo: .simbolico(.facil))],
            topeDuracionSegundos: tope)
    }

    /// Si la distancia entra en el tope, el tope no existe: la sesión
    /// termina por DISTANCIA, tal como está prescrita.
    func testLlegarALaDistanciaAntesDelTopeNoRecortaNada() {
        let definicion = larga(12, tope: 180 * 60)
        XCTAssertEqual(definicion.factorDeTope(baseline: baseline), 1)
        XCTAssertEqual(definicion.volumenKm(baseline: baseline), 12, accuracy: 0.001)
        XCTAssertEqual(definicion.distanciaPrescritaKm, 12)
    }

    /// Y si no entra, el volumen planificado NO puede seguir diciendo
    /// 30 km: dice lo que se va a correr de verdad.
    func testElVolumenPlanificadoReflejaElRecorte() {
        let sinTope = larga(30, tope: nil)
        let conTope = larga(30, tope: 180 * 60)
        XCTAssertEqual(sinTope.volumenKm(baseline: baseline), 30, accuracy: 0.001)

        let recortado = conTope.volumen(baseline: baseline)
        XCTAssertTrue(recortado.recortadoPorTope)
        XCTAssertLessThan(recortado.totalKm, 30)
        // 3 h al ritmo fácil del corredor de referencia.
        let esperado = 10800.0 / Double(CalculoVolumen.ritmo(de: .simbolico(.facil),
                                                            baseline: baseline).segKm)
        XCTAssertEqual(recortado.totalKm, esperado, accuracy: 0.05)
    }

    /// Los bloques por TIEMPO no se tocan: un umbral de 20′ dura 20′
    /// para cualquiera. Lo que se recorta es la distancia.
    func testElTopeNoTocaLosBloquesPorTiempo() {
        let definicion = DefinicionEntrenamiento(
            tipo: .umbral, nombre: "Umbral",
            segmentos: [Segmento(nombre: "Calentamiento", distanciaKm: 30,
                                 ritmo: .simbolico(.facil)),
                        Segmento(nombre: "Bloque", duracionSegundos: 20 * 60,
                                 ritmo: .simbolico(.umbral))],
            topeDuracionSegundos: 180 * 60)
        let volumen = definicion.volumen(baseline: baseline)
        XCTAssertEqual(volumen.segundosPorTiempo, 20 * 60,
                       "el bloque por tiempo no se recorta")
        XCTAssertTrue(volumen.recortadoPorTope)
    }

    /// El reloj recibe los kilómetros recortados, no los declarados:
    /// si el plan dice 30 km y el tope corta en 23, el tramo dice 23.
    func testLosTramosEjecutablesLleganRecortados() {
        var definicion = larga(30, tope: 180 * 60)
        // Al adoptar, el motor deja el ritmo resuelto en `.absoluto`.
        definicion.segmentos[0].ritmo = .absoluto(minSegKm: 470, maxSegKm: 490)
        let tramos = definicion.tramosEjecutables
        XCTAssertEqual(tramos.count, 1)
        XCTAssertEqual(tramos[0].kilometros, 22.5, accuracy: 0.2)   // 10800/480
    }

    /// Sin tope declarado, absolutamente nada cambia respecto de antes.
    func testSinTopeElComportamientoEsIdentico() {
        let definicion = larga(30, tope: nil)
        XCTAssertEqual(definicion.factorDeTope(baseline: baseline), 1)
        XCTAssertEqual(definicion.tramosEjecutables[0].kilometros, 30)
        XCTAssertFalse(definicion.volumen(baseline: baseline).recortadoPorTope)
    }
}

// MARK: - El techo se mide contra el corredor real

/// Los bloques por tiempo se convierten a km con un RITMO: un umbral de
/// 18′ son más kilómetros para quien corre rápido que para quien corre
/// lento. Medir el techo de entrada con un ritmo genérico evaluaba el
/// plan para un corredor que no era este.
final class ArranqueContraBaselineRealTests: XCTestCase {

    /// Mínimo alcanzable por escalado (límite factor→0) para un perfil.
    static func minimoAlcanzable(_ semana: SemanaBase,
                                 baseline: PerformanceBaseline?) -> Double {
        semana.entrenamientos.reduce(0.0) { total, e in
            guard e.tipo != .ritmoCarrera else {
                return total + CatalogoDePrueba.volumen(e, baseline: baseline)
            }
            var m = e
            m.segmentos = e.segmentos.map { s in
                guard s.distanciaKm != nil else { return s }
                var n = s; n.distanciaKm = 1.0; return n
            }
            return total + CatalogoDePrueba.volumen(m, baseline: baseline)
        }
    }

    private var rapido: PerformanceBaseline { CatalogoDePrueba.corredores[0].baseline }
    private var lento: PerformanceBaseline { CatalogoDePrueba.corredores[3].baseline }

    /// El mismo plan y el mismo volumen previo dan factores DISTINTOS
    /// según quién corra: al rápido hay que atenuarlo más, porque sus
    /// bloques por tiempo pesan más kilómetros.
    func testElFactorDependeDelCorredor() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 4)
        let deRapido = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 25, conservador: false, baseline: rapido)
        let deLento = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 25, conservador: false, baseline: lento)

        XCTAssertLessThan(deRapido.factor, deLento.factor,
                          "al corredor rápido el mismo plan le pesa más y hay que atenuarlo más")
        // Y los dos entran bajo SU propio techo, que es el punto.
        XCTAssertTrue(deRapido.diagnostico.cumpleElTecho)
        XCTAssertTrue(deLento.diagnostico.cumpleElTecho)
        for (ajuste, bl) in [(deRapido, rapido), (deLento, lento)] {
            XCTAssertLessThanOrEqual(
                CatalogoDePrueba.volumen(ajuste.base.semanas[0], baseline: bl),
                25 * MotorPlanificacion.factorEntradaMaximo + 0.001)
        }
    }

    /// Sin referencia se cae al ritmo de referencia, que resulta ser el
    /// del corredor de 5K en 30:00. O sea: el cálculo viejo dimensionaba
    /// TODO el catálogo como si cada corredor corriera 5K en 30 minutos.
    func testSinBaselineEquivaleAlCorredorDeReferencia() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mejorar10K(), aDias: 4)
        let generico = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 25, conservador: false, baseline: nil)
        let treintaMinutos = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 25, conservador: false,
            baseline: CatalogoDePrueba.corredores[2].baseline)
        XCTAssertEqual(generico.factor, treintaMinutos.factor, accuracy: 1e-9)
    }

    /// Un plan sin bloques por tiempo no puede depender del baseline:
    /// toda su carga está declarada en kilómetros. Es el control del
    /// experimento — si esto cambiara, el baseline se estaría colando
    /// donde no corresponde.
    func testUnPlanSinBloquesPorTiempoNoDependeDelBaseline() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.mediaMaraton(), aDias: 4)
        let porTiempo = base.semanas[0].entrenamientos
            .flatMap(\.segmentos).filter { $0.distanciaKm == nil && $0.duracionSegundos != nil }
        XCTAssertTrue(porTiempo.isEmpty, "el control asume que este plan no tiene bloques por tiempo")

        let valores = ([nil] + CatalogoDePrueba.corredores.map { Optional($0.baseline) })
            .map { bl in
                MotorPlanificacion.ajustarArranque(
                    base, kmSemanalesActuales: 20, conservador: false, baseline: bl).factor
            }
        for v in valores.dropFirst() {
            XCTAssertEqual(v, valores[0], accuracy: 1e-12)
        }
    }

    /// CARACTERIZACIÓN de la frontera, no aprobación de ella. Con el
    /// baseline real, ser irreducible pasa a depender del corredor:
    /// mejorar 5K a 5 días no cierra para NINGUNO de los cuatro, y a 3
    /// días no cierra solo para el más rápido. Si esto cambia, es
    /// porque cambió el contenido o una constante — y hay que verlo.
    func testLaFronteraDeIrreducibilidadDependeDelCorredor() {
        let piso5K = 18 * RequisitosObjetivo.fraccionPiso      // 7,2
        let cinco = MotorPlanificacion.recortar(ContenidoPlanes.mejorar5K(), aDias: 5)
        for (nombre, bl) in CatalogoDePrueba.corredores {
            XCTAssertGreaterThan(
                Self.minimoAlcanzable(cinco.semanas[0], baseline: bl), piso5K,
                "mejorar-5k 5d tendría que ser irreducible también para \(nombre)")
        }

        let tres = MotorPlanificacion.recortar(ContenidoPlanes.mejorar5K(), aDias: 3)
        XCTAssertGreaterThan(
            Self.minimoAlcanzable(tres.semanas[0], baseline: rapido), piso5K,
            "a 3 días el más rápido sigue sin entrar")
        XCTAssertLessThanOrEqual(
            Self.minimoAlcanzable(tres.semanas[0], baseline: lento), piso5K,
            "a 3 días el más lento SÍ entraría si el factor pudiera bajar")
    }

    /// En el piso de elegibilidad el factor termina SIEMPRE en su piso,
    /// para los 10 planes × frecuencias × los cuatro corredores. O sea:
    /// hoy la búsqueda nunca encuentra una solución interior ahí.
    /// Caracteriza el estado actual; no dice que esté bien.
    func testEnElPisoDeElegibilidadElFactorSiempreTocaSuPiso() {
        for (arquetipo, contenido) in CatalogoDePrueba.todos {
            let req = RequisitosObjetivo.para(arquetipo.objetivo)
            guard req.kmSemanales > 0 else { continue }
            let actuales = req.kmSemanales * RequisitosObjetivo.fraccionPiso
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let base = MotorPlanificacion.recortar(contenido, aDias: dias)
                for (nombre, bl) in CatalogoDePrueba.corredores {
                    let ajuste = MotorPlanificacion.ajustarArranque(
                        base, kmSemanalesActuales: actuales, conservador: true, baseline: bl)
                    XCTAssertEqual(ajuste.factor, MotorPlanificacion.factorArranqueMinimo,
                                   accuracy: 1e-12, "\(arquetipo.id) \(dias)d · \(nombre)")
                    XCTAssertFalse(ajuste.diagnostico.cumpleElTecho,
                                   "\(arquetipo.id) \(dias)d · \(nombre)")
                }
            }
        }
    }
}
