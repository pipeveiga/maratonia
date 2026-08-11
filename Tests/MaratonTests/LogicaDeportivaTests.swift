import XCTest
@testable import Maraton

// Tests de la lógica deportiva pura (Shared/Plan.swift y TramosImport).
// Cada caso replica la simulación validada durante la auditoría; los
// nombres describen la regla que protegen. Ver Tests/README.md para
// conectar este archivo al proyecto (una sola vez, en Xcode).

final class ZonasCardiacasTests: XCTestCase {

    // Caso real reportado por el usuario: 150-160 ppm en rodaje suave
    // con ~22 años. El % crudo de la máxima daba Z4; Karvonen da Z2-Z3.
    func testRodajeSuaveNoEsZona4() {
        XCTAssertEqual(zonaCardiaca(fc: 150, reposo: 55, maxima: 198), 2)
        XCTAssertEqual(zonaCardiaca(fc: 160, reposo: 55, maxima: 198), 3)
    }

    func testEsfuerzoMaximoEsZona5() {
        XCTAssertEqual(zonaCardiaca(fc: 190, reposo: 55, maxima: 198), 5)
    }

    func testSinLecturaDePulsoNoHayZona() {
        XCTAssertEqual(zonaCardiaca(fc: 0, reposo: 55, maxima: 198), 0)
    }

    func testDatosCorruptosNoCrashean() {
        // reposo >= máxima: división por cero o negativo si no se guarda.
        XCTAssertEqual(zonaCardiaca(fc: 150, reposo: 200, maxima: 190), 0)
        XCTAssertEqual(zonaCardiaca(fc: 150, reposo: 190, maxima: 190), 0)
    }

    func testLimitesDeZona() {
        // Exactamente 60% de reserva ya es Z2 (los rangos son [x, y)).
        // reposo 60, máxima 160: reserva = (fc-60)/100.
        XCTAssertEqual(zonaCardiaca(fc: 119, reposo: 60, maxima: 160), 1)
        XCTAssertEqual(zonaCardiaca(fc: 120, reposo: 60, maxima: 160), 2)
        XCTAssertEqual(zonaCardiaca(fc: 150, reposo: 60, maxima: 160), 5)
    }
}

final class CronogramaTests: XCTestCase {

    private func plan(fijos: [AvisoFijo] = [], repetidos: [AvisoRepetido] = []) -> Plan {
        Plan(nombre: "Test", pistas: [], avisosFijos: fijos, avisosRepetidos: repetidos)
    }

    func testExpansionMezclada() {
        let p = plan(
            fijos: [AvisoFijo(minuto: 30, texto: "gel")],
            repetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "agua")])
        let avisos = p.cronograma(duracionMaximaMinutos: 90).map { ($0.minuto, $0.texto) }
        XCTAssertEqual(avisos.map(\.0), [20, 30, 40, 60, 80])
        XCTAssertEqual(avisos.map(\.1), ["agua", "gel", "agua", "agua", "agua"])
    }

    func testFijoAntesQueRepetidoEnElMismoMinuto() {
        let p = plan(
            fijos: [AvisoFijo(minuto: 20, texto: "fijo")],
            repetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "repetido")])
        let primeros = p.cronograma(duracionMaximaMinutos: 20).map(\.texto)
        XCTAssertEqual(primeros, ["fijo", "repetido"])
    }

    func testBasuraFiltrada() {
        // Minutos <= 0 y cadencias <= 0 no generan avisos (ni loops).
        let p = plan(
            fijos: [AvisoFijo(minuto: 0, texto: "x"), AvisoFijo(minuto: -5, texto: "y")],
            repetidos: [AvisoRepetido(cadaMinutos: 0, desdeMinuto: 10, hastaMinuto: nil, texto: "z")])
        XCTAssertTrue(p.cronograma(duracionMaximaMinutos: 60).isEmpty)
    }

    func testPlanVacio() {
        XCTAssertTrue(Plan.vacio.cronograma(duracionMaximaMinutos: 360).isEmpty)
    }

    func testHastaMinutoRespetado() {
        let p = plan(repetidos: [
            AvisoRepetido(cadaMinutos: 10, desdeMinuto: 10, hastaMinuto: 30, texto: "a")])
        XCTAssertEqual(p.cronograma(duracionMaximaMinutos: 600).map(\.minuto), [10, 20, 30])
    }
}

final class FormatosTests: XCTestCase {

    func testFormatearRitmo() {
        XCTAssertEqual(formatearRitmo(230), "3:50")
        XCTAssertEqual(formatearRitmo(360), "6:00")
        XCTAssertEqual(formatearRitmo(59), "0:59")
    }

    func testRitmoParaHablar() {
        XCTAssertEqual(ritmoParaHablar(230), "3 50")
        XCTAssertEqual(ritmoParaHablar(305), "5 05")
    }

    func testKmTexto() {
        XCTAssertEqual(kmTexto(5.0), "5")
        XCTAssertEqual(kmTexto(7.5), "7.5")
    }
}

final class AutoPausaTests: XCTestCase {

    // Regresión del bug real observado: la distancia del sensor se
    // congela en movimiento (vehículo / hipo del delegate) y la lógica
    // vieja lo interpretaba como "parado". Con la doble confirmación,
    // avance congelado + GPS viendo desplazamiento = NO pausar.
    func testAvanceCongeladoConGPSEnMovimientoNoPausa() {
        XCTAssertFalse(AutoPausa.debePausar(
            avanceMetros: 0, ventanaSegundos: 10,
            desplazamientoGPSMetros: 120, edadUltimoGPSSegundos: 1))
    }

    func testDetencionRealSostenidaSiPausa() {
        XCTAssertTrue(AutoPausa.debePausar(
            avanceMetros: 2, ventanaSegundos: 10,
            desplazamientoGPSMetros: 3, edadUltimoGPSSegundos: 1))
    }

