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

    /// Por el nombre CRUDO (ver la nota del mismo helper en
    /// MotorAdaptativoTests): el visible ya depende del idioma.
    private func buscar(_ almacen: AlmacenV2, _ nombre: String) -> UUID {
        almacen.todosLosProgramados.first { $0.definicion.nombreCrudo == nombre }!.id
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let recortado = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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

    /// El plan REAL que el motor sirve a esa frecuencia. No alcanza con
    /// recortar el contenido general: un arquetipo puede declarar una
    /// variante propia para una frecuencia (Mejorar 5K con 3 días), y
    /// auditar el recorte del general dejaría sin probar justamente lo
    /// que el corredor recibe.
    static func variante(_ arquetipo: PlanArquetipo, base: PlanBase,
                         dias: Int) -> PlanBase {
        MotorPlanificacion.recortar(arquetipo.contenido(para: dias) ?? base,
                                    aDias: min(dias, arquetipo.diasMaximos))
    }

    /// Las sesiones del template que SOBREVIVEN al recorte, en el mismo
    /// orden en que el motor las deja. Replica la selección por rol
    /// (carrera > larga > calidad > fácil > recuperación, y a igual rol
    /// el orden del template) para poder comparar cada sesión con su
    /// original exacto. Emparejar por nombre no sirve: una semana tiene
    /// dos "Rodaje suave" de distinta distancia.
    static func sesionesElegidas(_ semana: SemanaBase, dias: Int) -> [EntrenamientoBase] {
        let ordenadas = semana.entrenamientos.enumerated().sorted {
            let a = RolSesion.para($0.element.tipo)
            let b = RolSesion.para($1.element.tipo)
            return a == b ? $0.offset < $1.offset : a < b
        }
        let elegidas = Set(ordenadas.prefix(dias).map(\.offset))
        return elegidas.sorted().map { semana.entrenamientos[$0] }
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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

    /// GUARDRAIL β: la redistribución no puede convertir un rodaje en
    /// una segunda tirada larga. Se compara contra el MISMO plan sin
    /// redistribuir (recorte a la frecuencia máxima, que no tira nada),
    /// porque lo que el guardrail limita es el CRECIMIENTO: una sesión
    /// que el contenido ya diseñó larga —el rodaje medio de los planes
    /// de maratón— conserva su distancia y eso está bien.
    func testLaRedistribucionNoFabricaUnaSegundaTiradaLarga() {
        // El umbral va LITERAL y no leído de `topeSegundaLarga`. Si el
        // test usara la constante que está probando, subirla a 99
        // desactivaría el guardrail Y haría pasar el test: comprobado,
        // así estaba escrito y pasaba con el guardrail apagado.
        let maximoDeUnaFacil = 0.60
        var fallos: [String] = []
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
                let sinRecortar = arquetipo.contenido(para: dias) ?? base
                for (indice, semana) in plan.semanas.enumerated() {
                    let larga = CatalogoDePrueba.larga(semana)
                    guard larga > 0 else { continue }
                    let originales = CatalogoDePrueba.sesionesElegidas(
                        sinRecortar.semanas[indice],
                        dias: min(dias, arquetipo.diasMaximos))
                    guard originales.count == semana.entrenamientos.count else { continue }
                    for (sesion, plantilla) in zip(semana.entrenamientos, originales) {
                        let rol = RolSesion.para(sesion.tipo)
                        guard rol == .facil || rol == .recuperacion else { continue }
                        let volumen = CatalogoDePrueba.volumen(sesion)
                        let original = CatalogoDePrueba.volumen(plantilla)
                        // Creció y quedó por encima del guardrail.
                        guard volumen > original + 0.05,
                              volumen > maximoDeUnaFacil * larga + 0.05
                        else { continue }
                        fallos.append(String(
                            format: "%@ %dd sem %d · %@: %.1f → %.1f km (%.0f%% de una larga de %.1f)",
                            arquetipo.id, dias, semana.numero, sesion.nombre,
                            original, volumen, volumen / larga * 100, larga))
                    }
                }
            }
        }
        XCTAssertTrue(fallos.isEmpty,
                      "la redistribución fabricó una segunda tirada larga en:\n"
                      + fallos.joined(separator: "\n"))
    }

    /// El guardrail limita el crecimiento, NUNCA achica. Una sesión
    /// diseñada larga a propósito tiene que llegar intacta.
    func testElGuardrailNuncaAchicaUnaSesion() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
                let sinRecortar = arquetipo.contenido(para: dias) ?? base
                for (indice, semana) in plan.semanas.enumerated() {
                    let originales = CatalogoDePrueba.sesionesElegidas(
                        sinRecortar.semanas[indice],
                        dias: min(dias, arquetipo.diasMaximos))
                    guard originales.count == semana.entrenamientos.count else {
                        return XCTFail("\(arquetipo.id) \(dias)d sem \(semana.numero): " +
                                       "el recorte no dejó las sesiones que la selección por rol predice")
                    }
                    for (sesion, original) in zip(semana.entrenamientos, originales) {
                        XCTAssertGreaterThanOrEqual(
                            CatalogoDePrueba.volumen(sesion),
                            CatalogoDePrueba.volumen(original) - 0.05,
                            "\(arquetipo.id) \(dias)d sem \(semana.numero) · \(sesion.nombre): " +
                            "el recorte achicó una sesión en vez de solo no dejarla crecer")
                    }
                }
            }
        }
    }

    func testNingunaSemanaTieneMasDeUnaTiradaLarga() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                for semana in CatalogoDePrueba.variante(arquetipo, base: base, dias: dias).semanas {
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
                for semana in CatalogoDePrueba.variante(arquetipo, base: base, dias: dias).semanas {
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
    /// entrada no puede superar lo que el propio plan pide — y, del
    /// otro lado, el plan no puede pedir el día uno MÁS de lo que la
    /// puerta exigió para entrar.
    ///
    /// Las dos direcciones importan y solo una estaba cubierta. El
    /// fondo se comparaba contra la larga MÁXIMA de todo el plan, que
    /// es una cota tan holgada que un requisito bajo jamás la roza:
    /// Mejorar 5K exigía 6 km, su semana 1 prescribía 9 y el invariante
    /// pasaba porque 6 ≤ 12. Eso es exactamente el desvío que hay que
    /// detectar, así que ahora el fondo se mide contra la SEMANA 1.
    ///
    /// Y se recorren TODAS las frecuencias soportadas, no solo
    /// `diasMinimos`: el recorte por disponibilidad cambia el volumen
    /// de la semana 1 (Mejorar 5K son 23,5 km con 3 días y 28,9 con 4),
    /// así que medir una sola frecuencia deja sin probar el resto.
    func testLosRequisitosNoSuperanAlPlanQueHabilitan() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                    let primera = CatalogoDePrueba.volumen(plan.semanas[0], baseline: baseline)
                    let largaPrimera = CatalogoDePrueba.larga(plan.semanas[0], baseline: baseline)
                    let quien = "\(arquetipo.id) · \(dias)d · \(corredor)"

                    // El requisito que DE VERDAD se aplica: el derivado
                    // de la semana 1 de esta variante. La tabla es solo
                    // el fallback y tiene su propio invariante abajo.
                    let requeridoKm = RequisitosObjetivo.volumenParaEntrar(
                        semana1Km: MotorPlanificacion.volumenSemanaBase(plan.semanas[0]))
                    XCTAssertLessThanOrEqual(requeridoKm, pico,
                        "\(quien): pide \(requeridoKm) km/sem y el plan pica en \(pico)")
                    XCTAssertLessThanOrEqual(requeridoKm, primera * 1.05,
                        "\(quien): el requisito debería poder sostenerse el día uno " +
                        "(pide \(requeridoKm), la primera semana son \(primera))")

                    // El fondo, de los dos lados y contra la semana 1.
                    // Los planes que no declaran requisito de fondo
                    // (Primeros 5K) quedan afuera a propósito: completar
                    // una distancia por primera vez no exige nada.
                    guard requisitos.tiradaLargaKm > 0 else { continue }
                    XCTAssertLessThanOrEqual(requisitos.tiradaLargaKm, largaPrimera * 1.05,
                        "\(quien): exige una larga previa de \(requisitos.tiradaLargaKm) km " +
                        "y la semana 1 solo pide \(largaPrimera)")
                    XCTAssertLessThanOrEqual(largaPrimera, requisitos.tiradaLargaKm * 1.05,
                        "\(quien): la puerta se abre con \(requisitos.tiradaLargaKm) km de fondo " +
                        "y la semana 1 pide \(largaPrimera) — el corredor entra a un plan " +
                        "que el día uno le pide más de lo que se le pidió para entrar")
                }
            }
            // Los días no dependen del ritmo ni de la frecuencia elegida.
            XCTAssertEqual(requisitos.diasPorSemana, arquetipo.diasMinimos,
                "\(arquetipo.id): elegibilidad y catálogo no coinciden en días mínimos")
        }
    }

    /// El requisito de volumen ES el techo de arranque despejado, así
    /// que no puede escribirse a mano: se deriva de la semana 1 de la
    /// variante que el corredor recibe. Este test fija el FALLBACK de
    /// tabla al derivado en la frecuencia mínima —la variante más
    /// liviana del objetivo—, para que no pueda quedar desactualizado
    /// en silencio cuando cambie el contenido. Si falla, el mensaje trae
    /// el número nuevo: no se toca el test, se copia el valor.
    func testLaTablaDeVolumenSigueAlDerivado() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
            guard requisitos.kmSemanales > 0 else { continue }
            let plan = CatalogoDePrueba.variante(arquetipo, base: base,
                                                 dias: arquetipo.diasMinimos)
            let derivado = RequisitosObjetivo.volumenParaEntrar(
                semana1Km: MotorPlanificacion.volumenSemanaBase(plan.semanas[0]))
            XCTAssertEqual(requisitos.kmSemanales, derivado,
                "\(arquetipo.id): la tabla dice \(requisitos.kmSemanales) km/sem y " +
                "el derivado de su semana 1 con \(arquetipo.diasMinimos) días es " +
                "\(derivado). Poné \(derivado) en RequisitosObjetivo.")
        }
    }

    /// El requisito de FONDO sí puede vivir en la tabla, y este test es
    /// la razón: la tirada larga no absorbe ni se recorta, así que es la
    /// misma en todas las frecuencias. Si algún día dejara de serlo,
    /// también habría que derivarla.
    func testElFondoDeLaSemana1NoDependeDeLaFrecuencia() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            let largas = (arquetipo.diasMinimos...arquetipo.diasMaximos).map { dias -> Double in
                CatalogoDePrueba.larga(
                    CatalogoDePrueba.variante(arquetipo, base: base, dias: dias).semanas[0])
            }
            for larga in largas {
                XCTAssertEqual(larga, largas[0], accuracy: 0.05,
                    "\(arquetipo.id): el fondo de la semana 1 cambia con la frecuencia " +
                    "(\(largas)), así que el requisito de fondo ya no puede ser de tabla")
            }
        }
    }

    func testTodaSesionCaeEnUnDiaValido() {
        for (arquetipo, base) in CatalogoDePrueba.todos {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                let elegidos = OnboardingDeportivo.diasSugeridos(para: dias)
                let plan = MotorPlanificacion.distribuir(
                    CatalogoDePrueba.variante(arquetipo, base: base, dias: dias), enDias: elegidos)
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

// MARK: - P0: un objetivo imposible no puede quedar como plan activo

/// Reproduce el bug del Build 65: objetivo Maratón con fecha a 5
/// semanas. El motor rechazaba correctamente, pero el onboarding ya
/// había guardado el perfil ANTES de consultarlo, así que quedaba el
/// objetivo puesto y la app mostraba "Faltan 5 semanas para tu carrera"
/// sin ningún plan detrás.
final class ObjetivoImposibleTests: XCTestCase {

    private var lunes: Calendar {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c
    }

    /// El caso EXACTO reportado.
    private func pedidoDelBug(dias: Int = 4) -> PedidoDePlan {
        PedidoDePlan(
            objetivo: .maraton,
            fechaObjetivo: DiaLocal(anio: 2026, mes: 9, dia: 20),
            diasPorSemana: dias,
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1500),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 14),
            actividad: ActividadActual(diasPorSemana: 3, kmSemanales: 30,
                                       tiradaLargaKm: 14, mesesCorriendoRegular: 12))
    }

    func testElMotorRechazaMaratonEnCincoSemanas() {
        guard case .tiempoInsuficiente(let disponibles, let minimas) =
                MotorPlanificacion.proponer(pedidoDelBug(), calendario: lunes) else {
            return XCTFail("un maratón a 5 semanas tiene que rechazarse")
        }
        XCTAssertLessThan(disponibles, minimas)
        XCTAssertEqual(minimas, 16)
    }

    /// El corazón del P0: el resultado del motor tiene que poder
    /// grabarse en el perfil. Antes no había dónde.
    func testElRechazoSeTraduceAMotivoSinPlan() {
        let resultado = MotorPlanificacion.proponer(pedidoDelBug(), calendario: lunes)
        XCTAssertEqual(resultado.motivoSinPlan, .fechaDemasiadoCerca)
        XCTAssertFalse(resultado.generaPlan)
    }

    func testCadaRechazoDelMotorTieneSuMotivo() {
        // Días insuficientes.
        let pocosDias = MotorPlanificacion.proponer(pedidoDelBug(dias: 2), calendario: lunes)
        XCTAssertEqual(pocosDias.motivoSinPlan, .diasInsuficientes)
        // Falta base: volumen y fondo muy por debajo.
        let sinBase = MotorPlanificacion.proponer(PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1500),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 14),
            actividad: ActividadActual(diasPorSemana: 2, kmSemanales: 5,
                                       tiradaLargaKm: 2, mesesCorriendoRegular: 1)),
            calendario: lunes)
        XCTAssertEqual(sinBase.motivoSinPlan, .faltaBase)
        // Una propuesta válida no deja nada pendiente.
        let bien = MotorPlanificacion.proponer(PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1500),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 14),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 45,
                                       tiradaLargaKm: 18, mesesCorriendoRegular: 24)),
            calendario: lunes)
        XCTAssertNil(bien.motivoSinPlan)
        XCTAssertTrue(bien.generaPlan)
    }

    /// El flujo completo tal como lo vive la app: se guarda el perfil,
    /// se consulta al motor, se registra el resultado. Al final NO
    /// puede haber plan activo ni cuenta regresiva.
    func testTrasUnRechazoNoHayPlanActivoNiCuentaRegresiva() {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo()
        perfil.objetivo = .maraton
        perfil.fechaObjetivo = DiaLocal(anio: 2026, mes: 9, dia: 20)
        perfil.diasPorSemana = 4
        perfil.actividad = ActividadActual(diasPorSemana: 3, kmSemanales: 30,
                                           tiradaLargaKm: 14, mesesCorriendoRegular: 12)
        almacen.perfil = perfil

        let resultado = MotorPlanificacion.proponer(pedidoDelBug(), calendario: lunes)
        almacen.perfil?.objetivoSinPlan = resultado.motivoSinPlan

        XCTAssertNil(almacen.planActivo, "no se puede adoptar un plan imposible")
        XCTAssertEqual(almacen.perfilDeportivo.objetivoSinPlan, .fechaDemasiadoCerca,
                       "el perfil tiene que recordar POR QUÉ no hay plan")
        // La intención se conserva: no se le borra lo que quiere.
        XCTAssertEqual(almacen.perfilDeportivo.objetivo, .maraton)
        XCTAssertNotNil(almacen.perfilDeportivo.fechaObjetivo)
    }

    /// Y adoptar un plan de verdad limpia lo pendiente.
    func testAdoptarUnPlanLimpiaElPendiente() {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo()
        perfil.objetivo = .maraton
        perfil.objetivoSinPlan = .fechaDemasiadoCerca
        almacen.perfil = perfil

        guard case .propuesta(let propuesta) = MotorPlanificacion.proponer(PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1500),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 14),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 45,
                                       tiradaLargaKm: 18, mesesCorriendoRegular: 24)),
            calendario: lunes) else {
            return XCTFail("este corredor sí puede")
        }
        almacen.adoptarPlan(propuesta.planUsuario)
        XCTAssertNil(almacen.perfilDeportivo.objetivoSinPlan,
                     "con plan activo no puede quedar un «no llegamos» colgado")
        XCTAssertNotNil(almacen.planActivo)
    }

    /// Los perfiles guardados por builds anteriores no tienen el campo:
    /// tienen que decodificar igual.
    func testUnPerfilViejoDecodificaSinElCampoNuevo() throws {
        let viejo = """
        {"objetivo":"maraton","diasPorSemana":4,"testPendiente":false}
        """
        let perfil = try JSONDecoder().decode(
            PerfilDeportivo.self, from: XCTUnwrap(viejo.data(using: .utf8)))
        XCTAssertEqual(perfil.objetivo, .maraton)
        XCTAssertNil(perfil.objetivoSinPlan)
    }

    /// La viabilidad que muestra la pantalla de fecha tiene que usar
    /// las MISMAS semanas mínimas que el motor: si dijera una cosa y el
    /// motor otra, volveríamos al bug por otro camino.
    func testLaViabilidadCoincideConElMotor() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 14)
        let fecha = DiaLocal(anio: 2026, mes: 9, dia: 20)
        let v = Viabilidad(objetivo: .maraton, fecha: fecha, hoy: hoy, calendario: lunes)
        let viabilidad = try? XCTUnwrap(v)
        XCTAssertNotNil(viabilidad)
        XCTAssertFalse(viabilidad?.alcanza ?? true)
        XCTAssertEqual(viabilidad?.semanasNecesarias, 16)
        XCTAssertGreaterThan(viabilidad?.faltan ?? 0, 0)

        // Y el motor tiene que estar de acuerdo, para el mismo caso.
        let resultado = MotorPlanificacion.proponer(pedidoDelBug(), calendario: lunes)
        XCTAssertFalse(resultado.generaPlan,
                       "la pantalla dice que no alcanza y el motor tiene que coincidir")

        // Con tiempo de sobra, los dos dicen que sí.
        let lejos = DiaLocal(anio: 2027, mes: 6, dia: 1)
        XCTAssertTrue(Viabilidad(objetivo: .maraton, fecha: lejos, hoy: hoy,
                                 calendario: lunes)?.alcanza ?? false)
    }

    /// Para cada plan del catálogo, las semanas que la pantalla dice que
    /// hacen falta son las que el arquetipo declara.
    func testLaViabilidadUsaLasSemanasDeCadaArquetipo() {
        let hoy = DiaLocal(anio: 2026, mes: 1, dia: 5)
        for arquetipo in BibliotecaArquetipos.v1() where arquetipo.contenido != nil {
            let v = Viabilidad(objetivo: arquetipo.objetivo,
                               fecha: DiaLocal(anio: 2026, mes: 6, dia: 1),
                               hoy: hoy, calendario: lunes)
            XCTAssertEqual(v?.semanasNecesarias, arquetipo.semanasMinimas, arquetipo.id)
        }
    }

    func testCadaMotivoOfreceAlMenosUnaSalida() {
        for motivo in MotivoSinPlan.allCases {
            XCTAssertFalse(motivo.accionesSugeridas.isEmpty,
                           "\(motivo) deja al corredor sin nada que hacer")
        }
        XCTAssertTrue(MotivoSinPlan.fechaDemasiadoCerca.accionesSugeridas
            .contains(.cambiarFecha))
        XCTAssertTrue(MotivoSinPlan.diasInsuficientes.accionesSugeridas
            .contains(.ajustarDisponibilidad))
    }
}

