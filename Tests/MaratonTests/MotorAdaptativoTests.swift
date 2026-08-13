import XCTest
@testable import Maraton

// Tests del MOTOR ADAPTATIVO: perfil, historial, elegibilidad,
// detección de eventos, validación y aplicación de adaptaciones.
//
// Todo lo que se testea acá es PURO: no toca HealthKit, ni red, ni
// disco. Ese es el punto — el cerebro deportivo tiene que ser
// verificable sin dispositivo.

private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 12)   // miércoles
/// El mismo instante que `hoy`, para que los tests de ventanas y los
/// de dominio hablen del mismo día.
private let ahora = Date(timeIntervalSince1970: 1_786_536_000)   // 2026-08-12 12:00 UTC

private func sesion(_ diasAtras: Int, km: Double, minutos: Double = 0) -> SesionMetrica {
    SesionMetrica(fecha: ahora.addingTimeInterval(-Double(diasAtras) * 86_400),
                  metros: km * 1000,
                  segundos: minutos > 0 ? minutos * 60 : km * 6 * 60)
}

// MARK: - Ventanas de historial (§5)

final class ResumenHistorialTests: XCTestCase {

    func testVentanaVaciaNoInventaNada() {
        let v = ResumenHistorial.ventana([], dias: 28, hoy: ahora)
        XCTAssertTrue(v.estaVacia)
        XCTAssertEqual(v.km, 0)
        XCTAssertEqual(v.salidas, 0)
        // Sin correr en 28 días, la pausa ES de 28 días.
        XCTAssertEqual(v.mayorPausaDias, 28)
    }

    func testSumaSoloLoQueCaeEnLaVentana() {
        let sesiones = [sesion(1, km: 10), sesion(5, km: 8), sesion(40, km: 30)]
        let v = ResumenHistorial.ventana(sesiones, dias: 7, hoy: ahora)
        XCTAssertEqual(v.salidas, 2)
        XCTAssertEqual(v.km, 18, accuracy: 0.01)
        XCTAssertEqual(v.tiradaMasLargaKm, 10, accuracy: 0.01)
    }

    func testKmPorSemanaEscalaConLaVentana() {
        // 40 km en 28 días = 10 km/semana.
        let sesiones = (1...4).map { sesion($0 * 6, km: 10) }
        let v = ResumenHistorial.ventana(sesiones, dias: 28, hoy: ahora)
        XCTAssertEqual(v.kmPorSemana, 10, accuracy: 0.5)
    }

    func testMayorPausaCuentaLaColaHastaHoy() {
        // Corrió mucho hace 30 días y nada desde entonces.
        let sesiones = [sesion(30, km: 10), sesion(32, km: 10)]
        let v = ResumenHistorial.ventana(sesiones, dias: 42, hoy: ahora)
        XCTAssertGreaterThanOrEqual(v.mayorPausaDias, 29,
                                    "dejar de correr hace un mes ES la pausa relevante")
    }

    func testDiasConCarreraNoCuentaDosVecesElMismoDia() {
        let dia = ahora.addingTimeInterval(-86_400)
        let sesiones = [
            SesionMetrica(fecha: dia, metros: 5000, segundos: 1800),
            SesionMetrica(fecha: dia.addingTimeInterval(3600), metros: 5000, segundos: 1800),
        ]
        let v = ResumenHistorial.ventana(sesiones, dias: 7, hoy: ahora)
        XCTAssertEqual(v.salidas, 2)
        XCTAssertEqual(v.diasConCarrera, 1)
    }

    func testDescartaSesionesSinDistancia() {
        let v = ResumenHistorial.ventana([
            SesionMetrica(fecha: ahora.addingTimeInterval(-3600), metros: 0, segundos: 600),
        ], dias: 7, hoy: ahora)
        XCTAssertTrue(v.estaVacia)
    }

    func testLasTresVentanasEstandar() {
        let v = ResumenHistorial.ventanas([sesion(1, km: 10)], hoy: ahora)
        XCTAssertEqual(Set(v.keys), Set([7, 28, 42]))
        XCTAssertEqual(v[7]?.km ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(v[42]?.km ?? 0, 10, accuracy: 0.01)
    }

    func testFondosSonRelativosAlPropioCorredor() {
        // Mediana 5 km; la de 12 km supera 1.5× → es un fondo.
        let sesiones = [sesion(1, km: 5), sesion(3, km: 5), sesion(5, km: 12)]
        let v = ResumenHistorial.ventana(sesiones, dias: 28, hoy: ahora)
        XCTAssertEqual(v.fondos, 1)
    }
}

// MARK: - Detección de actividad desde Salud (§4)

final class DeteccionActividadTests: XCTestCase {

    func testSinDatosDevuelveNilYNoAsumeSedentarismo() {
        XCTAssertNil(DeteccionActividad.detectar([], hoy: ahora))
    }

    func testPocasSalidasNoAlcanzan() {
        // 3 salidas: por debajo del mínimo. No es una rutina.
        let sesiones = [sesion(2, km: 5), sesion(9, km: 5), sesion(16, km: 5)]
        XCTAssertNil(DeteccionActividad.detectar(sesiones, hoy: ahora))
    }

    func testSalidasConcentradasEnUnaSemanaNoAlcanzan() {
        // 5 salidas pero todas en 4 días: no hay repartición semanal.
        let sesiones = (1...5).map { sesion($0, km: 5) }
        XCTAssertNil(DeteccionActividad.detectar(sesiones, hoy: ahora),
                     "cinco salidas en una semana no describen una rutina de seis")
    }

    func testDetectaConRutinaReal() {
        // 3 por semana durante 4 semanas.
        var sesiones: [SesionMetrica] = []
        for semana in 0..<4 {
            for dia in [1, 3, 5] {
                sesiones.append(sesion(semana * 7 + dia, km: 7))
            }
        }
        let detectada = DeteccionActividad.detectar(sesiones, hoy: ahora)
        XCTAssertNotNil(detectada)
        XCTAssertEqual(detectada?.salidasConsideradas, 12)
        XCTAssertEqual(detectada?.kmSemanales ?? 0, 14, accuracy: 1.5)
    }

    func testConvertirseEnActividadMarcaElOrigen() {
        let detectada = ActividadDetectada(diasPorSemana: 3.2, kmSemanales: 21.77,
                                           minutosSemanales: 130, tiradaLargaKm: 10.44,
                                           salidasConsideradas: 12, diasVentana: 42)
        let actividad = detectada.comoActividad(origen: .confirmado, fecha: ahora)
        XCTAssertEqual(actividad.origen, .confirmado)
        XCTAssertEqual(actividad.kmSemanales ?? 0, 21.8, accuracy: 0.01)
        XCTAssertEqual(actividad.tiradaLargaKm ?? 0, 10.4, accuracy: 0.01)
    }
}

// MARK: - Elegibilidad (§12)

final class ElegibilidadTests: XCTestCase {