    // GPS viejo o inexistente NO es "parado": es señal no confiable.
    func testGPSViejoOInexistenteNoPausa() {
        XCTAssertFalse(AutoPausa.debePausar(
            avanceMetros: 0, ventanaSegundos: 10,
            desplazamientoGPSMetros: nil, edadUltimoGPSSegundos: 12))
        XCTAssertFalse(AutoPausa.debePausar(
            avanceMetros: 0, ventanaSegundos: 10,
            desplazamientoGPSMetros: nil, edadUltimoGPSSegundos: nil))
    }

    // Una ventana corta (una lectura anómala aislada) no pausa.
    func testVentanaCortaNoPausa() {
        XCTAssertFalse(AutoPausa.debePausar(
            avanceMetros: 0, ventanaSegundos: 3,
            desplazamientoGPSMetros: 0, edadUltimoGPSSegundos: 1))
    }

    func testCorriendoNormalNoPausa() {
        // ~5:00/km = 33 m cada 10 s.
        XCTAssertFalse(AutoPausa.debePausar(
            avanceMetros: 33, ventanaSegundos: 10,
            desplazamientoGPSMetros: 33, edadUltimoGPSSegundos: 1))
    }
}

final class DetectorReanudacionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // Una única lectura rápida (fix saltarín) NO reanuda.
    func testUnaSolaLecturaNoReanuda() {
        var detector = AutoPausa.DetectorReanudacion()
        XCTAssertFalse(detector.procesar(desplazamiento: 30, umbral: 15, fecha: t0))
    }

    // Movimiento sostenido (dos lecturas sobre el umbral, >= 1,5 s) SÍ.
    func testMovimientoSostenidoReanuda() {
        var detector = AutoPausa.DetectorReanudacion()
        XCTAssertFalse(detector.procesar(desplazamiento: 20, umbral: 15, fecha: t0))
        XCTAssertTrue(detector.procesar(desplazamiento: 25, umbral: 15,
                                        fecha: t0.addingTimeInterval(2)))
    }

    // Ruido alrededor del umbral: cruza, vuelve al punto de pausa,
    // cruza de nuevo… nunca sostiene → nunca reanuda (sin ping-pong).
    func testRuidoAlrededorDelUmbralNoHaceNada() {
        var detector = AutoPausa.DetectorReanudacion()
        var fecha = t0
        for _ in 0..<20 {
            XCTAssertFalse(detector.procesar(desplazamiento: 17, umbral: 15, fecha: fecha))
            fecha = fecha.addingTimeInterval(1)
            XCTAssertFalse(detector.procesar(desplazamiento: 3, umbral: 15, fecha: fecha))
            fecha = fecha.addingTimeInterval(1)
        }
    }

    // Dos lecturas sobre el umbral demasiado juntas todavía no alcanzan.
    func testDosLecturasMuyJuntasNoReanudan() {
        var detector = AutoPausa.DetectorReanudacion()
        XCTAssertFalse(detector.procesar(desplazamiento: 20, umbral: 15, fecha: t0))
        XCTAssertFalse(detector.procesar(desplazamiento: 22, umbral: 15,
                                         fecha: t0.addingTimeInterval(1)))
        XCTAssertTrue(detector.procesar(desplazamiento: 22, umbral: 15,
                                        fecha: t0.addingTimeInterval(2)))
    }
}

final class DrenajeDeAvisosTests: XCTestCase {

    private func aviso(_ minuto: Int, _ texto: String) -> AvisoProgramado {
        AvisoProgramado(minuto: minuto, texto: texto)
    }

    // Regresión del bug MAJOR de la revisión adversarial: el colapso
    // anti-ráfaga descartaba avisos legítimos del mismo minuto.
    func testTresAvisosDelMismoMinutoSuenanTodos() {
        let resultado = CarreraCelu.avisosParaAnunciar(
            vencidos: [aviso(30, "gel"), aviso(30, "agua"), aviso(30, "postura")],
            minuto: 30)
        XCTAssertEqual(resultado, ["gel", "agua", "postura"])
    }

    // Tras 20 min suspendida en background, los vencidos viejos no se
    // leen en ráfaga: suena solo el más reciente.
    func testCatchUpColapsaALoMasReciente() {
        let resultado = CarreraCelu.avisosParaAnunciar(
            vencidos: [aviso(30, "a"), aviso(35, "b"), aviso(40, "c")],
            minuto: 55)
        XCTAssertEqual(resultado, ["c"])
    }

    func testCatchUpConAvisoFrescoConservaSoloLosFrescos() {
        let resultado = CarreraCelu.avisosParaAnunciar(
            vencidos: [aviso(30, "viejo"), aviso(54, "b"), aviso(55, "c")],
            minuto: 55)
        XCTAssertEqual(resultado, ["b", "c"])
    }

    func testAvisoDelMinutoAnteriorCuentaComoFresco() {
        // Un tick que llega apenas tarde no degrada el aviso a "viejo".
        XCTAssertEqual(
            CarreraCelu.avisosParaAnunciar(vencidos: [aviso(29, "x")], minuto: 30),
            ["x"])
    }

    func testSinVencidosNoSuenaNada() {
        XCTAssertTrue(CarreraCelu.avisosParaAnunciar(vencidos: [], minuto: 30).isEmpty)
    }
}

final class CumplimientoDePlanTests: XCTestCase {

    private func planConTramos(_ nombre: String = "Bloque", km: Double = 3) -> Plan {
        var plan = Plan.vacio
        plan.tramos = [Tramo(nombre: nombre, kilometros: km,
                             ritmoMinSegKm: 300, ritmoMaxSegKm: 330)]
        return plan
    }