// MARK: - Explorar planes: descubribilidad

/// El bug que se veía en TestFlight: "Explorar planes" mostraba solo 5K
/// y 10K. No era elegibilidad — la pantalla leía
/// `Catalogo.planesDisponibles()`, el catálogo V1 legado de dos planes
/// provisionales embebidos como JSON, y los ocho arquetipos reales
/// (todos los de 21K y 42K entre ellos) no aparecían nunca.
///
/// Regla de producto que estos tests fijan: **la elegibilidad describe,
/// nunca esconde.**
final class DescubribilidadDelCatalogoTests: XCTestCase {

    func testTodosLosObjetivosConContenidoSonVisibles() {
        let visibles = CatalogoView.visibles(distanciaMetros: nil, dias: nil)
        let conContenido = BibliotecaArquetipos.v1().filter { $0.contenido != nil }
        XCTAssertEqual(Set(visibles.map(\.id)), Set(conContenido.map(\.id)))
        XCTAssertEqual(visibles.count, 10,
                       "los diez objetivos del catálogo tienen que ser descubribles")
    }

    func testLasCuatroDistanciasEstanRepresentadas() {
        for (nombre, metros) in [("5K", 5000.0), ("10K", 10000.0),
                                 ("21K", 21097.5), ("42K", 42195.0)] {
            let visibles = CatalogoView.visibles(distanciaMetros: metros, dias: nil)
            XCTAssertFalse(visibles.isEmpty,
                           "\(nombre) no tiene ni un plan visible en Explorar planes")
        }
    }