    private func entrada(_ objetivo: ObjetivoDeportivo,
                         km: Double? = nil, larga: Double? = nil,
                         dias: Int = 5, semanas: Int? = nil,
                         meses: Int? = nil, baseline: Bool = true,
                         molestias: EstadoMolestias = .ninguna,
                         pausa: Bool = false) -> EntradaElegibilidad {
        EntradaElegibilidad(
            objetivo: objetivo,
            semanasDisponibles: semanas,
            semanasMinimasDelPlan: 12,
            diasElegidos: dias,
            historial: nil,
            actividadDeclarada: ActividadActual(
                diasPorSemana: Double(dias), kmSemanales: km,
                tiradaLargaKm: larga, mesesCorriendoRegular: meses),
            tieneBaseline: baseline,
            molestias: molestias,
            mesesCorriendoRegular: meses,
            volviendoDePausa: pausa)
    }

    // ---- Bloqueos duros: van primero y no son opinables.

    func testFechaImposibleGanaSobreTodoLoDemas() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 100, larga: 32, semanas: 3, meses: 24))
        XCTAssertEqual(v, .fechaDemasiadoCerca(semanasDisponibles: 3, semanasMinimas: 12))
        XCTAssertFalse(v.generaPlan)
    }

    func testFrecuenciaInsuficienteBloquea() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maratonRendimiento, km: 100, larga: 34, dias: 3, meses: 24))
        XCTAssertEqual(v, .frecuenciaInsuficiente(diasElegidos: 3, minimo: 5))
    }

    // ---- Primeros 5K: la fase base ES el plan, no exige nada.

    func testPrimeros5KDesdeCeroEsElegible() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.primeros5K, dias: 2, baseline: false))
        XCTAssertEqual(v, .elegible)
    }

    func testPrimeros5KNuncaPideFaseBase() {
        // Ni con cero de todo: no hay nada más abajo a donde mandarlo.
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.primeros5K, km: 0, larga: 0, dias: 2, baseline: false))
        XCTAssertTrue(v.generaPlan)
        XCTAssertNil(EvaluadorElegibilidad.objetivoPuente(para: .primeros5K))
    }

    // ---- Volumen.

    func testMaratonConBaseSolidaEsElegible() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 70, larga: 22, dias: 4, meses: 12))
        XCTAssertEqual(v, .elegible)
    }

    func testMaratonConVolumenJustoPorDebajoEsConservador() {
        // Requisito de "primera maratón" tras la recalibración: 40
        // km/sem y una larga de 12 km, anclados a lo que el propio plan
        // pide en su primera semana (antes eran 63 km por una fórmula
        // lineal que superaba el pico del plan que habilitaba).
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 30, larga: 14, dias: 4, meses: 12))
        XCTAssertTrue(v.esConservador)
        XCTAssertTrue(v.motivos.contains(.volumenBajo))
        XCTAssertTrue(v.generaPlan, "conservador todavía genera plan")
    }

    func testMaratonConRequisitoJustoEsElegible() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 42, larga: 13, dias: 4, meses: 12))
        XCTAssertEqual(v, .elegible)
    }

    func testMaratonConVolumenMuyPorDebajoPideBase() {
        // Por debajo del 40 % del requisito → falta base de verdad.
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 12, larga: 4, dias: 4, meses: 12))
        if case .requiereFaseBase(let motivos) = v {
            XCTAssertTrue(motivos.contains(.volumenBajo))
        } else {
            XCTFail("esperaba requiereFaseBase, vino \(v)")
        }
    }

    func testElPuenteSiempreVaHaciaAbajo() {
        XCTAssertEqual(EvaluadorElegibilidad.objetivoPuente(para: .maraton), .mediaMaraton)
        XCTAssertEqual(EvaluadorElegibilidad.objetivoPuente(para: .maratonRendimiento), .maraton)
        XCTAssertEqual(EvaluadorElegibilidad.objetivoPuente(para: .mejorar5K), .primeros5K)
    }

    // ---- Rendimiento: exige base real, sin excepciones.

    func testRendimientoSinBaselineNoSeGenera() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maratonRendimiento, km: 180, larga: 34, dias: 5,
                    meses: 24, baseline: false))
        XCTAssertFalse(v.generaPlan)
        XCTAssertTrue(v.motivos.contains(.sinBaseline))
    }

    func testRendimientoConLesionRecienteNoSeGenera() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.mediaRendimiento, km: 90, larga: 18, dias: 5,
                    meses: 24, molestias: .lesionReciente))
        XCTAssertFalse(v.generaPlan)
    }

    func testRendimientoConTodoEnRegla() {
        // 21.1 · 4 = 84 km/sem, larga 0.8 · 21.1 ≈ 17 km.
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.mediaRendimiento, km: 90, larga: 18, dias: 5, meses: 24))
        XCTAssertEqual(v, .elegible)
    }

    // ---- Contexto que baja a conservador pero no bloquea.

    func testMolestiaLeveBajaAConservador() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 70, larga: 22, dias: 4, meses: 12,
                    molestias: .molestiaLeve))
        XCTAssertTrue(v.esConservador)
        XCTAssertTrue(v.motivos.contains(.molestiaDeclarada))
    }

    func testVolverDeUnaPausaBajaAConservador() {
        let v = EvaluadorElegibilidad.evaluar(
            entrada(.maraton, km: 70, larga: 22, dias: 4, meses: 12, pausa: true))
        XCTAssertTrue(v.esConservador)
        XCTAssertTrue(v.motivos.contains(.volviendoDePausa))
    }

    func testSinDatosArrancaConservadorPeroNuncaBloquea() {
        // Ausencia de datos NO es sedentarismo (§4).
        let entrada = EntradaElegibilidad(
            objetivo: .mediaMaraton, semanasDisponibles: nil,
            semanasMinimasDelPlan: 12, diasElegidos: 4,
            historial: nil, actividadDeclarada: nil, tieneBaseline: true,
            molestias: .ninguna, mesesCorriendoRegular: nil, volviendoDePausa: false)
        let v = EvaluadorElegibilidad.evaluar(entrada)
        XCTAssertTrue(v.generaPlan)
        XCTAssertTrue(v.motivos.contains(.sinHistorial))
    }

    func testInactividadRecienteAparaceComoMotivo() {
        var historial = ResumenVentana(dias: 42)
        historial.km = 60; historial.salidas = 6
        historial.tiradaMasLargaKm = 20; historial.mayorPausaDias = 25
        historial.diasConCarrera = 6; historial.semanasConSalida = 3
        historial.semanasEnLaVentana = 6
        let entrada = EntradaElegibilidad(
            objetivo: .mediaMaraton, semanasDisponibles: nil,
            semanasMinimasDelPlan: 12, diasElegidos: 4,
            historial: historial, actividadDeclarada: nil, tieneBaseline: true,
            molestias: .ninguna, mesesCorriendoRegular: 12, volviendoDePausa: false)
        XCTAssertTrue(EvaluadorElegibilidad.evaluar(entrada).motivos
            .contains(.inactividadReciente))
    }

    func testElHistorialMedidoGanaSobreLoDeclarado() {
        // Declara 80 km/semana; Salud dice 12. Manda Salud (§4).
        var historial = ResumenVentana(dias: 42)
        historial.km = 72; historial.salidas = 18
        historial.tiradaMasLargaKm = 6; historial.diasConCarrera = 18
        historial.semanasConSalida = 6; historial.semanasEnLaVentana = 6
        let entrada = EntradaElegibilidad(
            objetivo: .maraton, semanasDisponibles: nil, semanasMinimasDelPlan: 12,
            diasElegidos: 4, historial: historial,
            actividadDeclarada: ActividadActual(kmSemanales: 80, tiradaLargaKm: 30),
            tieneBaseline: true, molestias: .ninguna,
            mesesCorriendoRegular: 12, volviendoDePausa: false)
        XCTAssertEqual(entrada.kmSemanales ?? 0, 12, accuracy: 0.5)
        XCTAssertFalse(EvaluadorElegibilidad.evaluar(entrada).motivos.isEmpty)
    }

    // ---- Coherencia entre el evaluador y el catálogo.

    func testCadaObjetivoTieneArquetipoConDiasCoherentes() {
        for objetivo in ObjetivoDeportivo.allCases {
            guard let arq = BibliotecaArquetipos.arquetipo(para: objetivo) else {
                return XCTFail("\(objetivo) sin arquetipo")
            }
            let requisitos = RequisitosObjetivo.para(objetivo)
            XCTAssertEqual(arq.diasMinimos, requisitos.diasPorSemana,
                           "\(objetivo): el arquetipo pide \(arq.diasMinimos) días y " +
                           "la elegibilidad \(requisitos.diasPorSemana) — divergir acá " +
                           "hace que la app te deje elegir y después no genere nada")
            XCTAssertNotNil(arq.contenido, "\(objetivo) sin contenido")
        }
    }

    func testLosDiezObjetivosExistenYSeDescomponen() {
        XCTAssertEqual(ObjetivoDeportivo.allCases.count, 10)
        for objetivo in ObjetivoDeportivo.allCases {
            XCTAssertEqual(ObjetivoDeportivo.combinando(objetivo.distancia,
                                                        objetivo.intencion), objetivo)
        }
        // 5K no tiene variante de rendimiento.
        XCTAssertNil(ObjetivoDeportivo.combinando(.cinco, .rendimiento))
        XCTAssertNotNil(ObjetivoDeportivo.combinando(.maraton, .rendimiento))
    }

    func testLosRawValueHistoricosNoCambiaron() {
        // Si esto se rompe, los perfiles ya guardados dejan de decodificar.
        XCTAssertEqual(ObjetivoDeportivo.primeros5K.rawValue, "primeros5K")
        XCTAssertEqual(ObjetivoDeportivo.mejorar5K.rawValue, "mejorar5K")
        XCTAssertEqual(ObjetivoDeportivo.diez.rawValue, "diez")
        XCTAssertEqual(ObjetivoDeportivo.mediaMaraton.rawValue, "mediaMaraton")
        XCTAssertEqual(ObjetivoDeportivo.maraton.rawValue, "maraton")
    }
}