    // pending → completar el workout correspondiente → completed.
    func testPendienteACumplido() {
        let plan = planConTramos()
        XCTAssertEqual(estadoDelEntrenamiento(plan: plan, huellaCumplida: nil), .pendiente)
        let huella = plan.huellaEntrenamiento
        XCTAssertNotNil(huella)
        XCTAssertEqual(estadoDelEntrenamiento(plan: plan, huellaCumplida: huella), .cumplido)
    }

    // sync: el iPhone reenvía el MISMO plan → sigue cumplido (la huella
    // es de contenido, idéntico contenido = idéntica huella). Esto
    // también cubre cerrar/reabrir: la huella persiste en UserDefaults.
    func testReenviarElMismoPlanNoLoVuelvePendiente() {
        let enviado = planConTramos()
        let reenviado = planConTramos()
        XCTAssertEqual(enviado.huellaEntrenamiento, reenviado.huellaEntrenamiento)
        XCTAssertEqual(
            estadoDelEntrenamiento(plan: reenviado,
                                   huellaCumplida: enviado.huellaEntrenamiento),
            .cumplido)
    }

    // Editar los tramos = entrenamiento NUEVO → vuelve a pendiente.
    func testEditarTramosGeneraEntrenamientoNuevo() {
        let viejo = planConTramos(km: 3)
        let editado = planConTramos(km: 5)
        XCTAssertNotEqual(viejo.huellaEntrenamiento, editado.huellaEntrenamiento)
        XCTAssertEqual(
            estadoDelEntrenamiento(plan: editado,
                                   huellaCumplida: viejo.huellaEntrenamiento),
            .pendiente)
    }

    // Sin plan, o plan sin tramos (solo música/avisos): no hay
    // entrenamiento que cumplir.
    func testSinTramosNoHayEntrenamiento() {
        XCTAssertEqual(estadoDelEntrenamiento(plan: nil, huellaCumplida: nil), .sinEntrenamiento)
        XCTAssertEqual(estadoDelEntrenamiento(plan: .vacio, huellaCumplida: nil), .sinEntrenamiento)
        XCTAssertNil(Plan.vacio.huellaEntrenamiento)
    }

    // Carrera libre (0 tramos) NO consume el entrenamiento planificado.
    func testCarreraLibreNoMarcaCumplido() {
        XCTAssertFalse(debeMarcarCumplido(tramosTotales: 0, indiceAlcanzado: 0))
        XCTAssertFalse(debeMarcarCumplido(tramosTotales: 0, indiceAlcanzado: 5))
    }

    // Abandonar a mitad de plan NO marca cumplido (conservador).
    func testAbandonoNoMarcaCumplido() {
        XCTAssertFalse(debeMarcarCumplido(tramosTotales: 5, indiceAlcanzado: 3))
    }

    func testPlanCompletoSiMarca() {
        XCTAssertTrue(debeMarcarCumplido(tramosTotales: 5, indiceAlcanzado: 5))
        XCTAssertTrue(debeMarcarCumplido(tramosTotales: 5, indiceAlcanzado: 6))
    }
}

final class ImportacionTramosTests: XCTestCase {

    func testParsearRitmoValido() throws {
        XCTAssertEqual(try parsearRitmo("3:50"), 230)
        XCTAssertEqual(try parsearRitmo("10:05"), 605)
    }

    func testParsearRitmoInvalido() {
        XCTAssertThrowsError(try parsearRitmo("3:70"))   // segundos >= 60
        XCTAssertThrowsError(try parsearRitmo("rápido"))
        XCTAssertThrowsError(try parsearRitmo("3"))
    }

    func testComillasCurvasYFencesSeLimpian() throws {
        // Regresión del bug real: el teclado del iPhone convierte comillas
        // y ChatGPT envuelve en ```json — las dos cosas rompían el parser.
        let pegado = """
        ```json
        {\u{201C}tramos\u{201D}:[{\u{201C}nombre\u{201D}:\u{201C}Bloque\u{201D},\u{201C}km\u{201D}:3,\u{201C}ritmoMax\u{201D}:\u{201C}4:10\u{201D}}]}
        ```
        """
        let tramos = try parsearTramos(desde: pegado)
        XCTAssertEqual(tramos.count, 1)
        XCTAssertEqual(tramos[0].kilometros, 3)
        XCTAssertEqual(tramos[0].ritmoMaxSegKm, 250)
        XCTAssertNil(tramos[0].ritmoMinSegKm)
    }

    func testPlanViejoSinTramosDecodifica() throws {
        // Compatibilidad: un plan.json guardado por una versión sin
        // tramos/avisosKm tiene que seguir cargando (campos opcionales).
        let json = #"{"nombre":"Viejo","pistas":[],"avisosFijos":[],"avisosRepetidos":[]}"#
        let plan = try JSONDecoder().decode(Plan.self, from: Data(json.utf8))
        XCTAssertTrue(plan.tramosActivos.isEmpty)
        XCTAssertTrue(plan.avisosKmActivos.isEmpty)
    }
}

// MARK: - Avance de tramos mixtos (distancia + tiempo)

final class ProgresoTramosTests: XCTestCase {

    private func porDistancia(_ km: Double, nombre: String = "D") -> Tramo {
        Tramo(nombre: nombre, kilometros: km)
    }

    private func porTiempo(_ segundos: Int, nombre: String = "T") -> Tramo {
        Tramo(nombre: nombre, kilometros: 0, duracionSegundos: segundos)
    }