    func testLos21KY42KAparecenAunqueElCorredorNoSeaElegible() {
        // Un corredor que no sostiene NINGÚN objetivo largo.
        let sedentario = PerfilDeportivo(
            objetivo: .primeros5K, diasPorSemana: 3,
            actividad: ActividadActual(diasPorSemana: 2, kmSemanales: 5,
                                       tiradaLargaKm: 2, mesesCorriendoRegular: 1))
        let largos = BibliotecaArquetipos.v1().filter {
            ($0.contenido?.distanciaObjetivoKm ?? 0) > 20
        }
        XCTAssertEqual(largos.count, 6, "seis planes de 21K/42K en el catálogo")

        let visibles = CatalogoView.visibles(distanciaMetros: nil, dias: nil).map(\.id)
        for arquetipo in largos {
            XCTAssertTrue(visibles.contains(arquetipo.id),
                          "\(arquetipo.id) desapareció de Explorar planes")
            // Y el estado que se le muestra al lado tiene que DECIR que
            // falta base, no hacer desaparecer la fila.
            let estado = EstadoDeObjetivo(arquetipo: arquetipo, perfil: sedentario,
                                          tieneBaseline: false)
            XCTAssertEqual(estado?.nivel, .faltaBase,
                           "\(arquetipo.id): a este corredor le falta base y hay que decírselo")
            XCTAssertFalse(estado?.motivos.isEmpty ?? true,
                           "\(arquetipo.id): decir 'falta base' sin decir qué falta no sirve")
        }
    }

    func testElEstadoDescribeAlCorredorPreparado() {
        // Corredor con base de sobra para una primera media maratón.
        let preparado = PerfilDeportivo(
            objetivo: .mediaMaraton, diasPorSemana: 5,
            actividad: ActividadActual(diasPorSemana: 5, kmSemanales: 55,
                                       tiradaLargaKm: 18, mesesCorriendoRegular: 24))
        let media = BibliotecaArquetipos.v1().first { $0.id == "media-maraton" }
        let estado = EstadoDeObjetivo(arquetipo: XCTUnwrap2(media),
                                      perfil: preparado, tieneBaseline: true)
        XCTAssertEqual(estado?.nivel, .listo)
    }

    /// El caso que faltaba: un corredor que marcó MENOS días de los que
    /// el objetivo pide. Tiene que seguir viendo los diez objetivos, y
    /// el estado tiene que DECIRLE cuántos días pide — no desaparecer.
    func testConMenosDiasQueElMinimoLosObjetivosSiguenVisibles() {
        let dosDias = PerfilDeportivo(
            objetivo: .primeros5K, diasPorSemana: 2,
            actividad: ActividadActual(diasPorSemana: 2, kmSemanales: 20,
                                       tiradaLargaKm: 8, mesesCorriendoRegular: 12))
        // La lista no mira el perfil: sigue completa.
        XCTAssertEqual(CatalogoView.visibles(distanciaMetros: nil, dias: nil).count, 10,
                       "elegir pocos días no puede borrar objetivos del catálogo")

        for arquetipo in BibliotecaArquetipos.v1() where arquetipo.contenido != nil {
            let estado = EstadoDeObjetivo(arquetipo: arquetipo, perfil: dosDias,
                                          tieneBaseline: false)
            XCTAssertNotNil(estado,
                            "\(arquetipo.id): el estado desapareció en vez de explicar")
            let minimo = RequisitosObjetivo.para(arquetipo.objetivo).diasPorSemana
            if minimo > 2 {
                XCTAssertEqual(estado?.diasQueFaltan, minimo,
                               "\(arquetipo.id): pide \(minimo) días y no se lo dice")
                XCTAssertNotNil(estado?.textoDeDias)
            } else {
                XCTAssertNil(estado?.diasQueFaltan,
                             "\(arquetipo.id): acepta 2 días, no hay nada que reclamar")
            }
        }
    }

    /// Y el 21K/42K en concreto, que es lo que se vio en TestFlight.
    func testLos21KY42KSiguenVisiblesConDosDiasMarcados() {
        let dosDias = PerfilDeportivo(objetivo: .primeros5K, diasPorSemana: 2)
        let visibles = CatalogoView.visibles(distanciaMetros: nil, dias: nil).map(\.id)
        for distancia in [21097.5, 42195.0] {
            let deEsaDistancia = CatalogoView.visibles(distanciaMetros: distancia, dias: nil)
            XCTAssertFalse(deEsaDistancia.isEmpty)
            for arquetipo in deEsaDistancia {
                XCTAssertTrue(visibles.contains(arquetipo.id))
                // Con 2 días marcados, el objetivo se ve y se explica.
                let estado = EstadoDeObjetivo(arquetipo: arquetipo, perfil: dosDias,
                                              tieneBaseline: false)
                XCTAssertNotNil(estado?.diasQueFaltan,
                                "\(arquetipo.id): con 2 días hay que decir cuántos pide")
            }
        }
    }

    /// La elegibilidad no toca la LISTA, solo el mensaje. Dos perfiles
    /// opuestos tienen que ver exactamente el mismo catálogo.
    func testLaListaEsLaMismaParaCualquierPerfil() {
        let sedentario = PerfilDeportivo(
            objetivo: .primeros5K, diasPorSemana: 2,
            actividad: ActividadActual(diasPorSemana: 1, kmSemanales: 2,
                                       tiradaLargaKm: 1, mesesCorriendoRegular: 0))
        let veterano = PerfilDeportivo(
            objetivo: .maratonRendimiento, diasPorSemana: 6,
            actividad: ActividadActual(diasPorSemana: 6, kmSemanales: 90,
                                       tiradaLargaKm: 32, mesesCorriendoRegular: 60))
        let lista = CatalogoView.visibles(distanciaMetros: nil, dias: nil).map(\.id)
        XCTAssertEqual(lista.count, 10)
        // El estado sí cambia; la lista no.
        for arquetipo in BibliotecaArquetipos.v1() where arquetipo.contenido != nil {
            _ = EstadoDeObjetivo(arquetipo: arquetipo, perfil: sedentario, tieneBaseline: false)
            _ = EstadoDeObjetivo(arquetipo: arquetipo, perfil: veterano, tieneBaseline: true)
            XCTAssertTrue(lista.contains(arquetipo.id))
        }
    }

    /// El filtro de días acepta el RANGO del arquetipo, no su valor
    /// declarado en el contenido: un plan de 4-5 días tiene que salir
    /// tanto en "4 días" como en "5 días".
    func testElFiltroDeDiasUsaElRangoDelArquetipo() {
        for arquetipo in BibliotecaArquetipos.v1() where arquetipo.contenido != nil {
            for dias in arquetipo.diasMinimos...arquetipo.diasMaximos {
                XCTAssertTrue(
                    CatalogoView.visibles(distanciaMetros: nil, dias: dias)
                        .contains { $0.id == arquetipo.id },
                    "\(arquetipo.id) acepta \(dias) días y no aparece con ese filtro")
            }
        }
    }

    private func XCTUnwrap2(_ arquetipo: PlanArquetipo?) -> PlanArquetipo {
        guard let arquetipo else {
            XCTFail("falta el arquetipo")
            return BibliotecaArquetipos.v1()[0]
        }
        return arquetipo
    }
}

// MARK: - Contrato del Coach con el backend

/// La otra mitad del contrato que vive en functions/test/contrato.test.js.
/// Allá se comprueba que zod ACEPTA lo que Swift manda; acá, que Swift
/// manda exactamente esas claves y ninguna más.
///
/// Importa porque el schema del backend es `.strict()`: una clave nueva
/// en el DTO —agregada con la mejor intención— hace que el backend
/// devuelva 400 para todos los usuarios, y del lado de la app se ve
/// como "el Coach no pudo responder".
final class ContratoCoachTests: XCTestCase {

