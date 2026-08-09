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