    func testPlanSoloDistanciaMismaSemanticaQuePrefijos() {
        var progreso = ProgresoTramos(tramos: [porDistancia(1), porDistancia(2)])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 999, tiempoActivo: 300), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 1000, tiempoActivo: 301),
                       [.cambioTramo(indice: 1)])
        // El fin del tramo 2 es 3000 m EXACTOS aunque el tick del cruce
        // haya pasado de largo (el excedente cuenta para el siguiente).
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 2999, tiempoActivo: 900), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 3004, tiempoActivo: 901),
                       [.planCompletado])
        XCTAssertTrue(progreso.terminado)
    }

    func testExcedenteDeDistanciaCuentaParaElSiguiente() {
        var progreso = ProgresoTramos(tramos: [porDistancia(1), porDistancia(1)])
        // El tick saltó de 900 a 1100: el tramo 2 arranca en 1000, no en 1100.
        _ = progreso.avanzar(distanciaMetros: 900, tiempoActivo: 10)
        _ = progreso.avanzar(distanciaMetros: 1100, tiempoActivo: 11)
        XCTAssertEqual(progreso.inicioDistanciaMetros, 1000)
        // Con 2100 m totales el tramo 2 ya cubrió sus 1000 m + excedente.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 2000, tiempoActivo: 20),
                       [.planCompletado])
    }

    func testPlanSoloTiempoAvanzaPorTiempoActivo() {
        var progreso = ProgresoTramos(tramos: [porTiempo(120), porTiempo(60)])
        // La distancia no importa: solo el tiempo activo.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 5000, tiempoActivo: 119), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 5010, tiempoActivo: 120),
                       [.cambioTramo(indice: 1)])
        // Fin exacto del tramo 2: 120 + 60 = 180 aunque el tick salte.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 5500, tiempoActivo: 179.5), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 5600, tiempoActivo: 183),
                       [.planCompletado])
    }

    func testTiempoCongeladoNoAvanzaTramoPorTiempo() {
        // En pausa el tiempo ACTIVO no corre: el tramo por tiempo tampoco.
        var progreso = ProgresoTramos(tramos: [porTiempo(60)])
        for _ in 0..<10 {
            XCTAssertEqual(progreso.avanzar(distanciaMetros: 100, tiempoActivo: 30), [])
        }
        XCTAssertFalse(progreso.terminado)
    }

    func testPlanMixtoDistanciaLuegoTiempoLuegoDistancia() {
        var progreso = ProgresoTramos(tramos: [porDistancia(1), porTiempo(120), porDistancia(1)])
        // Cierra el km 1 a los 300 s con 1002 m.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 1002, tiempoActivo: 300),
                       [.cambioTramo(indice: 1)])
        // El tramo por tiempo arranca en el tiempo del tick del cruce.
        XCTAssertEqual(progreso.inicioTiempoActivo, 300)
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 1300, tiempoActivo: 419), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 1405, tiempoActivo: 420),
                       [.cambioTramo(indice: 2)])
        // El tramo 3 (1 km) arranca en la distancia del tick del cruce:
        // termina en 1405 + 1000.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 2404, tiempoActivo: 900), [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 2405, tiempoActivo: 901),
                       [.planCompletado])
    }

    func testUnTickPuedeCerrarVariosTramos() {
        var progreso = ProgresoTramos(tramos: [porTiempo(10), porTiempo(10), porDistancia(5)])
        let eventos = progreso.avanzar(distanciaMetros: 80, tiempoActivo: 25)
        XCTAssertEqual(eventos, [.cambioTramo(indice: 1), .cambioTramo(indice: 2)])
        XCTAssertEqual(progreso.indice, 2)
        // El tramo 3 arranca con la distancia del tick (80 m ya corridos
        // no le cuentan: son de los tramos por tiempo).
        XCTAssertEqual(progreso.inicioDistanciaMetros, 80)
    }

    func testTramoDeCeroKilometrosSeCierraSolo() {
        var progreso = ProgresoTramos(tramos: [porDistancia(0), porDistancia(1)])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 0, tiempoActivo: 1),
                       [.cambioTramo(indice: 1)])
    }

    func testPlanVacioNoHaceNada() {
        var progreso = ProgresoTramos(tramos: [])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 5000, tiempoActivo: 600), [])
        XCTAssertFalse(progreso.terminado)   // sin plan no hay "completado"
        XCTAssertNil(progreso.tramoActual)
    }

    func testProgresoYRestanteDelTramoActual() {
        var progreso = ProgresoTramos(tramos: [porDistancia(2), porTiempo(120)])
        XCTAssertEqual(progreso.progresoTramoActual(distanciaMetros: 500, tiempoActivo: 100), 0.25)
        XCTAssertEqual(progreso.restanteTramoActual(distanciaMetros: 500, tiempoActivo: 100),
                       "faltan 1.5 km")
        XCTAssertEqual(progreso.restanteTramoActual(distanciaMetros: 1700, tiempoActivo: 400),
                       "faltan 300 m")
        _ = progreso.avanzar(distanciaMetros: 2000, tiempoActivo: 600)
        XCTAssertEqual(progreso.progresoTramoActual(distanciaMetros: 2200, tiempoActivo: 660), 0.5)
        XCTAssertEqual(progreso.restanteTramoActual(distanciaMetros: 2200, tiempoActivo: 660),
                       "faltan 1:00")
    }

    func testCumplimientoConPlanMixto() {
        var progreso = ProgresoTramos(tramos: [porDistancia(1), porTiempo(60)])
        _ = progreso.avanzar(distanciaMetros: 1000, tiempoActivo: 240)
        XCTAssertFalse(debeMarcarCumplido(tramosTotales: progreso.tramos.count,
                                          indiceAlcanzado: progreso.indice))
        _ = progreso.avanzar(distanciaMetros: 1200, tiempoActivo: 301)
        XCTAssertTrue(debeMarcarCumplido(tramosTotales: progreso.tramos.count,
                                         indiceAlcanzado: progreso.indice))
    }

    func testTramoViejoSinDuracionDecodifica() throws {
        // plan.json guardado por versiones sin duracionSegundos.
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","nombre":"Bloque","kilometros":3}"#
        let tramo = try JSONDecoder().decode(Tramo.self, from: Data(json.utf8))
        XCTAssertNil(tramo.duracionSegundos)
        XCTAssertFalse(tramo.esPorTiempo)
    }

    func testHuellaNoCambiaParaPlanesPorDistancia() {
        // Actualizar la app no puede "des-cumplir" el entrenamiento del
        // reloj: la huella de un plan por distancia queda IGUAL que la
        // que generaba la versión anterior.
        var plan = Plan.vacio
        plan.tramos = [Tramo(nombre: "Bloque", kilometros: 3, ritmoMinSegKm: 230, ritmoMaxSegKm: 250)]
        XCTAssertEqual(plan.huellaEntrenamiento, "Bloque|3.0|230|250")
        plan.tramos![0].duracionSegundos = 120
        plan.tramos![0].kilometros = 0
        XCTAssertEqual(plan.huellaEntrenamiento, "Bloque|0.0|230|250|t120")
    }

    func testTextosDeMeta() {
        XCTAssertEqual(duracionTexto(45), "45 s")
        XCTAssertEqual(duracionTexto(120), "2 min")
        XCTAssertEqual(duracionTexto(90), "1:30 min")
        XCTAssertEqual(metaParaHablar(Tramo(nombre: "T", kilometros: 0, duracionSegundos: 150)),
                       "2 minutos y 30 segundos")
        XCTAssertEqual(metaParaHablar(Tramo(nombre: "T", kilometros: 0, duracionSegundos: 60)),
                       "1 minuto")
        XCTAssertEqual(metaParaHablar(Tramo(nombre: "D", kilometros: 1)), "1 kilómetro")
        XCTAssertEqual(metaParaHablar(Tramo(nombre: "D", kilometros: 7.5)), "7.5 kilómetros")
        XCTAssertEqual(Tramo(nombre: "T", kilometros: 0, duracionSegundos: 120).descripcion,
                       "2 min libre")
    }
}