    private func json(_ valor: some Encodable) throws -> [String: Any] {
        let datos = try JSONEncoder().encode(valor)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: datos) as? [String: Any])
    }

    func testElContextoMandaExactamenteLasClavesDelSchema() throws {
        let contexto = ContextoCoach(
            idioma: "es", objetivo: "maraton", fechaCarrera: "2026-11-15",
            diasElegidos: [2, 4, 6, 7], diasImposibles: [3],
            baseline: .init(distanciaMetros: 5000, segundos: 1470),
            semanaActual: 5, semanasTotales: 16, faseSemanaActual: "construccion",
            cumplimientoPorciento: 82, kmUltimas4Semanas: 148.6,
            ventanas: [], eventos: [], proximosEntrenamientos: [], ultimasSesiones: [])
        let claves = Set(try json(contexto).keys)
        // Espejo literal de ContextoCoach en functions/schemas.js.
        XCTAssertEqual(claves, [
            "idioma", "objetivo", "fechaCarrera", "diasElegidos", "diasImposibles",
            "baseline", "semanaActual", "semanasTotales", "faseSemanaActual",
            "cumplimientoPorciento", "kmUltimas4Semanas", "ventanas", "eventos",
            "proximosEntrenamientos", "ultimasSesiones",
        ], "el DTO y el schema de zod se separaron: el backend va a devolver 400")
    }

    /// El caso que rompía: Swift OMITE la clave de un Optional nil, y el
    /// schema la exigía presente. Este test fija el comportamiento del
    /// encoder para que el schema del backend pueda confiar en él.
    func testLosOpcionalesNilNoViajanComoClave() throws {
        let contexto = ContextoCoach(
            idioma: "es", objetivo: "primeros5K", fechaCarrera: nil,
            diasElegidos: [2, 4, 6], diasImposibles: [],
            baseline: nil, semanaActual: nil, semanasTotales: nil,
            faseSemanaActual: nil, cumplimientoPorciento: nil,
            kmUltimas4Semanas: nil,
            ventanas: [], eventos: [], proximosEntrenamientos: [], ultimasSesiones: [])
        let claves = Set(try json(contexto).keys)
        for ausente in ["fechaCarrera", "baseline", "semanaActual", "semanasTotales",
                        "faseSemanaActual", "cumplimientoPorciento", "kmUltimas4Semanas"] {
            XCTAssertFalse(claves.contains(ausente),
                "\(ausente) viaja aunque sea nil — el schema tiene que seguir siendo nullish")
        }
        XCTAssertEqual(claves, ["idioma", "objetivo", "diasElegidos", "diasImposibles",
                                "ventanas", "eventos", "proximosEntrenamientos",
                                "ultimasSesiones"])
    }

    func testLasSubestructurasTambienRespetanElSchema() throws {
        XCTAssertEqual(Set(try json(ContextoCoach.VentanaDTO(
            dias: 7, km: 38.2, salidas: 4, tiradaMasLargaKm: 16,
            mayorPausaDias: 2)).keys),
            ["dias", "km", "salidas", "tiradaMasLargaKm", "mayorPausaDias"])
        XCTAssertEqual(Set(try json(ContextoCoach.BaselineDTO(
            distanciaMetros: 5000, segundos: 1470)).keys),
            ["distanciaMetros", "segundos"])
        XCTAssertEqual(Set(try json(ContextoCoach.ProgramadoDTO(
            programadoID: UUID().uuidString.lowercased(), dia: "2026-08-18",
            nombre: "Umbral 28′", tipo: "umbral", km: 9.4)).keys),
            ["programadoID", "dia", "nombre", "tipo", "km"])
        XCTAssertEqual(Set(try json(ContextoCoach.SesionDTO(
            fecha: "2026-08-13", tipo: "facil", km: 10, ritmoSegKm: 330,
            cumplida: true, sensacion: "bien")).keys),
            ["fecha", "tipo", "km", "ritmoSegKm", "cumplida", "sensacion"])
        XCTAssertEqual(Set(try json(ContextoCoach.EventoDTO(
            tipo: "molestia", severidad: "alta", programadoID: nil,
            detalle: nil)).keys),
            ["tipo", "severidad"])
    }

    /// Los rawValue que el DTO manda tienen que estar en el enum de zod.
    func testLasSensacionesCoincidenConElEnumDelBackend() {
        XCTAssertEqual(Set(SensacionEsfuerzo.allCases.map(\.rawValue)),
                       ["muyBien", "bien", "exigido", "muyExigido"])
    }

    /// El último eslabón de la cadena, con la respuesta REAL que
    /// devolvió el backend desplegado (`coach(us-central1)`, acción
    /// `reorganizar`, 14/8/2026). Copiada tal cual, solo con los
    /// programadoID reemplazados por los del plan de prueba.
    ///
    /// Verifica lo que ningún test de schema puede: que lo que sale de
    /// OpenAI, después de pasar por el structured output y por el
    /// Codable del cliente, llega al dominio como operaciones que el
    /// validador acepta y el aplicador ejecuta.
    func testLaRespuestaRealDelBackendLlegaAlDominio() throws {
        var almacen = almacenConPlan()
        let umbral = try XCTUnwrap(almacen.todosLosProgramados
            .first { $0.definicion.nombreCrudo == "Umbral" })
        let rodaje = try XCTUnwrap(almacen.todosLosProgramados
            .first { $0.definicion.nombreCrudo == "Rodaje" })
        let larga = try XCTUnwrap(almacen.todosLosProgramados
            .first { $0.definicion.nombreCrudo == "Larga" })

        let respuestaDelBackend = """
        {
          "explicacion": "Como esta semana no podés correr el jueves y el día es elegido, te propongo mantener los entrenamientos restantes y omitir el del jueves.",
          "cambios": [
            {"tipo": "omitir", "programadoID": "\(umbral.id.uuidString.lowercased())", "nuevoDia": null, "factor": null},
            {"tipo": "mantener", "programadoID": "\(rodaje.id.uuidString.lowercased())", "nuevoDia": null, "factor": null},
            {"tipo": "mantener", "programadoID": "\(larga.id.uuidString.lowercased())", "nuevoDia": null, "factor": null}
          ]
        }
        """

        let ajuste = try JSONDecoder().decode(
            CoachWeekAdjustment.self, from: XCTUnwrap(respuestaDelBackend.data(using: .utf8)))
        XCTAssertEqual(ajuste.propuestas.count, 3)
        XCTAssertEqual(ajuste.propuestasQueMutan.count, 1,
                       "dos «mantener» no mutan nada; solo el omitir")

        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 11)
        let validas = ValidadorDeCoach.validas(ajuste.propuestasQueMutan,
                                               en: almacen, hoy: hoy)
        XCTAssertEqual(validas.count, 1, "el validador rechazó el omitir del backend")

        let aplicados = AplicadorAdaptacion.aplicar(validas, a: &almacen, hoy: hoy,
                                                    origen: .coach, motivo: "test e2e")
        XCTAssertEqual(aplicados, 1)
        XCTAssertEqual(almacen.todosLosProgramados.first { $0.id == umbral.id }?.resolucion,
                       .omitido, "la sesión no quedó omitida en el plan")
    }

    /// La carrera objetivo es intocable, venga de donde venga la
    /// propuesta. Si el modelo alguna vez la propone, muere acá.
    func testElValidadorFrenaLoQueElModeloNoDeberiaProponer() throws {
        let almacen = almacenConPlan()
        let larga = try XCTUnwrap(almacen.todosLosProgramados
            .first { $0.definicion.nombreCrudo == "Larga" })
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 11)

        // Un ID que no existe en el plan: se descarta.
        let inventado = CambioPropuesto.omitir(programadoID: UUID())
        XCTAssertFalse(ValidadorDeCoach.validar(inventado, en: almacen, hoy: hoy).permitido)

        // Reprogramar a una fecha pasada: se descarta.
        let alPasado = CambioPropuesto.reprogramar(
            programadoID: larga.id, a: DiaLocal(anio: 2026, mes: 8, dia: 1))
        XCTAssertFalse(ValidadorDeCoach.validar(alPasado, en: almacen, hoy: hoy).permitido)
    }

    private func almacenConPlan() -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.activado = true
        var perfil = PerfilDeportivo()
        perfil.diasElegidos = [1, 3, 5, 7]
        almacen.perfil = perfil
        func hacer(_ nombre: String, _ tipo: TipoEntrenamiento,
                   _ km: Double, _ dia: Int) -> EntrenamientoProgramado {
            let rol = RolSesion.para(tipo)
            return EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: tipo, nombre: nombre,
                    segmentos: [Segmento(nombre: nombre, distanciaKm: km,
                                         ritmo: .simbolico(.facil))]),
                dia: DiaLocal(anio: 2026, mes: 8, dia: dia),
                rolGuardado: rol, adaptabilidadGuardada: .para(rol))
        }
        almacen.planActivo = PlanUsuario(
            nombre: "T", fechaAdopcion: Date(timeIntervalSince1970: 0), semanas: [
                SemanaPlan(numero: 1, programados: [
                    hacer("Umbral", .umbral, 8, 12),
                    hacer("Rodaje", .facil, 7, 14),
                    hacer("Larga", .largo, 16, 16),
                ], reglas: ReglasSemana(fase: .construccion)),
            ])
        return almacen
    }

    /// La traducción de la respuesta a operaciones del dominio: solo las
    /// cinco válidas, y cualquier cosa rara se descarta en silencio en
    /// vez de "interpretarse".
    func testSoloLasCincoOperacionesSobrevivenLaTraduccion() {
        let id = UUID().uuidString.lowercased()
        let ajuste = CoachWeekAdjustment(explicacion: "x", cambios: [
            .init(tipo: "mantener", programadoID: id, nuevoDia: nil, factor: nil),
            .init(tipo: "omitir", programadoID: id, nuevoDia: nil, factor: nil),
            .init(tipo: "convertir", programadoID: id, nuevoDia: nil, factor: nil),
            .init(tipo: "reducir", programadoID: id, nuevoDia: nil, factor: 0.8),
            .init(tipo: "reprogramar", programadoID: id, nuevoDia: "2026-08-20", factor: nil),
            // Todo lo que sigue se DESCARTA.
            .init(tipo: "aumentar", programadoID: id, nuevoDia: nil, factor: 1.5),
            .init(tipo: "reducir", programadoID: id, nuevoDia: nil, factor: 1.4),
            .init(tipo: "reducir", programadoID: id, nuevoDia: nil, factor: nil),
            .init(tipo: "reprogramar", programadoID: id, nuevoDia: "no-es-fecha", factor: nil),
            .init(tipo: "omitir", programadoID: "no-es-uuid", nuevoDia: nil, factor: nil),
        ])
        XCTAssertEqual(ajuste.propuestas.count, 5,
                       "sobrevivió algo que no es una de las cinco operaciones válidas")
        XCTAssertEqual(ajuste.propuestasQueMutan.count, 4,
                       "«mantener» no muta nada y no debería contarse como propuesta")
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
                                $0.definicion.nombreCrudo == "Umbral" }?.id,
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
                let base = CatalogoDePrueba.variante(arquetipo, base: contenido, dias: dias)
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
                let base = CatalogoDePrueba.variante(arquetipo, base: contenido, dias: dias)
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

    /// Corredor con volumen suficiente pero fondo demasiado corto:
    /// `requiereFaseBase` por fondoCorto.
    ///
    /// El volumen (35 km/sem) está elegido para DISCRIMINAR entre los
    /// dos techos sobre la variante de 4 días, cuya semana 1 son 38,9 km:
    /// con el permisivo (1,2 × 35 = 42) la semana entra sola y no se
    /// atenúa nada; con el conservador (1,0 × 35 = 35) hay que bajarla.
    /// Si no discriminara, los dos tests de abajo pasarían por casualidad.
    ///
    /// Antes eran 40 km/sem, calibrados contra una semana 1 de 47,9. El
    /// guardrail de la segunda tirada larga bajó esa semana a 38,9, así
    /// que 40 dejó de atenuar por ningún camino y el discriminador se
    /// apagó. Cambia la fixture, no lo que se afirma.
    private func pedidoQueInsiste(aceptaConservador: Bool) -> PedidoDePlan {
        PedidoDePlan(
            objetivo: .maraton, fechaObjetivo: nil, diasPorSemana: 4,
            diasConcretos: [2, 4, 6, 7],
            referencia: ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                              distanciaMetros: 5000, segundos: 1470),
            hoy: DiaLocal(anio: 2026, mes: 8, dia: 10),
            actividad: ActividadActual(diasPorSemana: 4, kmSemanales: 35,
                                       tiradaLargaKm: 4, mesesCorriendoRegular: 6),
            aceptaConservador: aceptaConservador)
    }

    /// El discriminador, explícito: con el techo permisivo esta misma
    /// semana 1 NO se atenúa. Si esto dejara de valer, los dos tests que
    /// siguen dejarían de probar lo que dicen probar.
    func testLaFixtureDiscriminaEntreLosDosTechos() {
        let base = MotorPlanificacion.recortar(ContenidoPlanes.maraton(), aDias: 4)
        let permisivo = MotorPlanificacion.ajustarArranque(
            base, kmSemanalesActuales: 35, conservador: false)
        XCTAssertEqual(permisivo.factor, 1, accuracy: 0.001,
                       "con el techo permisivo esta fixture no tiene que atenuar nada")
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
                       35 * MotorPlanificacion.factorEntradaConservador, accuracy: 0.001,
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
            base, kmSemanalesActuales: 35, conservador: true)
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let plan = CatalogoDePrueba.variante(arquetipo, base: base, dias: dias)
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
                let base = CatalogoDePrueba.variante(arquetipo, base: contenido, dias: dias)
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