// MARK: - Helpers de dominio para los tests de adaptación

private func definicion(_ nombre: String, tipo: TipoEntrenamiento,
                        km: Double) -> DefinicionEntrenamiento {
    DefinicionEntrenamiento(tipo: tipo, nombre: nombre,
                            segmentos: [Segmento(nombre: nombre, distanciaKm: km)])
}

private func programado(_ nombre: String, tipo: TipoEntrenamiento, km: Double,
                        dia: DiaLocal) -> EntrenamientoProgramado {
    let rol = RolSesion.para(tipo)
    return EntrenamientoProgramado(definicion: definicion(nombre, tipo: tipo, km: km),
                                   dia: dia, rolGuardado: rol,
                                   adaptabilidadGuardada: .para(rol))
}

/// Una semana REAL en curso: hoy es miércoles, el lunes ya se corrió.
/// Que el lunes esté CUMPLIDO importa: un pendiente con fecha pasada
/// es un "vencido" y el detector lo levantaría como evento, ensuciando
/// todos los tests que quieren mirar otra cosa.
///
/// L 10/8 recuperación 4 km (cumplida) · X 12/8 umbral 8 km (hoy) ·
/// V 14/8 rodaje 7 km · D 16/8 tirada larga 16 km. Total: 35 km.
private func almacenDeSemana(reglas: ReglasSemana? = nil,
                             diasElegidos: [Int] = [1, 3, 5, 7]) -> AlmacenV2 {
    var almacen = AlmacenV2()
    almacen.activado = true
    var perfil = PerfilDeportivo()
    perfil.diasElegidos = diasElegidos
    almacen.perfil = perfil
    var lunes = programado("Recuperación", tipo: .recuperacion, km: 4,
                           dia: DiaLocal(anio: 2026, mes: 8, dia: 10))
    lunes.resolucion = .cumplido
    let semana = SemanaPlan(numero: 1, programados: [
        lunes,
        programado("Umbral", tipo: .umbral, km: 8,
                   dia: DiaLocal(anio: 2026, mes: 8, dia: 12)),   // miércoles (hoy)
        programado("Rodaje", tipo: .facil, km: 7,
                   dia: DiaLocal(anio: 2026, mes: 8, dia: 14)),   // viernes
        programado("Tirada larga", tipo: .largo, km: 16,
                   dia: DiaLocal(anio: 2026, mes: 8, dia: 16)),   // domingo
    ], reglas: reglas)
    almacen.planActivo = PlanUsuario(nombre: "Test", fechaAdopcion: ahora,
                                     semanas: [semana])
    return almacen
}

/// Agrega un pendiente con fecha pasada (un "vencido" de verdad).
private func conVencido(_ almacen: AlmacenV2, dia: Int,
                        nombre: String = "Vencido") -> AlmacenV2 {
    var copia = almacen
    copia.planActivo!.semanas[0].programados.append(
        programado(nombre, tipo: .facil, km: 5,
                   dia: DiaLocal(anio: 2026, mes: 8, dia: dia)))
    return copia
}

private func buscar(_ almacen: AlmacenV2, _ nombre: String) -> EntrenamientoProgramado {
    almacen.todosLosProgramados.first { $0.definicion.nombre == nombre }!
}

// MARK: - Roles, adaptabilidad y plan original (§17, §18, §45)

final class AdaptabilidadTests: XCTestCase {

    func testLaCarreraObjetivoEsIntocable() {
        let contrato = Adaptabilidad.para(.carrera)
        XCTAssertFalse(contrato.sePuedeMover)
        XCTAssertFalse(contrato.sePuedeReducir)
        XCTAssertFalse(contrato.sePuedeConvertirEnFacil)
        XCTAssertFalse(contrato.sePuedeOmitir)
    }

    func testLaLargaSeAcortaPeroNoSeConvierte() {
        let contrato = Adaptabilidad.para(.tiradaLarga)
        XCTAssertTrue(contrato.sePuedeReducir)
        XCTAssertFalse(contrato.sePuedeConvertirEnFacil,
                       "una larga convertida en rodaje fácil ya no es una larga")
        XCTAssertGreaterThan(contrato.recuperacionMinimaDias, 0)
    }