// MARK: - Auto-resume (bug 1 de build 39)

final class SupervisorReanudacionTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1000)
    private func t(_ segundos: Double) -> Date { base.addingTimeInterval(segundos) }

    func testAutoPausaLuegoMovimientoReanuda() {
        // running → autoPause → caminar alejándose → autoResume (camino
        // de desplazamiento, la semántica de siempre).
        var supervisor = AutoPausa.SupervisorReanudacion()
        XCTAssertFalse(supervisor.procesar(desplazamiento: 5, velocidad: nil,
                                           umbral: 15, fecha: t(0)))
        XCTAssertFalse(supervisor.procesar(desplazamiento: 18, velocidad: nil,
                                           umbral: 15, fecha: t(1)))   // arma
        XCTAssertTrue(supervisor.procesar(desplazamiento: 22, velocidad: nil,
                                          umbral: 15, fecha: t(3)))    // sostenido → reanuda
    }

    func testVelocidadSostenidaReanudaAunSinDesplazamiento() {
        // El caso de build 38: umbral inflado por mala precisión o
        // referencia ruidosa — la velocidad Doppler reanuda igual.
        var supervisor = AutoPausa.SupervisorReanudacion()
        XCTAssertFalse(supervisor.procesar(desplazamiento: 4, velocidad: 1.3,
                                           umbral: 40, fecha: t(0)))   // arma velocidad
        XCTAssertFalse(supervisor.procesar(desplazamiento: 6, velocidad: 1.2,
                                           umbral: 40, fecha: t(1)))   // < 1.5 s
        XCTAssertTrue(supervisor.procesar(desplazamiento: 8, velocidad: 1.4,
                                          umbral: 40, fecha: t(2)))    // sostenida → reanuda
        // Y también funciona SIN punto de referencia todavía (primer fix).
        var sinReferencia = AutoPausa.SupervisorReanudacion()
        XCTAssertFalse(sinReferencia.procesar(desplazamiento: nil, velocidad: 1.2,
                                              umbral: 15, fecha: t(0)))
        XCTAssertTrue(sinReferencia.procesar(desplazamiento: nil, velocidad: 1.2,
                                             umbral: 15, fecha: t(2)))
    }

    func testRuidoAlrededorDelUmbralNoReanuda() {
        // Lecturas saltarinas paradas al lado del umbral: nunca dos
        // sostenidas — no oscila.
        var supervisor = AutoPausa.SupervisorReanudacion()
        for (i, despl) in [16.0, 4.0, 17.0, 3.0, 18.0, 5.0].enumerated() {
            XCTAssertFalse(supervisor.procesar(desplazamiento: despl,
                                               velocidad: 0.2,
                                               umbral: 15, fecha: t(Double(i) * 2)),
                           "reanudó con ruido en la lectura \(i)")
        }
        // Velocidad ruidosa bajo el umbral de caminata tampoco arma.
        var porVelocidad = AutoPausa.SupervisorReanudacion()
        for (i, vel) in [0.8, 0.3, 0.85, 0.1, 0.7].enumerated() {
            XCTAssertFalse(porVelocidad.procesar(desplazamiento: 2, velocidad: vel,
                                                 umbral: 15, fecha: t(Double(i) * 2)))
        }
    }

    func testPausaManualNoEsElegibleParaAutoResume() {
        // running → manualPause → movimiento → sigue pausada: la regla
        // vive en la capa compartida y los dos delegates la consultan.
        XCTAssertFalse(AutoPausa.puedeAutoReanudar(pausada: true, enPausaAutomatica: false))
        XCTAssertTrue(AutoPausa.puedeAutoReanudar(pausada: true, enPausaAutomatica: true))
        XCTAssertFalse(AutoPausa.puedeAutoReanudar(pausada: false, enPausaAutomatica: false))
        // Estado imposible (auto sin pausa): tampoco habilita.
        XCTAssertFalse(AutoPausa.puedeAutoReanudar(pausada: false, enPausaAutomatica: true))
    }

    func testInteraccionManualDejaEstadoConsistente() {
        // autoPause → el corredor toca Reanudar a mano → reiniciar():
        // el supervisor no arrastra candidatos armados a la próxima.
        var supervisor = AutoPausa.SupervisorReanudacion()
        _ = supervisor.procesar(desplazamiento: 18, velocidad: 1.2, umbral: 15, fecha: t(0))
        supervisor.reiniciar()
        // Tras el reset, una lectura sostenida sola NO reanuda: hay que
        // volver a armar de cero.
        XCTAssertFalse(supervisor.procesar(desplazamiento: 20, velocidad: 1.2,
                                           umbral: 15, fecha: t(10)))
        XCTAssertTrue(supervisor.procesar(desplazamiento: 22, velocidad: 1.3,
                                          umbral: 15, fecha: t(12)))
    }

    func testVigilanteDeGPS() {
        // Sin señal y sin empujón reciente → despertar. Con señal
        // fresca o empujón reciente → no molestar.
        XCTAssertTrue(AutoPausa.debeDespertarGPS(edadUltimaSenal: 11, edadUltimoEmpujon: nil))
        XCTAssertTrue(AutoPausa.debeDespertarGPS(edadUltimaSenal: nil, edadUltimoEmpujon: 12))
        XCTAssertFalse(AutoPausa.debeDespertarGPS(edadUltimaSenal: 3, edadUltimoEmpujon: nil))
        XCTAssertFalse(AutoPausa.debeDespertarGPS(edadUltimaSenal: 30, edadUltimoEmpujon: 5))
        XCTAssertTrue(AutoPausa.debeDespertarGPS(edadUltimaSenal: nil, edadUltimoEmpujon: nil))
    }

    func testTramoPorTiempoCongeladoYContinuaTrasResume() {
        // El tiempo ACTIVO no corre en pausa: el tramo no avanza; al
        // reanudar, completa con su duración exacta.
        var progreso = ProgresoTramos(tramos: [Tramo(nombre: "T", kilometros: 0,
                                                     duracionSegundos: 120)])
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 200, tiempoActivo: 60), [])
        // Pausa de 5 minutos: el tiempo activo queda clavado en 60.
        for _ in 0..<300 {
            XCTAssertEqual(progreso.avanzar(distanciaMetros: 200, tiempoActivo: 60), [])
        }
        // Reanuda: 59 s más de tiempo activo aún no cierra…
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 350, tiempoActivo: 119), [])
        // …y al llegar a los 120 s ACTIVOS exactos, cierra.
        XCTAssertEqual(progreso.avanzar(distanciaMetros: 360, tiempoActivo: 120),
                       [.planCompletado])
    }
}