// MARK: - Localización del contenido deportivo
//
// El bug de arquitectura: los títulos y descripciones de los
// entrenamientos nacían como literales en español y se CONGELABAN en el
// snapshot al adoptar el plan. De ahí en más eran datos, no texto, y
// ninguna capa de presentación podía traducirlos.
//
// La regla que protegen estos tests: el plan guarda QUÉ ES cada cosa
// (una clave), no cómo se llama. El texto se arma al mostrarlo.

final class LocalizacionContenidoDeportivoTests: XCTestCase {

    /// TODO el catálogo, sesión por sesión y tramo por tramo.
    private func todoElContenido() -> [PlanBase] {
        var planes: [PlanBase] = []
        for arquetipo in BibliotecaArquetipos.v1() {
            if let base = arquetipo.contenido { planes.append(base) }
            planes.append(contentsOf: arquetipo.contenidoPorDias.values)
        }
        return planes
    }

    // ---- EL INVARIANTE

    /// Ninguna sesión del contenido declarativo puede depender de un
    /// string: si no trae clave, su título quedó congelado en español.
    func testElContenidoDeclarativoDeclaraClaveEnCadaSesion() {
        for base in todoElContenido() where !base.provisional {
            for semana in base.semanas {
                for entrenamiento in semana.entrenamientos {
                    XCTAssertNotNil(entrenamiento.clave,
                                    "\(base.id) semana \(semana.numero): «\(entrenamiento.nombre)» sin clave")
                    for segmento in entrenamiento.segmentos {
                        XCTAssertNotNil(segmento.clave,
                                        "\(base.id): tramo «\(segmento.nombre)» sin clave")
                    }
                }
            }
        }
    }

    /// El contenido PROVISIONAL (catálogo V1, JSON embebido) no declara
    /// claves, así que su rescate es la tabla: todo lo que muestra tiene
    /// que estar ahí, o quedaría en español con la app en inglés.
    func testElContenidoProvisionalEstaEnLaTablaDeRescate() {
        for base in todoElContenido() where base.provisional {
            for semana in base.semanas {
                for entrenamiento in semana.entrenamientos {
                    XCTAssertTrue(TextosLegado.conoceEntrenamiento(entrenamiento.nombre),
                                  "\(base.id): el título «\(entrenamiento.nombre)» no está en la tabla")
                    XCTAssertTrue(TextosLegado.conoceDescripcion(entrenamiento.descripcion),
                                  "\(base.id): la descripción «\(entrenamiento.descripcion)» no está en la tabla")
                    for segmento in entrenamiento.segmentos {
                        XCTAssertTrue(TextosLegado.conoceSegmento(segmento.nombre),
                                      "\(base.id): el tramo «\(segmento.nombre)» no está en la tabla")
                    }
                }
            }
        }
    }

    /// Todo arquetipo tiene clave de plan: el nombre del plan también se
    /// congelaba al adoptar.
    func testTodoArquetipoTieneClaveDePlan() {
        let claves = BibliotecaArquetipos.v1().map(\.clave)
        XCTAssertEqual(Set(claves).count, claves.count, "dos arquetipos comparten clave")
        for arquetipo in BibliotecaArquetipos.v1() {
            XCTAssertEqual(arquetipo.nombre, arquetipo.clave.nombre)
        }
    }

    // ---- CANÓNICO vs LOCALIZADO
    //
    // El host de tests corre en el idioma del simulador (hoy inglés), así
    // que NO se puede comparar el canónico contra el localizado: darían
    // distinto justamente cuando todo funciona. Lo que sí se puede
    // verificar es que cada canónico sea una CLAVE REAL del catálogo de
    // strings — como el idioma fuente es español, la clave es el propio
    // texto en español. Si alguien edita el literal de `String(localized:)`
    // y se olvida del canónico (o al revés), la clave deja de existir y
    // esto falla.

    /// El catálogo en español, para preguntarle si una clave existe.
    private var catalogoES: Bundle {
        let ruta = Bundle(for: LocalizacionContenidoDeportivoTests.self)
            .path(forResource: "es", ofType: "lproj")
            ?? Bundle.main.path(forResource: "es", ofType: "lproj")
        return ruta.flatMap(Bundle.init(path:)) ?? .main
    }

    private func esClaveDelCatalogo(_ texto: String) -> Bool {
        // Un texto con interpolación ya resuelta ("Umbral 32′") no es la
        // clave del catálogo, que la guarda como "Umbral %lld′". Esos se
        // verifican por separado, en el test de tokens.
        catalogoES.localizedString(forKey: texto, value: "␀", table: nil) != "␀"
    }

    func testCadaCanonicoEsUnaClaveDelCatalogo() {
        let sinParametros: [ClaveEntrenamiento] = [
            .rodajeSuave, .rodajeMedio, .rodajeMedioFacil, .recuperacion,
            .tiradaLarga, .tiradaLargaConFinal, .activacion,
            .carrera(distancia: .cinco), .carrera(distancia: .diez),
            .carrera(distancia: .media), .carrera(distancia: .maraton),
        ]
        for clave in sinParametros {
            XCTAssertTrue(esClaveDelCatalogo(clave.nombreCanonico),
                          "«\(clave.nombreCanonico)» no es clave del catálogo (título de \(clave.token))")
            XCTAssertTrue(esClaveDelCatalogo(clave.descripcionCanonica),
                          "la descripción de \(clave.token) no es clave del catálogo")
        }
        let tramos: [ClaveSegmento] = [
            .rodaje, .rodajeMedio, .troteSuave, .largaComoda, .finalRitmoMaraton,
            .calentamiento, .bloqueUmbral, .vueltaALaCalma, .trotePausa,
            .alRitmoObjetivo, .carrera(distancia: .maraton),
        ]
        for clave in tramos {
            XCTAssertTrue(esClaveDelCatalogo(clave.nombreCanonico),
                          "«\(clave.nombreCanonico)» no es clave del catálogo")
        }
        for clave in ClavePlan.allCases {
            XCTAssertTrue(esClaveDelCatalogo(clave.nombreCanonico),
                          "«\(clave.nombreCanonico)» no es clave del catálogo")
        }
    }