    func testLosRolesSalenDelTipo() {
        XCTAssertEqual(RolSesion.para(.ritmoCarrera), .carrera)
        XCTAssertEqual(RolSesion.para(.largo), .tiradaLarga)
        XCTAssertEqual(RolSesion.para(.umbral), .calidadPrincipal)
        XCTAssertEqual(RolSesion.para(.series), .calidadPrincipal)
        XCTAssertEqual(RolSesion.para(.recuperacion), .recuperacion)
        XCTAssertEqual(RolSesion.para(.facil), .facil)
    }

    func testPrioridadOrdenaDeLoImportanteALoSacrificable() {
        XCTAssertLessThan(RolSesion.carrera, RolSesion.tiradaLarga)
        XCTAssertLessThan(RolSesion.tiradaLarga, RolSesion.calidadPrincipal)
        XCTAssertLessThan(RolSesion.calidadPrincipal, RolSesion.facil)
        XCTAssertLessThan(RolSesion.facil, RolSesion.recuperacion)
    }

    func testReducirCongelaLaPrescripcionOriginal() {
        var almacen = almacenDeSemana()
        let umbral = buscar(almacen, "Umbral")
        XCTAssertFalse(umbral.fueAdaptada)
        XCTAssertTrue(almacen.reducir(programadoID: umbral.id, factor: 0.75))
        let despues = buscar(almacen, "Umbral")
        XCTAssertEqual(despues.definicion.distanciaTotalKm ?? 0, 6, accuracy: 0.01)
        XCTAssertEqual(despues.prescripcionOriginal.distanciaTotalKm ?? 0, 8, accuracy: 0.01)
        XCTAssertTrue(despues.fueAdaptada)
    }

    func testReducirDosVecesNoPisaElOriginal() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        XCTAssertTrue(almacen.reducir(programadoID: id, factor: 0.8))
        XCTAssertTrue(almacen.reducir(programadoID: id, factor: 0.9))
        XCTAssertEqual(buscar(almacen, "Umbral").prescripcionOriginal.distanciaTotalKm ?? 0,
                       8, accuracy: 0.01, "el original sigue siendo el ORIGINAL")
    }

    func testReducirPorDebajoDelPisoSeRechaza() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        // factorMinimo de calidad principal = 0.6
        XCTAssertFalse(almacen.reducir(programadoID: id, factor: 0.3))
        XCTAssertEqual(buscar(almacen, "Umbral").definicion.distanciaTotalKm ?? 0,
                       8, accuracy: 0.01)
    }

    func testReducirConFactorMayorAUnoSeRechaza() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        XCTAssertFalse(almacen.reducir(programadoID: id, factor: 1.3),
                       "adaptar nunca sube carga")
    }

    func testConvertirBajaElRolYMantieneLaDistancia() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        XCTAssertTrue(almacen.convertirEnFacil(programadoID: id))
        let convertido = almacen.todosLosProgramados.first { $0.id == id }!
        XCTAssertEqual(convertido.definicion.tipo, .facil)
        XCTAssertEqual(convertido.rol, .facil)
        XCTAssertEqual(convertido.definicion.distanciaTotalKm ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(convertido.prescripcionOriginal.tipo, .umbral)
        XCTAssertEqual(convertido.definicion.segmentos.count, 1)
    }

    func testNoSeConvierteUnaTiradaLarga() {
        var almacen = almacenDeSemana()
        XCTAssertFalse(almacen.convertirEnFacil(programadoID: buscar(almacen, "Tirada larga").id))
    }

    func testNoSeAdaptaAlgoYaResuelto() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Recuperación").id
        almacen.vincular(sesionID: UUID(), fechaSesion: ahora, aProgramado: id, completo: true)
        XCTAssertFalse(almacen.reducir(programadoID: id, factor: 0.8))
        XCTAssertFalse(almacen.convertirEnFacil(programadoID: id))
    }

    func testLasReglasSemanalesSeDerivanDelContenido() {
        let base = ContenidoPlanes.mediaMaraton()
        let reglas = base.semanas[0].reglasDerivadas
        XCTAssertNotNil(reglas.fase)
        XCTAssertNotNil(reglas.volumenObjetivoKm)
        XCTAssertLessThan(reglas.volumenMinimoKm ?? 0, reglas.volumenObjetivoKm ?? 0)
        XCTAssertGreaterThan(reglas.volumenMaximoKm ?? 0, reglas.volumenObjetivoKm ?? 0)
        XCTAssertNotNil(reglas.propositoFase)
    }
}

// MARK: - Detector de eventos (§34, §35)

final class DetectorEventosTests: XCTestCase {

    private func analisis(km: Double, prescritos: Double?, completa: Bool,
                          sensacion: SensacionEsfuerzo? = nil,
                          molestia: Bool = false,
                          programadoID: UUID? = nil) -> AnalisisPostCarrera {
        AnalisisPostCarrera(sesionID: UUID(), fecha: ahora, km: km, minutos: km * 6,
                            ritmoSegKm: 360, programadoID: programadoID,
                            kmPrescritos: prescritos, estructuraCompleta: completa,
                            sensacion: sensacion, conMolestia: molestia)
    }