// MARK: - Localización de fechas (build 41)

final class FormatoFechaTests: XCTestCase {

    private let es = Locale(identifier: "es_AR")
    private let en = Locale(identifier: "en_US")

    /// martes 11 de agosto de 2026, 21:54 hora local.
    private var fecha: Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 8, day: 11, hour: 21, minute: 54))!
    }

    func testFechaCortaDeEntrenamiento() {
        let texto = FormatoFecha.corta(fecha, locale: es).lowercased()
        XCTAssertTrue(texto.contains("martes"), texto)
        XCTAssertTrue(texto.contains("11"), texto)
        XCTAssertTrue(texto.contains("ago"), texto)
        XCTAssertFalse(texto.contains("tuesday"), texto)
        XCTAssertFalse(texto.contains("aug"), texto)
    }

    func testFechaLargaDeDetalle() {
        let texto = FormatoFecha.larga(fecha, locale: es).lowercased()
        XCTAssertTrue(texto.contains("martes"), texto)
        XCTAssertTrue(texto.contains("de agosto"), texto)   // "11 de agosto"
        XCTAssertFalse(texto.contains("august"), texto)
    }

    func testFechaYHoraDeCarrera() {
        let texto = FormatoFecha.fechaYHora(fecha, locale: es).lowercased()
        XCTAssertTrue(texto.contains("ago"), texto)
        XCTAssertTrue(texto.contains("2026"), texto)
        XCTAssertTrue(texto.contains(" · "), texto)         // sin "at"/"a las"
        XCTAssertTrue(texto.contains("54"), texto)
        XCTAssertFalse(texto.contains(" at "), texto)
    }

    func testCambioDeLocale() {
        // La MISMA arquitectura formatea en el idioma que se le pida:
        // el bug era que el bundle resolvía inglés, no los formatos.
        let esCorta = FormatoFecha.corta(fecha, locale: es).lowercased()
        let enCorta = FormatoFecha.corta(fecha, locale: en).lowercased()
        XCTAssertTrue(esCorta.contains("martes"))
        XCTAssertTrue(enCorta.contains("tuesday"))
        XCTAssertTrue(FormatoFecha.larga(fecha, locale: en).contains("August"))
        XCTAssertTrue(FormatoFecha.media(fecha, locale: en).contains("2026"))
    }

    func testFormatosCompactos() {
        XCTAssertEqual(FormatoFecha.numerica(fecha, locale: es), "11/8")
        let corto = FormatoFecha.diaCorto(fecha, locale: es).lowercased()
        XCTAssertTrue(corto.contains("mar"), corto)         // "mar 11/8"
        XCTAssertTrue(corto.contains("11/8"), corto)
        XCTAssertEqual(FormatoFecha.diaDeSemana(fecha, locale: es).lowercased(), "martes")
    }

    func testFormatearNoAlteraLaFecha() {
        // Presentación pura: ni el Date ni el día calendario cambian
        // por formatear (en ningún locale).
        let dia = DiaLocal(anio: 2026, mes: 8, dia: 11)
        let fecha = dia.fecha()!
        let antes = fecha.timeIntervalSince1970
        for locale in [es, en] {
            _ = FormatoFecha.corta(fecha, locale: locale)
            _ = FormatoFecha.larga(fecha, locale: locale)
            _ = FormatoFecha.fechaYHora(fecha, locale: locale)
            _ = FormatoFecha.completa(fecha, locale: locale)
        }
        XCTAssertEqual(fecha.timeIntervalSince1970, antes)
        XCTAssertEqual(DiaLocal(fecha: fecha), dia)   // mismo día local
    }
}