    /// Y el localizado SÍ está traducido: si `nombre` devolviera el
    /// español con la app en inglés, el bug seguiría vivo y este test
    /// —que corre en inglés— lo detecta.
    func testElContenidoSeTraduceDeVerdad() throws {
        try XCTSkipIf(Bundle.main.preferredLocalizations.first == "es",
                      "corriendo en español no hay nada que distinguir")
        XCTAssertNotEqual(ClaveEntrenamiento.tiradaLarga.nombre,
                          ClaveEntrenamiento.tiradaLarga.nombreCanonico)
        XCTAssertNotEqual(ClaveSegmento.largaComoda.nombre,
                          ClaveSegmento.largaComoda.nombreCanonico)
        XCTAssertNotEqual(TextosLegado.entrenamiento("Tirada larga"), "Tirada larga")
    }

    func testElCanonicoYElLocalizadoTienenLaMismaForma() {
        let entrenamientos: [ClaveEntrenamiento] = [
            .rodajeSuave, .rodajeMedio, .rodajeMedioFacil, .recuperacion,
            .tiradaLarga, .tiradaLargaConFinal, .activacion,
            .umbral(minutos: 32), .series(repeticiones: 6, minutos: 3),
            .ritmoObjetivo(distancia: .media, km: 8),
            .ritmoObjetivo(distancia: .maraton, km: 12),
            .ritmoObjetivo(distancia: .cinco, km: 4),
            .ritmoObjetivo(distancia: .diez, km: 6),
            .carrera(distancia: .cinco), .carrera(distancia: .diez),
            .carrera(distancia: .media), .carrera(distancia: .maraton),
        ]
        // Ni el título ni la descripción pueden quedar vacíos en ningún
        // idioma, y los parámetros tienen que aparecer en los dos lados.
        for clave in entrenamientos {
            XCTAssertFalse(clave.nombre.isEmpty, "título vacío en \(clave.token)")
            XCTAssertFalse(clave.nombreCanonico.isEmpty, "canónico vacío en \(clave.token)")
            XCTAssertFalse(clave.descripcion.isEmpty, "descripción vacía en \(clave.token)")
            XCTAssertFalse(clave.descripcionCanonica.isEmpty)
        }
        XCTAssertTrue(ClaveEntrenamiento.umbral(minutos: 32).nombre.contains("32"),
                      "el parámetro tiene que sobrevivir a la traducción")
        XCTAssertTrue(ClaveEntrenamiento.umbral(minutos: 32).nombreCanonico.contains("32"))
        let seis = ClaveEntrenamiento.series(repeticiones: 6, minutos: 3)
        XCTAssertTrue(seis.nombre.contains("6") && seis.nombre.contains("3"))
        // La distancia del bloque se muestra en la unidad del corredor
        // (8 km son 5 mi), así que la garantía va sobre el canónico.
        XCTAssertTrue(ClaveEntrenamiento.ritmoObjetivo(distancia: .media, km: 8)
                        .nombreCanonico.contains("8 km"))
        XCTAssertFalse(ClaveEntrenamiento.ritmoObjetivo(distancia: .media, km: 8)
                        .nombre.isEmpty)

        let segmentos: [ClaveSegmento] = [
            .rodaje, .rodajeMedio, .troteSuave, .largaComoda, .finalRitmoMaraton,
            .calentamiento, .bloqueUmbral, .vueltaALaCalma, .trotePausa,
            .alRitmoObjetivo, .intervalo(numero: 3), .cambioDeRitmo(numero: 2),
            .carrera(distancia: .maraton),
        ]
        for clave in segmentos {
            XCTAssertFalse(clave.nombre.isEmpty, "tramo vacío \(clave.token)")
            XCTAssertFalse(clave.nombreCanonico.isEmpty)
        }
        XCTAssertTrue(ClaveSegmento.intervalo(numero: 3).nombre.contains("3"))

        for clave in ClavePlan.allCases {
            XCTAssertFalse(clave.nombre.isEmpty, "plan \(clave.rawValue)")
            XCTAssertFalse(clave.nombreCanonico.isEmpty)
        }
    }

    // ---- LO QUE SE CONGELA

    /// Adoptar guarda el ESPAÑOL canónico, no el idioma en que se armó
    /// el plan: el archivo no puede quedar atado al idioma que tenía el
    /// corredor ese día.
    func testAdoptarCongelaElEspanolCanonico() throws {
        let base = try XCTUnwrap(BibliotecaArquetipos.v1()
            .first { $0.clave == .mediaMaraton }?.contenido)
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 17),
                                fechaAdopcion: Date())
        let programados = plan.semanas.flatMap(\.programados)
        XCTAssertFalse(programados.isEmpty)
        for programado in programados {
            let definicion = programado.definicion
            let clave = try XCTUnwrap(definicion.clave, "la clave tiene que viajar al snapshot")
            XCTAssertEqual(definicion.nombreCrudo, clave.nombreCanonico)
            XCTAssertEqual(definicion.descripcionCruda, clave.descripcionCanonica)
            for segmento in definicion.segmentos {
                let claveSeg = try XCTUnwrap(segmento.clave)
                XCTAssertEqual(segmento.nombreCrudo, claveSeg.nombreCanonico)
            }
        }
    }

    /// El nombre del PLAN también viaja como clave, y lo que queda
    /// escrito es el canónico.
    func testElNombreDelPlanViajaComoClave() {
        var perfil = PerfilDeportivo()
        perfil.diasPorSemana = 4
        perfil.diasElegidos = [2, 4, 6, 7]
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 17)
        // Media maratón recomienda baseline: sin referencia el motor
        // responde `faltaBaseline` y no habría plan que mirar.
        let marca = ReferenciaRendimiento(fecha: Date(), fuente: .marcaManual,
                                          distanciaMetros: 10000, segundos: 48 * 60)
        guard let pedido = PedidoDePlan(perfil: perfil, objetivo: .mediaMaraton,
                                        referencia: marca, hoy: hoy),
              case .propuesta(let propuesta) = MotorPlanificacion.proponer(pedido)
        else { return XCTFail("el motor no propuso un plan") }
        XCTAssertEqual(propuesta.planUsuario.clave, .mediaMaraton)
        XCTAssertEqual(propuesta.planUsuario.nombreCrudo, ClavePlan.mediaMaraton.nombreCanonico)
        XCTAssertEqual(propuesta.planUsuario.nombre, ClavePlan.mediaMaraton.nombre)
    }

    // ---- COMPATIBILIDAD

    /// Un plan de una build ANTERIOR no tiene claves. Su texto congelado
    /// se rescata por tabla: se ve traducido sin migrar ni tocar nada.
    func testUnPlanViejoSinClavesSeSigueLeyendo() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "nombre": "Media maratón",
          "fechaAdopcion": 0,
          "semanas": [{
            "id": "\(UUID().uuidString)", "numero": 1,
            "programados": [{
              "id": "\(UUID().uuidString)",
              "resolucion": "pendiente",
              "definicion": {
                "id": "\(UUID().uuidString)",
                "tipo": "largo",
                "nombre": "Tirada larga",
                "descripcion": "La sesión que construye tu resistencia. Ritmo conversable de principio a fin.",
                "segmentos": [{
                  "id": "\(UUID().uuidString)",
                  "nombre": "Larga cómoda",
                  "distanciaKm": 16
                }]
              }
            }]
          }]
        }
        """
        let plan = try JSONDecoder().decode(PlanUsuario.self, from: Data(json.utf8))
        let definicion = try XCTUnwrap(plan.semanas.first?.programados.first?.definicion)

        // Sin clave: el texto sale de la tabla de rescate, no del disco.
        XCTAssertNil(definicion.clave)
        XCTAssertNil(plan.clave)
        XCTAssertEqual(definicion.nombre, ClaveEntrenamiento.tiradaLarga.nombre)
        XCTAssertEqual(definicion.descripcion, ClaveEntrenamiento.tiradaLarga.descripcion)
        XCTAssertEqual(definicion.segmentos.first?.nombre, ClaveSegmento.largaComoda.nombre)
        XCTAssertEqual(plan.nombre, ClavePlan.mediaMaraton.nombre)
    }

    /// La clave se guarda ADEMÁS del texto, nunca en su lugar: una build
    /// vieja leyendo un plan nuevo encuentra el string donde siempre.
    func testElJSONSigueTrayendoElTextoParaLasBuildsViejas() throws {
        let base = try XCTUnwrap(BibliotecaArquetipos.v1()
            .first { $0.clave == .mediaMaraton }?.contenido)
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 17),
                                fechaAdopcion: Date())
        let datos = try JSONEncoder().encode(plan)
        let crudo = try XCTUnwrap(try JSONSerialization.jsonObject(with: datos) as? [String: Any])

        XCTAssertEqual(crudo["nombre"] as? String, ClavePlan.mediaMaraton.nombreCanonico)
        XCTAssertEqual(crudo["clave"] as? String, ClavePlan.mediaMaraton.rawValue)

        let semanas = try XCTUnwrap(crudo["semanas"] as? [[String: Any]])
        let programados = try XCTUnwrap(semanas.first?["programados"] as? [[String: Any]])
        let definicion = try XCTUnwrap(programados.first?["definicion"] as? [String: Any])
        XCTAssertNotNil(definicion["nombre"] as? String, "el texto tiene que seguir estando")
        XCTAssertNotNil(definicion["descripcion"] as? String)
        XCTAssertNotNil(definicion["clave"] as? String, "y la clave al lado")
    }

    /// Ida y vuelta por disco: la clave sobrevive.
    func testLaClaveSobreviveElRoundTrip() throws {
        let base = try XCTUnwrap(BibliotecaArquetipos.v1()
            .first { $0.clave == .maraton }?.contenido)
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 17),
                                fechaAdopcion: Date())
        let ida = try JSONEncoder().encode(plan)
        let vuelta = try JSONDecoder().decode(PlanUsuario.self, from: ida)
        XCTAssertEqual(vuelta, plan)
        XCTAssertEqual(vuelta.clave, .maraton)
        let claves = vuelta.semanas.flatMap(\.programados).compactMap(\.definicion.clave)
        XCTAssertEqual(claves.count, vuelta.semanas.flatMap(\.programados).count)
    }

    /// Una clave que esta build NO conoce (la escribió una versión
    /// futura) no puede tirar el almacén entero: se ignora y queda el
    /// texto guardado.
    func testUnaClaveDesconocidaNoRompeLaDecodificacion() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "tipo": "largo",
          "clave": "sesionDelFuturo:9",
          "nombre": "Tirada larga",
          "descripcion": "La sesión que construye tu resistencia. Ritmo conversable de principio a fin.",
          "segmentos": [{
            "id": "\(UUID().uuidString)",
            "clave": "tramoDelFuturo",
            "nombre": "Larga cómoda",
            "distanciaKm": 16
          }]
        }
        """
        let definicion = try JSONDecoder().decode(DefinicionEntrenamiento.self,
                                                  from: Data(json.utf8))
        XCTAssertNil(definicion.clave, "la clave desconocida se ignora")
        XCTAssertEqual(definicion.nombre, ClaveEntrenamiento.tiradaLarga.nombre,
                       "y el texto guardado sigue resolviendo por tabla")
        XCTAssertNil(definicion.segmentos.first?.clave)
        XCTAssertEqual(definicion.segmentos.first?.nombre, ClaveSegmento.largaComoda.nombre)
    }

    /// Lo que escribió el CORREDOR no se toca: no es contenido de
    /// Maratonia y no hay nada que traducir.
    func testLoQueEscribeElCorredorSeMuestraTalCual() {
        let propio = DefinicionEntrenamiento(
            tipo: .personalizado, nombre: "Mi sesión del jueves",
            descripcion: "Con Ana en el parque",
            segmentos: [Segmento(nombre: "Vueltas al lago", distanciaKm: 3)])
        XCTAssertNil(propio.clave)
        XCTAssertEqual(propio.nombre, "Mi sesión del jueves")
        XCTAssertEqual(propio.descripcion, "Con Ana en el parque")
        XCTAssertEqual(propio.segmentos.first?.nombre, "Vueltas al lago")
    }

    /// Renombrar a mano ABANDONA la clave: si el corredor le puso otro
    /// nombre, ese nombre manda y no puede volver a aparecer el del
    /// catálogo traducido encima.
    func testRenombrarAManoAbandonaLaClave() {
        var definicion = DefinicionEntrenamiento(
            tipo: .largo, clave: .tiradaLarga,
            nombre: ClaveEntrenamiento.tiradaLarga.nombreCanonico)
        XCTAssertEqual(definicion.nombre, ClaveEntrenamiento.tiradaLarga.nombre)
        definicion.nombre = "La larga del domingo"
        XCTAssertNil(definicion.clave)
        XCTAssertEqual(definicion.nombre, "La larga del domingo")
    }

    /// Los tramos numerados del contenido viejo ("Intervalo 3") se
    /// reconocen por forma: no entran en una tabla fija.
    func testLosTramosNumeradosViejosSeReconocen() {
        XCTAssertEqual(TextosLegado.segmento("Intervalo 3"),
                       ClaveSegmento.intervalo(numero: 3).nombre)
        XCTAssertEqual(TextosLegado.segmento("Cambio de ritmo 2"),
                       ClaveSegmento.cambioDeRitmo(numero: 2).nombre)
        XCTAssertEqual(TextosLegado.segmento("Intervalo de Ana"), "Intervalo de Ana",
                       "lo que no es del catálogo no se toca")
    }

    /// El token es la forma persistida: si cambia, los planes guardados
    /// dejan de resolver. Se fija acá a propósito.
    func testLosTokensSonEstables() {
        XCTAssertEqual(ClaveEntrenamiento.umbral(minutos: 32).token, "umbral:32")
        XCTAssertEqual(ClaveEntrenamiento.series(repeticiones: 6, minutos: 3).token, "series:6:3")
        XCTAssertEqual(ClaveEntrenamiento.ritmoObjetivo(distancia: .media, km: 8).token,
                       "ritmoObjetivo:media:8")
        XCTAssertEqual(ClaveEntrenamiento.carrera(distancia: .maraton).token, "carrera:maraton")
        XCTAssertEqual(ClaveSegmento.intervalo(numero: 4).token, "intervalo:4")

        // Y vuelven a leerse.
        for token in ["umbral:32", "series:6:3", "ritmoObjetivo:media:8",
                      "carrera:maraton", "rodajeSuave", "tiradaLargaConFinal"] {
            XCTAssertNotNil(ClaveEntrenamiento(token: token), token)
        }
    }
}