    func testUnaCarreraNormalNoGeneraNada() {
        let almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 8, prescritos: 8, completa: true, programadoID: id)))
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos),
                       "la mayoría de las carreras NO deben terminar en un ajuste")
    }

    /// Cambió con la inercia (§17): un "muy exigido" AISLADO ya no es
    /// evento. Los casos con confirmación viven en InerciaAdaptadorTests.
    func testEsfuerzoMuyAltoAisladoYaNoDisparaNada() {
        let almacen = almacenDeSemana()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 8, prescritos: 8, completa: true,
                               sensacion: .muyExigido)))
        XCTAssertFalse(eventos.contains { if case .esfuerzoMuyAlto = $0 { return true }; return false },
                       "hace falta una segunda señal coherente")
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos))
    }

    func testSentirseMuyBienNoGeneraNada() {
        // §40: una buena sesión aislada no habilita nada.
        let almacen = almacenDeSemana()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 8, prescritos: 8, completa: true, sensacion: .muyBien)))
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos))
    }

    func testMolestiaSiempreEsEvento() {
        let almacen = almacenDeSemana()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 8, prescritos: 8, completa: true, molestia: true)))
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testSesionParcialSeDetecta() {
        let almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 4, prescritos: 8, completa: false, programadoID: id)))
        XCTAssertTrue(eventos.contains { if case .sesionParcial = $0 { return true }; return false })
    }

    func testFondoParcialEsMasGraveQueUnaParcialCualquiera() {
        let almacen = almacenDeSemana()
        let id = buscar(almacen, "Tirada larga").id
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 6, prescritos: 16, completa: false, programadoID: id)))
        XCTAssertTrue(eventos.contains { if case .fondoComprometido = $0 { return true }; return false })
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testUnaSolaAusenciaEsSesionPerdidaYNoAmeritaIA() {
        let almacen = conVencido(almacenDeSemana(), dia: 11)
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoy, almacen: almacen))
        XCTAssertTrue(eventos.contains { if case .sesionPerdida = $0 { return true }; return false })
        XCTAssertFalse(eventos.contains { if case .variasAusencias = $0 { return true }; return false })
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos),
                       "perder un rodaje suelto se registra, no reescribe la semana")
    }

    func testVariasAusenciasSeDetectan() {
        // Dos pendientes con fecha pasada: eso ya es un patrón.
        let almacen = conVencido(conVencido(almacenDeSemana(), dia: 11, nombre: "V1"),
                                 dia: 9, nombre: "V2")
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoy, almacen: almacen))
        XCTAssertTrue(eventos.contains { if case .variasAusencias = $0 { return true }; return false })
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testOmitirTambienCuentaComoAusencia() {
        var almacen = almacenDeSemana()
        var omitido = programado("Omitido", tipo: .facil, km: 5,
                                 dia: DiaLocal(anio: 2026, mes: 8, dia: 11))
        omitido.resolucion = .omitido
        almacen.planActivo!.semanas[0].programados.append(omitido)
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoy, almacen: almacen))
        XCTAssertTrue(eventos.contains { if case .sesionPerdida = $0 { return true }; return false })
    }

    func testCarreraLibreChicaNoMueveNada() {
        // §42: una carrera libre solo importa si mueve la aguja.
        let almacen = almacenDeSemana()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 3, prescritos: nil, completa: false)))
        XCTAssertFalse(eventos.contains {
            if case .carreraLibreSignificativa = $0 { return true }; return false })
    }

    func testCarreraLibreGrandeSiImporta() {
        let almacen = almacenDeSemana()   // 35 km prescritos en la semana
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen,
            analisis: analisis(km: 20, prescritos: nil, completa: false)))
        XCTAssertTrue(eventos.contains {
            if case .carreraLibreSignificativa = $0 { return true }; return false })
    }

    func testPedidoDelUsuarioSiempreLlamaALaIA() {
        let almacen = almacenDeSemana()
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen, analisis: nil, kmSemanaActual: nil,
            pedidoExplicito: true))
        XCTAssertTrue(DetectorEventos.ameritaIA(eventos))
    }

    func testCercaDeLaCarreraEsContextoNoAlarma() {
        var almacen = almacenDeSemana()
        var perfil = almacen.perfilDeportivo
        perfil.fechaObjetivo = DiaLocal(anio: 2026, mes: 8, dia: 20)
        almacen.perfil = perfil
        let eventos = DetectorEventos.detectar(EntradaDeteccion(hoy: hoy, almacen: almacen))
        XCTAssertTrue(eventos.contains { if case .cercaDeLaCarrera = $0 { return true }; return false })
        XCTAssertFalse(DetectorEventos.ameritaIA(eventos),
                       "estar cerca de la carrera no es motivo para tocar el plan")
    }
}

// MARK: - Validador (§39)

final class ValidadorAdaptacionTests: XCTestCase {

    func testNoSeTocaLoQueNoExiste() {
        let almacen = almacenDeSemana()
        XCTAssertFalse(ValidadorDeCoach.validar(.omitir(programadoID: UUID()),
                                                en: almacen, hoy: hoy).permitido)
    }

    func testNoSeTocaElPasado() {
        // Un PENDIENTE con fecha pasada: no está resuelto, pero ya pasó.
        let almacen = conVencido(almacenDeSemana(), dia: 11)
        let vencido = buscar(almacen, "Vencido")
        XCTAssertEqual(vencido.resolucion, .pendiente)
        XCTAssertFalse(ValidadorDeCoach.validar(.omitir(programadoID: vencido.id),
                                                en: almacen, hoy: hoy).permitido)
    }

    func testNoSeTocaLoYaResuelto() {
        let almacen = almacenDeSemana()
        let lunes = buscar(almacen, "Recuperación")   // cumplido
        XCTAssertFalse(ValidadorDeCoach.validar(.reducir(programadoID: lunes.id, factor: 0.8),
                                                en: almacen, hoy: hoy).permitido)
    }

    func testNoSeTocaLaCarreraObjetivo() {
        var almacen = almacenDeSemana()
        almacen.planActivo!.semanas[0].programados.append(
            programado("Maratón", tipo: .ritmoCarrera, km: 42.195,
                       dia: DiaLocal(anio: 2026, mes: 8, dia: 30)))
        let carrera = buscar(almacen, "Maratón")
        for cambio: CambioPropuesto in [
            .omitir(programadoID: carrera.id),
            .reducir(programadoID: carrera.id, factor: 0.9),
            .convertirEnFacil(programadoID: carrera.id),
            .reprogramar(programadoID: carrera.id, a: DiaLocal(anio: 2026, mes: 8, dia: 29)),
        ] {
            XCTAssertFalse(ValidadorDeCoach.validar(cambio, en: almacen, hoy: hoy).permitido,
                           "la carrera objetivo es un ancla inmutable")
        }
    }