// MARK: - Calidad de métricas (RC1)

final class MetricasSesionTests: XCTestCase {

    func testRitmoConGuardsCompletos() {
        // El caso real de build 40: sesión de prueba diminuta → 0:15/km.
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 80, segundos: 20))
        // División por cero / duración cero / distancia cero.
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 0, segundos: 100))
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 1000, segundos: 0))
        // NaN e infinito jamás pasan.
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: .nan, segundos: 100))
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 1000, segundos: .infinity))
        // Absurdo rápido (1:00/km) y absurdo lento (33:20/km).
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 5000, segundos: 300))
        XCTAssertNil(MetricasSesion.ritmoSegKm(metros: 500, segundos: 1000000))
        // Uno real: 5 km en 25:00 → 5:00/km.
        XCTAssertEqual(MetricasSesion.ritmoSegKm(metros: 5000, segundos: 1500), 300)
        // El piso es configurable (el reloj usa 100 m para el resumen).
        XCTAssertNotNil(MetricasSesion.ritmoSegKm(metros: 150, segundos: 60,
                                                  metrosMinimos: 100))
    }

    func testElegibilidadParaMarcas() {
        // Elegible: 5 km en 25 min.
        XCTAssertTrue(MetricasSesion.elegibleParaMarcas(metros: 5000, segundos: 1500))
        // Corta en distancia o en tiempo: historial sí, marca no.
        XCTAssertFalse(MetricasSesion.elegibleParaMarcas(metros: 900, segundos: 600))
        XCTAssertFalse(MetricasSesion.elegibleParaMarcas(metros: 2000, segundos: 200))
        // Ritmo implausible (más rápido que 2:30/km sostenido).
        XCTAssertFalse(MetricasSesion.elegibleParaMarcas(metros: 5000, segundos: 700))
        // Caminata muy lenta (> 15:00/km): sin marca.
        XCTAssertFalse(MetricasSesion.elegibleParaMarcas(metros: 1000, segundos: 1000))
        XCTAssertFalse(MetricasSesion.elegibleParaMarcas(metros: .nan, segundos: 600))
    }

    func testDestacadosIgnoranSesionesDePrueba() {
        let sesiones = [
            SesionMetrica(fecha: Date(), metros: 80, segundos: 20),      // prueba: 0:15/km
            SesionMetrica(fecha: Date(), metros: 12000, segundos: 90),   // sensor roto
            SesionMetrica(fecha: Date(), metros: 5000, segundos: 1500),  // real, 5:00/km
            SesionMetrica(fecha: Date(), metros: 8000, segundos: 2800),  // real, más larga
        ]
        let (masLarga, mejorRitmo) = CalculoProgreso.destacados(sesiones)
        // La "salida" del sensor roto (12 km en 90 s) no es la más larga.
        XCTAssertEqual(masLarga?.metros, 8000)
        XCTAssertEqual(mejorRitmo?.metros, 5000)
        // Solo basura → sin marcas, jamás un número absurdo.
        let vacio = CalculoProgreso.destacados([
            SesionMetrica(fecha: Date(), metros: 80, segundos: 20)])
        XCTAssertNil(vacio.masLarga)
        XCTAssertNil(vacio.mejorRitmo)
    }
}

// MARK: - Build 54: estimador de ritmo en vivo + análisis post-carrera

final class EstimadorRitmoLiveTests: XCTestCase {

    /// Simula ticks 1/s con una velocidad dada (m/s), con entrega de
    /// distancia en ráfagas de `lote` segundos (como HealthKit real).
    private func correr(_ estimador: inout EstimadorRitmoLive,
                        desde t0: Double, segundos: Int,
                        velocidad: Double, lote: Int = 1,
                        distanciaInicial: Double) -> Double {
        var distanciaReal = distanciaInicial
        var distanciaEntregada = distanciaInicial
        for i in 0..<segundos {
            distanciaReal += velocidad
            if lote <= 1 || (i % lote == lote - 1) {
                distanciaEntregada = distanciaReal
            }
            estimador.procesar(tiempo: t0 + Double(i + 1),
                               distanciaAcumulada: distanciaEntregada)
        }
        return distanciaReal
    }

    // TEST 1: carrera estable a 6:30/km (2.564 m/s) con ráfagas de 3 s
    // → estable alrededor de 6:30, sin oscilaciones de 30 s/km.
    func testEstableSeisTreintaConRafagas() {
        var e = EstimadorRitmoLive()
        _ = correr(&e, desde: 0, segundos: 120, velocidad: 1000.0 / 390, lote: 3,
                   distanciaInicial: 0)
        let ritmo = e.ritmoSegKm!
        XCTAssertTrue((380...400).contains(ritmo), "ritmo: \(ritmo)")
        XCTAssertTrue(e.esConfiable)
    }