// MARK: - Unidades
//
// La regla que protegen: el almacenamiento y el motor siguen SIEMPRE en
// unidades canónicas (metros, seg/km, kg, cm). La preferencia solo
// cambia presentación, input y voz. Cambiar de km a millas no toca el
// plan ni el disco.

final class UnidadesTests: XCTestCase {

    // ---- Conversión

    func testKilometrosAMillas() {
        XCTAssertEqual(Unidades.distanciaMostrable(km: 42.195, sistema: .imperial),
                       26.2187, accuracy: 0.001)
        XCTAssertEqual(Unidades.distanciaMostrable(km: 5, sistema: .imperial),
                       3.1069, accuracy: 0.001)
        // En métrico no se toca nada: el canónico YA es km.
        XCTAssertEqual(Unidades.distanciaMostrable(km: 42.195, sistema: .metrico), 42.195)
    }

    func testLaVueltaDeDistanciaNoPierdeNada() {
        for km in [1.0, 5.0, 10.0, 21.0975, 42.195] {
            for sistema in SistemaUnidades.allCases {
                let ida = Unidades.distanciaMostrable(km: km, sistema: sistema)
                XCTAssertEqual(Unidades.kmDesde(ida, sistema: sistema), km, accuracy: 0.0001,
                               "\(km) km en \(sistema.rawValue)")
            }
        }
    }

    /// Un ritmo es tiempo POR distancia: al pasar a millas el número
    /// SUBE (la milla es más larga). Invertirlo es el error clásico.
    func testRitmoPorKmAPorMilla() {
        // 5:00 /km = 300 s/km → 8:03 /mi (482,8 s/mi).
        XCTAssertEqual(Unidades.ritmoMostrable(segundosPorKm: 300, sistema: .imperial), 483)
        XCTAssertEqual(Unidades.ritmo(segundosPorKm: 300, sistema: .imperial), "8:03 /mi")
        XCTAssertEqual(Unidades.ritmo(segundosPorKm: 300, sistema: .metrico), "5:00 /km")
        XCTAssertGreaterThan(Unidades.ritmoMostrable(segundosPorKm: 300, sistema: .imperial), 300)
    }

    func testLaVueltaDeRitmoNoPierdeNada() {
        for segKm in [180, 240, 300, 360, 420] {
            let porMilla = Unidades.ritmoMostrable(segundosPorKm: segKm, sistema: .imperial)
            XCTAssertEqual(Unidades.ritmoCanonico(segundosPorUnidad: porMilla, sistema: .imperial),
                           segKm, accuracy: 1, "\(segKm) s/km")
        }
    }

    func testKilosALibras() {
        XCTAssertEqual(Unidades.pesoMostrable(kg: 70, sistema: .imperial), 154.32, accuracy: 0.01)
        XCTAssertEqual(Unidades.pesoMostrable(kg: 70, sistema: .metrico), 70)
        XCTAssertEqual(Unidades.peso(kg: 70, sistema: .imperial), "154 lb")
        XCTAssertEqual(Unidades.peso(kg: 70, sistema: .metrico), "70 kg")
        XCTAssertEqual(Unidades.kgDesde(154.324, sistema: .imperial), 70, accuracy: 0.01)
    }

    func testCentimetrosAPiesYPulgadas() {
        let (pies, pulgadas) = Unidades.alturaImperial(cm: 178)
        XCTAssertEqual(pies, 5)
        XCTAssertEqual(pulgadas, 10)
        XCTAssertEqual(Unidades.altura(cm: 178, sistema: .imperial), "5′10″")
        XCTAssertEqual(Unidades.altura(cm: 178, sistema: .metrico), "178 cm")
        XCTAssertEqual(Unidades.cmDesde(pies: 5, pulgadas: 10), 177.8, accuracy: 0.01)
    }

    /// 12 pulgadas son un pie: 182,9 cm es 6′0″, nunca 5′12″.
    func testLasPulgadasNuncaLleganADoce() {
        for cm in stride(from: 140.0, through: 210.0, by: 0.5) {
            let (_, pulgadas) = Unidades.alturaImperial(cm: cm)
            XCTAssertLessThan(pulgadas, 12, "\(cm) cm dio \(pulgadas)″")
            XCTAssertGreaterThanOrEqual(pulgadas, 0)
        }
        XCTAssertEqual(Unidades.altura(cm: 182.9, sistema: .imperial), "6′0″")
    }

    // ---- Presentación

    func testElFormatoLlevaLaUnidadCorrecta() {
        XCTAssertEqual(Unidades.distancia(km: 7, sistema: .metrico), "7 km")
        XCTAssertEqual(Unidades.distancia(km: 7, sistema: .imperial), "4.3 mi")
        XCTAssertEqual(Unidades.distancia(km: 7, conUnidad: false, sistema: .metrico), "7")
        // El "/sem" se traduce ("/wk" en inglés) y el host de tests
        // corre en el idioma del simulador: lo que se afirma acá es el
        // NÚMERO y la UNIDAD, que es lo que depende del sistema.
        XCTAssertTrue(Unidades.volumenSemanal(km: 43, sistema: .metrico).hasPrefix("43 km/"))
        XCTAssertTrue(Unidades.volumenSemanal(km: 43, sistema: .imperial).hasPrefix("27 mi/"))
        XCTAssertEqual(Unidades.rangoDeRitmo(300, 320, sistema: .metrico), "5:00–5:20 /km")
        XCTAssertEqual(Unidades.rangoDeRitmo(300, 320, sistema: .imperial), "8:03–8:35 /mi")
    }