    func testNoSeReprogramaHaciaElPasado() {
        let almacen = almacenDeSemana()
        let rodaje = buscar(almacen, "Rodaje")
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 1)),
            en: almacen, hoy: hoy).permitido)
    }

    func testNoSeReprogramaAUnDiaQueNoEligio() {
        let almacen = almacenDeSemana()   // días elegidos: 1, 3, 5, 7
        let rodaje = buscar(almacen, "Rodaje")
        // 13/8/2026 es jueves (día 4): no está entre los elegidos.
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 13)),
            en: almacen, hoy: hoy).permitido)
    }

    func testNoSeReprogramaAUnDiaImposible() {
        var almacen = almacenDeSemana()
        var perfil = almacen.perfilDeportivo
        perfil.diasElegidos = [1, 3, 4, 5, 7]
        perfil.preferencias = PreferenciasSemana(diaPreferidoFondo: nil, diasImposibles: [4])
        almacen.perfil = perfil
        let rodaje = buscar(almacen, "Rodaje")
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 13)),
            en: almacen, hoy: hoy).permitido)
    }

    func testNoSeReprogramaADiaOcupado() {
        let almacen = almacenDeSemana()
        let rodaje = buscar(almacen, "Rodaje")
        // 16/8 es domingo y ya tiene la tirada larga.
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 16)),
            en: almacen, hoy: hoy).permitido)
    }

    func testNoSeProgramaDespuesDeLaCarrera() {
        var almacen = almacenDeSemana()
        var perfil = almacen.perfilDeportivo
        perfil.fechaObjetivo = DiaLocal(anio: 2026, mes: 8, dia: 15)
        almacen.perfil = perfil
        let rodaje = buscar(almacen, "Rodaje")
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 17)),
            en: almacen, hoy: hoy).permitido)
    }

    func testDosExigentesPegadasSeRechazan() {
        // Días elegidos con sábado incluido para que el rechazo NO sea
        // por disponibilidad y se pruebe de verdad la recuperación.
        let almacen = almacenDeSemana(diasElegidos: [1, 3, 5, 6, 7])
        let umbral = buscar(almacen, "Umbral")   // calidad: pide 1 día de por medio
        // Sábado 15 queda pegado a la tirada larga del domingo 16.
        let validacion = ValidadorDeCoach.validar(
            .reprogramar(programadoID: umbral.id, a: DiaLocal(anio: 2026, mes: 8, dia: 15)),
            en: almacen, hoy: hoy)
        XCTAssertFalse(validacion.permitido)
        XCTAssertNotNil(validacion.motivo)
    }

    func testMoverAUnDiaLibreYSinVecinosExigentesSePermite() {
        // Miércoles 19: día elegido, sin nada programado y con los dos
        // días vecinos vacíos. Es el caso que SÍ tiene que pasar — si
        // no, la regla de recuperación sería un "nunca se mueve nada".
        let almacen = almacenDeSemana(diasElegidos: [1, 3, 5, 6, 7])
        let umbral = buscar(almacen, "Umbral")
        let validacion = ValidadorDeCoach.validar(
            .reprogramar(programadoID: umbral.id, a: DiaLocal(anio: 2026, mes: 8, dia: 19)),
            en: almacen, hoy: hoy)
        XCTAssertTrue(validacion.permitido, validacion.motivo ?? "")
    }

    func testNoSeOmiteLaUnicaLargaDeLaSemana() {
        let almacen = almacenDeSemana()
        let larga = buscar(almacen, "Tirada larga")
        let validacion = ValidadorDeCoach.validar(.omitir(programadoID: larga.id),
                                                  en: almacen, hoy: hoy)
        XCTAssertFalse(validacion.permitido)
        XCTAssertNotNil(validacion.motivo)
        // …pero acortarla sí se puede.
        XCTAssertTrue(ValidadorDeCoach.validar(.reducir(programadoID: larga.id, factor: 0.7),
                                               en: almacen, hoy: hoy).permitido)
    }

    func testElCoachNoPuedeAumentarCarga() {
        let almacen = almacenDeSemana()
        let umbral = buscar(almacen, "Umbral")
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reducir(programadoID: umbral.id, factor: 1.5), en: almacen, hoy: hoy).permitido)
    }

    func testReducirRespetaElVolumenMinimoDeLaSemana() {
        // Semana de 35 km con mínimo declarado en 33: acortar la larga
        // a la mitad la deja en 27 → se rechaza.
        let reglas = ReglasSemana(fase: .construccion, volumenObjetivoKm: 35,
                                  volumenMinimoKm: 33, volumenMaximoKm: 37,
                                  maximoCalidad: 1)
        let almacen = almacenDeSemana(reglas: reglas)
        let larga = buscar(almacen, "Tirada larga")
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reducir(programadoID: larga.id, factor: 0.6), en: almacen, hoy: hoy).permitido)
        XCTAssertTrue(ValidadorDeCoach.validar(
            .reducir(programadoID: larga.id, factor: 0.9), en: almacen, hoy: hoy).permitido)
    }

    func testSinReglasDeclaradasLaReglaDeVolumenNoOpina() {
        let almacen = almacenDeSemana()   // sin reglas
        let larga = buscar(almacen, "Tirada larga")
        XCTAssertTrue(ValidadorDeCoach.validar(
            .reducir(programadoID: larga.id, factor: 0.6), en: almacen, hoy: hoy).permitido,
            "sin mínimo declarado no se inventa un mínimo")
    }

    func testMantenerSiempreEsValido() {
        let almacen = almacenDeSemana()
        XCTAssertTrue(ValidadorDeCoach.validar(
            .mantener(programadoID: buscar(almacen, "Umbral").id),
            en: almacen, hoy: hoy).permitido)
    }

    func testFiltrarUnaTandaDejaSoloLoValido() {
        let almacen = almacenDeSemana()
        let cambios: [CambioPropuesto] = [
            .reducir(programadoID: buscar(almacen, "Umbral").id, factor: 0.8),   // ok
            .omitir(programadoID: buscar(almacen, "Tirada larga").id),           // no
            .omitir(programadoID: UUID()),                                       // no
        ]
        XCTAssertEqual(ValidadorDeCoach.validas(cambios, en: almacen, hoy: hoy).count, 1)
    }
}

// MARK: - Aplicador e historial (§44)

final class AplicadorAdaptacionTests: XCTestCase {

    func testAplicarDejaRastroEnElHistorial() {
        var almacen = almacenDeSemana()
        let id = buscar(almacen, "Umbral").id
        let aplicados = AplicadorAdaptacion.aplicar(
            [.reducir(programadoID: id, factor: 0.75)], a: &almacen, hoy: hoy,
            origen: .motor, motivo: "Venías muy exigido", ahora: ahora)
        XCTAssertEqual(aplicados, 1)
        XCTAssertEqual(almacen.historialAdaptaciones.count, 1)
        let registro = almacen.historialAdaptaciones[0]
        XCTAssertEqual(registro.tipo, .reducir)
        XCTAssertEqual(registro.origen, .motor)
        XCTAssertEqual(registro.programadoID, id)
        XCTAssertEqual(registro.motivo, "Venías muy exigido")
        XCTAssertNotEqual(registro.antes, registro.despues)
    }

    func testLoInvalidoNoSeAplicaNiSeAnota() {
        var almacen = almacenDeSemana()
        let aplicados = AplicadorAdaptacion.aplicar(
            [.omitir(programadoID: buscar(almacen, "Tirada larga").id),
             .omitir(programadoID: UUID())],
            a: &almacen, hoy: hoy, origen: .coach, motivo: "x", ahora: ahora)
        XCTAssertEqual(aplicados, 0)
        XCTAssertTrue(almacen.historialAdaptaciones.isEmpty)
        XCTAssertEqual(buscar(almacen, "Tirada larga").resolucion, .pendiente)
    }

    func testMantenerNoEsUnaAdaptacion() {
        var almacen = almacenDeSemana()
        let aplicados = AplicadorAdaptacion.aplicar(
            [.mantener(programadoID: buscar(almacen, "Umbral").id)],
            a: &almacen, hoy: hoy, origen: .coach, motivo: "todo bien", ahora: ahora)
        XCTAssertEqual(aplicados, 0)
        XCTAssertTrue(almacen.historialAdaptaciones.isEmpty)
    }

    func testConvertirQuedaAnotadoConSuTipo() {
        var almacen = almacenDeSemana()
        AplicadorAdaptacion.aplicar(
            [.convertirEnFacil(programadoID: buscar(almacen, "Umbral").id)],
            a: &almacen, hoy: hoy, origen: .motor, motivo: "molestia", ahora: ahora)
        XCTAssertEqual(almacen.historialAdaptaciones.first?.tipo, .convertir)
    }

    func testMoverQuedaAnotadoYConservaLaFechaOriginal() {
        var almacen = almacenDeSemana()
        let rodaje = buscar(almacen, "Rodaje")   // viernes 14
        let original = rodaje.dia
        AplicadorAdaptacion.aplicar(
            [.reprogramar(programadoID: rodaje.id, a: DiaLocal(anio: 2026, mes: 8, dia: 17))],
            a: &almacen, hoy: hoy, origen: .usuario, motivo: "viaje", ahora: ahora)
        let despues = buscar(almacen, "Rodaje")
        XCTAssertEqual(despues.dia, DiaLocal(anio: 2026, mes: 8, dia: 17))
        XCTAssertEqual(despues.diaOriginal, original)
        XCTAssertEqual(almacen.historialAdaptaciones.first?.tipo, .mover)
    }
}