    // TEST 2+3+13: congelamiento largo + lote de recuperación → JAMÁS
    // 2:00/km; durante el congelamiento pasa a stale y luego a nil; al
    // volver el GPS converge suave al ritmo real.
    func testLoteDeRecuperacionNoProduceDosMinutos() {
        var e = EstimadorRitmoLive()
        let v = 1000.0 / 390   // 6:30/km
        let d = correr(&e, desde: 0, segundos: 60, velocidad: v, distanciaInicial: 0)
        // 45 s congelado (misma distancia entregada)…
        for i in 0..<45 {
            e.procesar(tiempo: 60 + Double(i + 1), distanciaAcumulada: d)
        }
        XCTAssertNil(e.ritmoSegKm, "tras caducidad debe ser nil (--:--)")
        // …y llega el lote con TODO lo corrido en esos 45 s de golpe.
        let recuperada = d + v * 45
        let publicado = e.procesar(tiempo: 106, distanciaAcumulada: recuperada)
        if let publicado {
            XCTAssertGreaterThan(publicado, 300,
                "el lote de recuperación produjo un ritmo absurdo: \(publicado)")
        }
        // Siguen ticks normales: converge al ritmo real.
        _ = correr(&e, desde: 106, segundos: 40, velocidad: v, distanciaInicial: recuperada)
        XCTAssertTrue((370...410).contains(e.ritmoSegKm ?? 0), "\(e.ritmoSegKm ?? 0)")
    }

    // TEST 4: aceleración real 6:00 → 4:30 converge en pocos segundos.
    func testAceleracionRealConverge() {
        var e = EstimadorRitmoLive()
        let d = correr(&e, desde: 0, segundos: 60, velocidad: 1000.0 / 360, distanciaInicial: 0)
        _ = correr(&e, desde: 60, segundos: 30, velocidad: 1000.0 / 270, distanciaInicial: d)
        let ritmo = e.ritmoSegKm!
        XCTAssertLessThan(ritmo, 320, "a los 30 s ya debe reflejar la aceleración: \(ritmo)")
    }

    // TEST 5: desaceleración real también converge.
    func testDesaceleracionConverge() {
        var e = EstimadorRitmoLive()
        let d = correr(&e, desde: 0, segundos: 60, velocidad: 1000.0 / 270, distanciaInicial: 0)
        _ = correr(&e, desde: 60, segundos: 40, velocidad: 1000.0 / 390, distanciaInicial: d)
        XCTAssertGreaterThan(e.ritmoSegKm!, 340)
    }

    // TEST 6/9: una muestra espacial incoherente (velocidad imposible)
    // se rechaza sin ensuciar el publicado.
    func testMuestraImposibleRechazada() {
        var e = EstimadorRitmoLive()
        let d = correr(&e, desde: 0, segundos: 60, velocidad: 1000.0 / 390, distanciaInicial: 0)
        let antes = e.ritmoSegKm
        e.procesar(tiempo: 61, distanciaAcumulada: d + 20)   // 20 m en 1 s = 20 m/s
        XCTAssertEqual(e.ritmoSegKm, antes)
    }

    // TEST 7/8: timestamps duplicados o hacia atrás — sin división por
    // cero, sin cambio de estado.
    func testTimestampsIrregularesSeguros() {
        var e = EstimadorRitmoLive()
        let d = correr(&e, desde: 0, segundos: 30, velocidad: 2.5, distanciaInicial: 0)
        let antes = e.ritmoSegKm
        e.procesar(tiempo: 30, distanciaAcumulada: d + 5)    // duplicado
        e.procesar(tiempo: 29, distanciaAcumulada: d + 9)    // hacia atrás
        XCTAssertEqual(e.ritmoSegKm, antes)
    }

    // TEST 10/11: pausa manual → estado seguro; reanudación → warm-up
    // sin spikes (no publica hasta juntar datos nuevos).
    func testPausaYReanudacionConWarmUp() {
        var e = EstimadorRitmoLive()
        _ = correr(&e, desde: 0, segundos: 60, velocidad: 2.5, distanciaInicial: 0)
        XCTAssertNotNil(e.ritmoSegKm)
        e.reiniciar()
        XCTAssertNil(e.ritmoSegKm)
        XCTAssertFalse(e.esConfiable)
        // Tres ticks tras reanudar: todavía en warm-up, nada publicado.
        e.procesar(tiempo: 300, distanciaAcumulada: 500)
        e.procesar(tiempo: 301, distanciaAcumulada: 502.5)
        e.procesar(tiempo: 302, distanciaAcumulada: 505)
        XCTAssertNil(e.ritmoSegKm)
    }

    // TEST 12: GPS desaparece → stale primero (valor visible, no
    // confiable) y luego nil.
    func testDegradacionStaleLuegoNil() {
        var e = EstimadorRitmoLive()
        let d = correr(&e, desde: 0, segundos: 60, velocidad: 2.5, distanciaInicial: 0)
        for i in 0..<12 {
            e.procesar(tiempo: 60 + Double(i + 1), distanciaAcumulada: d)
        }
        XCTAssertNotNil(e.ritmoSegKm)      // stale: se muestra
        XCTAssertFalse(e.esConfiable)      // pero no acciona al coach
        for i in 12..<25 {
            e.procesar(tiempo: 60 + Double(i + 1), distanciaAcumulada: d)
        }
        XCTAssertNil(e.ritmoSegKm)         // caducado: --:--
    }
}

final class AnalisisSesionTests: XCTestCase {

    func testSplitsInterpolados() {
        // 2.5 km exactos a 6:00/km → splits de 360 s.
        var puntos: [AnalisisSesion.Punto] = []
        for i in 0...250 {
            puntos.append(.init(t: Double(i) * 3.6, d: Double(i) * 10, alt: 10))
        }
        let splits = AnalisisSesion.splits(puntos)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].segundos, 360)
        XCTAssertEqual(splits[1].segundos, 360)
    }

    func testReducirYDesnivel() {
        let muchos = Array(0..<1000)
        XCTAssertEqual(AnalisisSesion.reducir(muchos, a: 80).count, 80)
        // Subida de 30 m con ruido < 1 m no suma ruido.
        var puntos: [AnalisisSesion.Punto] = []
        for i in 0...100 {
            puntos.append(.init(t: Double(i), d: Double(i) * 10,
                                alt: 10 + Double(i) * 0.3))
        }
        let desnivel = AnalisisSesion.desnivelPositivo(puntos)!
        XCTAssertEqual(desnivel, 30, accuracy: 3)
    }
}