    // ---- Voz

    func testLaVozTambienRespetaLasUnidades() {
        // El nombre del hito se traduce; lo que importa es que el
        // NÚMERO viaje y que métrico e imperial no digan lo mismo.
        let metrico = Unidades.hitoHablado(numero: 5, sistema: .metrico)
        let imperial = Unidades.hitoHablado(numero: 5, sistema: .imperial)
        XCTAssertTrue(metrico.hasSuffix("5"), metrico)
        XCTAssertTrue(imperial.hasSuffix("5"), imperial)
        XCTAssertNotEqual(metrico, imperial, "un kilómetro no es una milla")
        // El ritmo hablado va sin "/mi": nadie dice "barra milla".
        XCTAssertEqual(Unidades.ritmoHablado(segundosPorKm: 300, sistema: .metrico), "5 00")
        XCTAssertEqual(Unidades.ritmoHablado(segundosPorKm: 300, sistema: .imperial), "8 03")
    }

    /// Los hitos de distancia (splits y avisos por voz) son POR UNIDAD:
    /// en imperial la milla mide 1609 m, no un kilómetro con otro nombre.
    func testElHitoDeDistanciaEsLaUnidadReal() {
        XCTAssertEqual(Unidades.metrosPorHito(sistema: .metrico), 1000)
        XCTAssertEqual(Unidades.metrosPorHito(sistema: .imperial), 1609.344, accuracy: 0.001)
    }

    /// Los splits se recalculan por unidad, no se reetiquetan: 10 km a
    /// ritmo constante son 10 splits en métrico y 6 en imperial.
    func testLosSplitsSeRecalculanPorUnidad() {
        // Un punto cada 100 m a 5:00/km (30 s cada 100 m).
        let puntos = (0...100).map {
            AnalisisSesion.Punto(t: Double($0) * 30, d: Double($0) * 100, alt: 0)
        }
        let metrico = AnalisisSesion.splits(puntos, metrosPorHito: 1000)
        let imperial = AnalisisSesion.splits(puntos, metrosPorHito: 1609.344)
        XCTAssertEqual(metrico.count, 10)
        XCTAssertEqual(imperial.count, 6)
        // El ritmo se guarda SIEMPRE en seg/km canónicos: el mismo
        // esfuerzo da el mismo número en las dos listas.
        XCTAssertEqual(metrico.first?.ritmoSegKm ?? 0, 300, accuracy: 2)
        XCTAssertEqual(imperial.first?.ritmoSegKm ?? 0, 300, accuracy: 2)
        XCTAssertEqual(imperial.last?.numero, 6)
    }

    // ---- Default por región y retrocompatibilidad

    func testElDefaultSaleDeLaRegion() {
        XCTAssertEqual(SistemaUnidades.segunRegion(Locale(identifier: "es_AR")), .metrico)
        XCTAssertEqual(SistemaUnidades.segunRegion(Locale(identifier: "en_US")), .imperial)
        XCTAssertEqual(SistemaUnidades.segunRegion(Locale(identifier: "en_GB")), .imperial)
        XCTAssertEqual(SistemaUnidades.segunRegion(Locale(identifier: "es_ES")), .metrico)
    }

    /// Un usuario existente NO tiene preferencia guardada: recibe el
    /// default por región, sin migración ni escritura.
    func testUsuarioSinPreferenciaRecibeElDefaultDeSuRegion() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.unidades.\(UUID().uuidString)"))
        let preferencia = PreferenciaUnidades(defaults: defaults,
                                              locale: Locale(identifier: "en_US"))
        XCTAssertEqual(preferencia.sistema, .imperial)
        XCTAssertFalse(preferencia.elegidaPorElCorredor,
                       "no eligió: el onboarding tiene que preguntar")
        XCTAssertNil(defaults.string(forKey: "maratonia.sistemaUnidades"),
                     "un default inferido NO se escribe: eso lo haría indistinguible de una elección")

        // Un perfil viejo tampoco la trae: se mantiene el default.
        let perfil = PerfilDeportivo()
        XCTAssertNil(perfil.sistemaUnidades)
        preferencia.adoptarDelPerfil(perfil.sistemaUnidades)
        XCTAssertEqual(preferencia.sistema, .imperial)
        XCTAssertFalse(preferencia.elegidaPorElCorredor)
    }

    func testElegirLaGuardaYLaMarcaComoElegida() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.unidades.\(UUID().uuidString)"))
        let preferencia = PreferenciaUnidades(defaults: defaults,
                                              locale: Locale(identifier: "es_AR"))
        XCTAssertEqual(preferencia.sistema, .metrico)
        preferencia.elegir(.imperial)
        XCTAssertEqual(preferencia.sistema, .imperial)
        XCTAssertTrue(preferencia.elegidaPorElCorredor)

        // Y sobrevive al reinicio del proceso.
        let despues = PreferenciaUnidades(defaults: defaults, locale: Locale(identifier: "es_AR"))
        XCTAssertEqual(despues.sistema, .imperial)
        XCTAssertTrue(despues.elegidaPorElCorredor)
    }

    // ---- Con un plan ya adoptado

    /// Cambiar de unidades NO regenera el plan ni reescribe el disco: el
    /// snapshot es idéntico byte a byte y solo cambia lo que se muestra.
    func testCambiarUnidadesNoTocaElPlanAdoptado() throws {
        let base = try XCTUnwrap(BibliotecaArquetipos.v1()
            .first { $0.clave == .mediaMaraton }?.contenido)
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 17),
                                fechaAdopcion: Date(timeIntervalSince1970: 0))
        let antes = try JSONEncoder().encode(plan)

        let definicion = try XCTUnwrap(plan.semanas.first?.programados.first?.definicion)
        let km = try XCTUnwrap(definicion.distanciaPrescritaKm)
        let enMetrico = Unidades.distancia(km: km, sistema: .metrico)
        let enImperial = Unidades.distancia(km: km, sistema: .imperial)
        XCTAssertNotEqual(enMetrico, enImperial, "la presentación sí cambia")
        XCTAssertTrue(enImperial.hasSuffix("mi"))

        // El dominio, intacto: mismos km guardados y mismo plan al
        // releerlo. Se compara el VALOR y no los bytes porque el encoder
        // no garantiza un orden estable para los diccionarios de dentro.
        XCTAssertEqual(definicion.distanciaPrescritaKm, km)
        XCTAssertEqual(try JSONDecoder().decode(PlanUsuario.self, from: antes), plan,
                       "cambiar de unidades no puede reescribir el plan")
    }

    /// La preferencia viaja al reloj con la proyección, que ya se
    /// reenvía ante cada cambio.
    func testLaProyeccionLlevaLasUnidadesAlReloj() throws {
        var perfil = PerfilDeportivo()
        perfil.sistemaUnidades = .imperial
        let datos = try JSONEncoder().encode(perfil)
        let releido = try JSONDecoder().decode(PerfilDeportivo.self, from: datos)
        XCTAssertEqual(releido.sistemaUnidades, .imperial)

        var proyeccion = ProyeccionDia(generadaEl: Date(), dia: DiaLocal(anio: 2026, mes: 8, dia: 17))
        proyeccion.sistemaUnidades = .imperial
        let ida = try JSONEncoder().encode(proyeccion)
        let vuelta = try JSONDecoder().decode(ProyeccionDia.self, from: ida)
        XCTAssertEqual(vuelta.sistemaUnidades, .imperial)
        XCTAssertEqual(vuelta.version, ProyeccionDia.versionActual,
                       "agregar el campo no sube la versión: un receptor viejo lo ignora")
    }

    /// Una proyección de una build ANTERIOR no trae unidades: el reloj
    /// no puede pisar la preferencia con un vacío.
    func testUnaProyeccionViejaNoBorraLasUnidadesDelReloj() throws {
        let json = """
        {"version":1,"generadaEl":0,"dia":{"anio":2026,"mes":8,"dia":17}}
        """
        let vieja = try JSONDecoder().decode(ProyeccionDia.self, from: Data(json.utf8))
        XCTAssertNil(vieja.sistemaUnidades)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.unidades.\(UUID().uuidString)"))
        let preferencia = PreferenciaUnidades(defaults: defaults,
                                              locale: Locale(identifier: "es_AR"))
        preferencia.elegir(.imperial)
        preferencia.adoptarDelPerfil(vieja.sistemaUnidades)
        XCTAssertEqual(preferencia.sistema, .imperial, "un nil no puede pisar lo elegido")
    }

    // ---- Idioma × unidades

    /// Las dos preferencias son independientes: el idioma cambia las
    /// palabras y las unidades cambian los números, y ninguna pisa a la
    /// otra.
    func testIdiomaYUnidadesSonIndependientes() {
        let clave = ClaveEntrenamiento.tiradaLarga
        // El título viene del catálogo (idioma) y no lleva unidades.
        XCTAssertFalse(clave.nombre.contains("km"))
        XCTAssertFalse(clave.nombre.contains("mi"))

        // Y una sesión con distancia se muestra en la unidad elegida sin
        // que el idioma la toque.
        for sistema in SistemaUnidades.allCases {
            let texto = Unidades.distancia(km: 16, sistema: sistema)
            XCTAssertTrue(texto.hasSuffix(sistema.etiquetaDistancia), texto)
        }
        // El nombre de un bloque a ritmo objetivo SÍ lleva la distancia:
        // se convierte, pero el CANÓNICO —lo que se congela— sigue en km.
        let bloque = ClaveEntrenamiento.ritmoObjetivo(distancia: .media, km: 8)
        XCTAssertTrue(bloque.nombreCanonico.contains("8 km"))
    }
}