// MARK: - Propuesta local sin IA (§49)

final class PropuestaLocalTests: XCTestCase {

    func testSinEventosNoProponeNada() {
        let almacen = almacenDeSemana()
        XCTAssertTrue(PropuestaLocal.proponer(para: [], en: almacen, hoy: hoy).isEmpty)
    }

    func testEsfuerzoAltoAlivianaLaProximaCalidad() {
        let almacen = almacenDeSemana()
        let cambios = PropuestaLocal.proponer(
            para: [.esfuerzoMuyAlto(sesionID: UUID())], en: almacen, hoy: hoy)
        XCTAssertEqual(cambios.count, 1)
        if case .convertirEnFacil(let id) = cambios[0] {
            XCTAssertEqual(id, buscar(almacen, "Umbral").id)
        } else {
            XCTFail("esperaba convertir la próxima calidad, vino \(cambios[0])")
        }
    }

    func testNuncaProponeMasDeUnaOperacionPorSesion() {
        let almacen = almacenDeSemana()
        let cambios = PropuestaLocal.proponer(
            para: [.esfuerzoMuyAlto(sesionID: UUID()),
                   .molestiaReportada(sesionID: UUID()),
                   .variasAusencias(cantidad: 3)],
            en: almacen, hoy: hoy)
        XCTAssertEqual(Set(cambios.map(\.programadoID)).count, cambios.count)
    }

    func testNuncaCompensaKilometrosPerdidos() {
        // §41: ante ausencias, jamás se agrega ni se apila volumen.
        let almacen = almacenDeSemana()
        let cambios = PropuestaLocal.proponer(
            para: [.variasAusencias(cantidad: 4)], en: almacen, hoy: hoy)
        for cambio in cambios {
            if case .reducir(_, let factor) = cambio {
                XCTAssertLessThan(factor, 1)
            }
            XCTAssertNotEqual(cambio.tipoDeAdaptacion, RegistroAdaptacion.Tipo.mover)
        }
    }

    func testLoQueProponeSiempreEsValido() {
        let almacen = almacenDeSemana()
        let cambios = PropuestaLocal.proponer(
            para: [.esfuerzoMuyAlto(sesionID: UUID()), .variasAusencias(cantidad: 2)],
            en: almacen, hoy: hoy)
        for cambio in cambios {
            XCTAssertTrue(ValidadorDeCoach.validar(cambio, en: almacen, hoy: hoy).permitido)
        }
    }
}

// MARK: - Feedback subjetivo (§33)

final class FeedbackSesionTests: XCTestCase {

    func testGuardarSensacionSobreUnaSesionExistente() {
        var almacen = AlmacenV2()
        let id = UUID()
        almacen.registrarSesionLibre(sesionID: id, fecha: ahora)
        XCTAssertTrue(almacen.registrarSensacion(sesionID: id, sensacion: .exigido,
                                                 conMolestia: false))
        XCTAssertEqual(almacen.sesiones.first?.sensacion, .exigido)
        XCTAssertEqual(almacen.sesiones.first?.conMolestia, false)
    }

    func testNoCreaSesionesFantasma() {
        var almacen = AlmacenV2()
        XCTAssertFalse(almacen.registrarSensacion(sesionID: UUID(), sensacion: .bien,
                                                  conMolestia: nil))
        XCTAssertTrue(almacen.sesiones.isEmpty)
    }

    func testSoloElExtremoAltoPideAtencion() {
        XCTAssertTrue(SensacionEsfuerzo.muyExigido.pideAtencion)
        XCTAssertFalse(SensacionEsfuerzo.exigido.pideAtencion)
        XCTAssertFalse(SensacionEsfuerzo.bien.pideAtencion)
        XCTAssertFalse(SensacionEsfuerzo.muyBien.pideAtencion)
    }

    func testAnalisisCalculaCumplimiento() {
        let programadoDePrueba = programado("Umbral", tipo: .umbral, km: 8, dia: hoy)
        let analisis = AnalisisPostCarrera.desde(
            sesion: SesionMetrica(fecha: ahora, metros: 6000, segundos: 2160),
            sesionID: UUID(), programado: programadoDePrueba, registro: nil,
            estructuraCompleta: false)
        XCTAssertEqual(analisis.cumplimiento ?? 0, 0.75, accuracy: 0.01)
        XCTAssertFalse(analisis.esLibre)
        XCTAssertEqual(analisis.ritmoSegKm, 360)
    }

    func testCarreraLibreNoTieneCumplimiento() {
        let analisis = AnalisisPostCarrera.desde(
            sesion: SesionMetrica(fecha: ahora, metros: 6000, segundos: 2160),
            sesionID: UUID(), programado: nil, registro: nil, estructuraCompleta: false)
        XCTAssertNil(analisis.cumplimiento)
        XCTAssertTrue(analisis.esLibre)
    }
}

// MARK: - Retrocompatibilidad del esquema (§57)

final class MigracionMotorAdaptativoTests: XCTestCase {

    /// Un dominio-v2.json de una build ANTERIOR tiene que decodificar
    /// sin perder nada. Si esto se rompe, un usuario que actualiza
    /// pierde su plan.
    func testAlmacenViejoDecodificaConLosCamposNuevos() throws {
        let json = """
        {
          "versionEsquema": 1, "activado": true,
          "audio": {"pistas": [], "avisosFijos": [], "avisosRepetidos": [], "avisosKm": []},
          "sesiones": [{"id": "\(UUID().uuidString)", "fecha": 780000000}],
          "referencias": [],
          "perfil": {"objetivo": "maraton", "diasPorSemana": 4, "testPendiente": false},
          "planActivo": {
            "id": "\(UUID().uuidString)", "nombre": "Viejo",
            "origen": {"personalizado": {}},
            "fechaAdopcion": 780000000,
            "semanas": [{"id": "\(UUID().uuidString)", "numero": 1, "programados": [
              {"id": "\(UUID().uuidString)",
               "definicion": {"id": "\(UUID().uuidString)", "tipo": "umbral",
                              "nombre": "Umbral", "descripcion": "",
                              "segmentos": [{"id": "\(UUID().uuidString)",
                                             "nombre": "Bloque", "distanciaKm": 8,
                                             "ritmo": {"libre": {}}}]},
               "resolucion": "pendiente"}]}]
          }
        }
        """
        let almacen = try JSONDecoder().decode(AlmacenV2.self, from: Data(json.utf8))
        XCTAssertEqual(almacen.planActivo?.nombre, "Viejo")
        XCTAssertEqual(almacen.perfilDeportivo.objetivo, .maraton)
        // Los campos nuevos quedan en su default, no rompen nada.
        XCTAssertTrue(almacen.historialAdaptaciones.isEmpty)
        XCTAssertNil(almacen.perfilDeportivo.actividad)
        XCTAssertNil(almacen.perfilDeportivo.molestias)
        XCTAssertNil(almacen.planActivo?.semanas[0].reglas)
        XCTAssertNil(almacen.sesiones.first?.sensacion)
        // Y el rol se DERIVA aunque no estuviera guardado.
        let programado = almacen.todosLosProgramados[0]
        XCTAssertEqual(programado.rol, .calidadPrincipal)
        XCTAssertTrue(programado.adaptabilidad.sePuedeReducir)
        XCTAssertFalse(programado.fueAdaptada)
    }

    func testIdaYVueltaConLosCamposNuevos() throws {
        var almacen = almacenDeSemana(reglas: ReglasSemana(fase: .taper))
        var perfil = almacen.perfilDeportivo
        perfil.datosBasicos = DatosBasicos(fechaNacimiento: DiaLocal(anio: 2003, mes: 1, dia: 20),
                                           sexo: .masculino, alturaCm: 178, pesoKg: 70)
        perfil.actividad = ActividadActual(origen: .confirmado, kmSemanales: 30)
        perfil.molestias = .molestiaLeve
        perfil.preferencias = PreferenciasSemana(diaPreferidoFondo: 6, diasImposibles: [3])
        almacen.perfil = perfil
        almacen.registrarAdaptacion(RegistroAdaptacion(
            fecha: ahora, programadoID: UUID(), tipo: .reducir, origen: .motor,
            antes: "8 km", despues: "6 km", motivo: "cansancio"))

        let datos = try JSONEncoder().encode(almacen)
        let vuelta = try JSONDecoder().decode(AlmacenV2.self, from: datos)
        XCTAssertEqual(vuelta, almacen)
        XCTAssertEqual(vuelta.perfilDeportivo.datosBasicos?.sexo, .masculino)
        XCTAssertEqual(vuelta.perfilDeportivo.preferencias?.diaPreferidoFondo, 6)
        XCTAssertEqual(vuelta.historialAdaptaciones.count, 1)
        XCTAssertEqual(vuelta.planActivo?.semanas[0].reglas?.fase, .taper)
    }

    func testEdadSeCalculaYNoSeGuarda() {
        let datos = DatosBasicos(fechaNacimiento: DiaLocal(anio: 2003, mes: 1, dia: 20))
        XCTAssertEqual(datos.edad(a: DiaLocal(anio: 2026, mes: 8, dia: 12)), 23)
        XCTAssertEqual(datos.edad(a: DiaLocal(anio: 2026, mes: 1, dia: 19)), 22)
        XCTAssertNil(DatosBasicos().edad(a: hoy))
    }
}

// MARK: - Privacidad del DTO enriquecido (§47, §54)

@MainActor
final class PrivacidadDTOTests: XCTestCase {

    /// El DTO creció mucho en este sprint (ventanas, eventos, fases,
    /// sensaciones). Este test lo mira CON DATOS REALES adentro: el de
    /// CoachTests usa un almacén vacío y por eso no prueba gran cosa.
    func testElDTOConDatosRealesNoLlevaGPSNiMuestras() throws {
        var almacen = almacenDeSemana(reglas: ReglasSemana(fase: .especifica))
        var perfil = almacen.perfilDeportivo
        perfil.objetivo = .maraton
        perfil.fechaObjetivo = DiaLocal(anio: 2026, mes: 11, dia: 1)
        perfil.preferencias = PreferenciasSemana(diaPreferidoFondo: 7, diasImposibles: [4])
        almacen.perfil = perfil
        almacen.registrarReferencia(ReferenciaRendimiento(
            fecha: ahora, fuente: .test5K, distanciaMetros: 5000, segundos: 1500))
        let sesionID = UUID()
        almacen.registrarSesionLibre(sesionID: sesionID, fecha: ahora)
        almacen.registrarSensacion(sesionID: sesionID, sensacion: .muyExigido,
                                   conMolestia: true)

        let historial = (1...12).map { sesion($0 * 2, km: 8) }
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen, pedidoExplicito: true))
        let contexto = ContextoCoach.desde(almacen, hoy: hoy, historial: historial,
                                           eventos: eventos, ahora: ahora)
        let json = String(data: try JSONEncoder().encode(contexto), encoding: .utf8)!
        let minuscula = json.lowercased()

        for prohibido in ["lat", "lon", "coord", "ruta", "route", "gps",
                          "heartrate", "hkworkout", "workoutuuid", "muestra",
                          "sample", "altitud", "elevation"] {
            XCTAssertFalse(minuscula.contains(prohibido),
                           "el DTO filtra «\(prohibido)»: \(json.prefix(400))")
        }
        // Y sí lleva lo que TIENE que llevar: agregados.
        XCTAssertTrue(json.contains("ventanas"))
        XCTAssertTrue(json.contains("eventos"))
        XCTAssertFalse(contexto.ventanas.isEmpty)
    }

    func testLaMolestiaViajaComoBanderaYNoComoDetalle() {
        // Una molestia declarada es una señal para el plan, no un dato
        // clínico que se le manda a un tercero con contexto.
        let dto = ContextoCoach.dto(.molestiaReportada(sesionID: UUID()))
        XCTAssertEqual(dto.tipo, "molestia")
        XCTAssertNil(dto.detalle)
        XCTAssertNil(dto.programadoID)
    }

    func testTodosLosEventosSeSerializanConTipoYSeveridad() {
        let eventos: [EventoEntrenamiento] = [
            .sesionPerdida(programadoID: UUID()),
            .sesionParcial(programadoID: UUID(), cumplimiento: 0.5),
            .variasAusencias(cantidad: 3),
            .volumenSemanalBajo(hechoKm: 10, previstoKm: 35),
            .esfuerzoMuyAlto(sesionID: UUID()),
            .molestiaReportada(sesionID: UUID()),
            .fondoComprometido(programadoID: UUID()),
            .carreraLibreSignificativa(sesionID: UUID(), km: 20),
            .cambioDeDisponibilidad,
            .pedidoDelUsuario,
            .cercaDeLaCarrera(diasRestantes: 5),
        ]
        for evento in eventos {
            let dto = ContextoCoach.dto(evento)
            XCTAssertFalse(dto.tipo.isEmpty)
            XCTAssertTrue(["baja", "media", "alta"].contains(dto.severidad))
        }
    }

    /// El identificador de sesión de Salud NUNCA sale: los eventos que
    /// llevan sesionID lo descartan al serializar.
    func testElUUIDDeSaludNoSaleEnNingunEvento() {
        let sesionID = UUID()
        for evento: EventoEntrenamiento in [
            .esfuerzoMuyAlto(sesionID: sesionID),
            .molestiaReportada(sesionID: sesionID),
            .carreraLibreSignificativa(sesionID: sesionID, km: 12),
        ] {
            let dto = ContextoCoach.dto(evento)
            XCTAssertNotEqual(dto.programadoID, sesionID.uuidString.lowercased())
            XCTAssertNil(dto.programadoID)
        }
    }
}
