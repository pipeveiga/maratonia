import XCTest
@testable import Maraton

// Tests del dominio V2 (Fase A). Protegen las invariantes de
// ARCHITECTURE_V2 §Fase A: identidad estable, snapshot, estados,
// vínculos sesión↔programado, serialización y migración V1→V2.

private func definicionDeEjemplo() -> DefinicionEntrenamiento {
    DefinicionEntrenamiento(
        tipo: .facil, nombre: "Rodaje",
        segmentos: [Segmento(nombre: "Rodaje", distanciaKm: 8,
                             ritmo: .absoluto(minSegKm: 345, maxSegKm: 370))])
}

private func almacenConProgramado() -> (AlmacenV2, UUID) {
    var almacen = AlmacenV2()
    let programado = EntrenamientoProgramado(
        definicion: definicionDeEjemplo(),
        dia: DiaLocal(anio: 2026, mes: 8, dia: 11))
    almacen.planActivo = PlanUsuario(
        nombre: "Test", fechaAdopcion: Date(timeIntervalSince1970: 0),
        semanas: [SemanaPlan(numero: 1, programados: [programado])])
    return (almacen, programado.id)
}

final class IdentidadTests: XCTestCase {

    // Editar contenido NO cambia la identidad.
    func testEditarContenidoConservaIdentidad() {
        var programado = EntrenamientoProgramado(definicion: definicionDeEjemplo())
        let id = programado.id
        let definicionID = programado.definicion.id
        programado.definicion.nombre = "Rodaje largo"
        programado.definicion.segmentos[0].distanciaKm = 12
        XCTAssertEqual(programado.id, id)
        XCTAssertEqual(programado.definicion.id, definicionID)
    }

    // Mover la fecha NO cambia la identidad y conserva la historia.
    func testReprogramarConservaIdentidadYFechaOriginal() {
        var programado = EntrenamientoProgramado(
            definicion: definicionDeEjemplo(),
            dia: DiaLocal(anio: 2026, mes: 8, dia: 11))
        let id = programado.id
        programado.reprogramar(a: DiaLocal(anio: 2026, mes: 8, dia: 12))
        programado.reprogramar(a: DiaLocal(anio: 2026, mes: 8, dia: 13))
        XCTAssertEqual(programado.id, id)
        XCTAssertEqual(programado.dia, DiaLocal(anio: 2026, mes: 8, dia: 13))
        // La fecha ORIGINAL es la primera, aunque se mueva dos veces.
        XCTAssertEqual(programado.diaOriginal, DiaLocal(anio: 2026, mes: 8, dia: 11))
        XCTAssertEqual(programado.resolucion, .pendiente)  // reprogramar no es estado
    }

    // El snapshot del usuario es independiente del template: mutar una
    // copia no afecta a la otra (semántica de valor + IDs propios).
    func testSnapshotIndependienteDelTemplate() {
        let template = definicionDeEjemplo()
        var plan1 = PlanUsuario(nombre: "A", fechaAdopcion: Date(timeIntervalSince1970: 0),
                                semanas: [SemanaPlan(numero: 1, programados: [
                                    EntrenamientoProgramado(definicion: template)])])
        let plan2 = PlanUsuario(nombre: "B", fechaAdopcion: Date(timeIntervalSince1970: 0),
                                semanas: [SemanaPlan(numero: 1, programados: [
                                    EntrenamientoProgramado(definicion: template)])])
        plan1.semanas[0].programados[0].definicion.segmentos[0].distanciaKm = 21
        XCTAssertEqual(plan2.semanas[0].programados[0].definicion.segmentos[0].distanciaKm, 8)
        XCTAssertNotEqual(plan1.id, plan2.id)
    }
}

final class EstadosProgramadoTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)

    func testProgramadoFuturoYHoy() {
        var programado = EntrenamientoProgramado(definicion: definicionDeEjemplo(),
                                                 dia: DiaLocal(anio: 2026, mes: 8, dia: 10))
        XCTAssertEqual(programado.estado(hoy: hoy), .programado)
        programado.dia = DiaLocal(anio: 2026, mes: 8, dia: 15)
        XCTAssertEqual(programado.estado(hoy: hoy), .programado)
    }

    // overdue se DERIVA de la fecha: el paso del tiempo no muta datos.
    func testVencidoDerivadoNoPersistido() {
        let programado = EntrenamientoProgramado(definicion: definicionDeEjemplo(),
                                                 dia: DiaLocal(anio: 2026, mes: 8, dia: 9))
        XCTAssertEqual(programado.estado(hoy: hoy), .vencido)
        XCTAssertEqual(programado.resolucion, .pendiente)  // persistido: sin cambios
    }

    // Un vencido que después se hace queda cumplido (la resolución
    // explícita pisa lo derivado).
    func testVencidoLuegoCumplido() {
        var (almacen, programadoID) = almacenConProgramado()
        almacen.planActivo!.semanas[0].programados[0].dia = DiaLocal(anio: 2026, mes: 8, dia: 1)
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[0].estado(hoy: hoy), .vencido)
        almacen.vincular(sesionID: UUID(), fechaSesion: Date(timeIntervalSince1970: 100),
                         aProgramado: programadoID, completo: true)
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[0].estado(hoy: hoy), .cumplido)
    }

    func testOmitirSoloDesdePendiente() {
        var programado = EntrenamientoProgramado(definicion: definicionDeEjemplo())
        programado.resolucion = .cumplido
        programado.omitir()
        XCTAssertEqual(programado.resolucion, .cumplido)  // no se pisa
        var pendiente = EntrenamientoProgramado(definicion: definicionDeEjemplo())
        pendiente.omitir()
        XCTAssertEqual(pendiente.resolucion, .omitido)
    }

    func testSinFechaNoEsVencido() {
        let programado = EntrenamientoProgramado(definicion: definicionDeEjemplo(), dia: nil)
        XCTAssertEqual(programado.estado(hoy: hoy), .programado)
    }
}

final class VinculoSesionTests: XCTestCase {

    // Estructura completa → cumplido; iniciada sin completar → parcial (D1).
    func testVincularCompletoYParcial() {
        var (almacen, programadoID) = almacenConProgramado()
        let sesion = UUID()
        XCTAssertTrue(almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                                       aProgramado: programadoID, completo: false))
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[0].resolucion, .parcial)
        // La info original se conserva: el vínculo está, la sesión está.
        XCTAssertEqual(almacen.sesiones.first?.vinculoProgramadoID, programadoID)

        var (almacen2, programadoID2) = almacenConProgramado()
        XCTAssertTrue(almacen2.vincular(sesionID: UUID(), fechaSesion: Date(timeIntervalSince1970: 1),
                                        aProgramado: programadoID2, completo: true))
        XCTAssertEqual(almacen2.planActivo!.semanas[0].programados[0].resolucion, .cumplido)
    }

    // Completar dos veces es idempotente.
    func testVincularIdempotente() {
        var (almacen, programadoID) = almacenConProgramado()
        let sesion = UUID()
        XCTAssertTrue(almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                                       aProgramado: programadoID, completo: true))
        let antes = almacen
        XCTAssertTrue(almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                                       aProgramado: programadoID, completo: true))
        XCTAssertEqual(almacen, antes)
        XCTAssertEqual(almacen.sesiones.count, 1)  // sin duplicados
    }

    // Una sesión se vincula a lo sumo a UN programado: el segundo intento
    // se rechaza (deshacer un vínculo es acción aparte, nunca un efecto).
    func testSesionNoPuedeVincularseADosProgramados() {
        var (almacen, primerID) = almacenConProgramado()
        let segundo = EntrenamientoProgramado(definicion: definicionDeEjemplo(),
                                              dia: DiaLocal(anio: 2026, mes: 8, dia: 12))
        almacen.planActivo!.semanas[0].programados.append(segundo)
        let sesion = UUID()
        XCTAssertTrue(almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                                       aProgramado: primerID, completo: true))
        XCTAssertFalse(almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                                        aProgramado: segundo.id, completo: true))
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[1].resolucion, .pendiente)
    }

    // Carrera Libre: vínculo nil, no toca ningún programado, idempotente.
    func testCarreraLibreSinVinculo() {
        var (almacen, _) = almacenConProgramado()
        let sesion = UUID()
        almacen.registrarSesionLibre(sesionID: sesion, fecha: Date(timeIntervalSince1970: 5))
        almacen.registrarSesionLibre(sesionID: sesion, fecha: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(almacen.sesiones.count, 1)
        XCTAssertTrue(almacen.sesiones[0].esLibre)
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[0].resolucion, .pendiente)
    }

    // Un programado puede existir sin sesión; el historial de sesiones
    // no desaparece al modificar el plan.
    func testHistorialSobreviveCambiosDelPlan() {
        var (almacen, _) = almacenConProgramado()
        almacen.registrarSesionLibre(sesionID: UUID(), fecha: Date(timeIntervalSince1970: 7))
        almacen.planActivo!.semanas[0].programados[0].definicion.nombre = "Editado"
        almacen.planActivo!.nombre = "Otro nombre"
        XCTAssertEqual(almacen.sesiones.count, 1)
    }
}

final class SerializacionV2Tests: XCTestCase {

    // Round-trip completo del grafo, incluyendo los tres casos de
    // RitmoObjetivo y los estados cumplido/parcial.
    func testRoundTripJSON() throws {
        var (almacen, programadoID) = almacenConProgramado()
        almacen.planActivo!.semanas[0].programados[0].definicion.segmentos += [
            Segmento(nombre: "Recuperación", duracionSegundos: 120, ritmo: .libre),
            Segmento(nombre: "Umbral", distanciaKm: 3, ritmo: .simbolico(.umbral)),
        ]
        almacen.vincular(sesionID: UUID(), fechaSesion: Date(timeIntervalSince1970: 9),
                         aProgramado: programadoID, completo: true)
        almacen.registrarSesionLibre(sesionID: UUID(), fecha: Date(timeIntervalSince1970: 10))
        almacen.referencias = [ReferenciaRendimiento(
            fecha: Date(timeIntervalSince1970: 11), fuente: .test5K,
            distanciaMetros: 5000, segundos: 1500)]

        let datos = try JSONEncoder().encode(almacen)
        let releido = try JSONDecoder().decode(AlmacenV2.self, from: datos)
        XCTAssertEqual(releido, almacen)
        XCTAssertEqual(releido.planActivo!.semanas[0].programados[0].resolucion, .cumplido)
    }

    func testParcialSobreviveSerializacion() throws {
        var (almacen, programadoID) = almacenConProgramado()
        almacen.vincular(sesionID: UUID(), fechaSesion: Date(timeIntervalSince1970: 1),
                         aProgramado: programadoID, completo: false)
        let releido = try JSONDecoder().decode(
            AlmacenV2.self, from: JSONEncoder().encode(almacen))
        XCTAssertEqual(releido.planActivo!.semanas[0].programados[0].resolucion, .parcial)
    }
}

final class MigracionV2Tests: XCTestCase {

    private func planV1() -> Plan {
        var plan = Plan(nombre: "Mi plan", pistas: ["a.mp3", "b.mp3"],
                        avisosFijos: [AvisoFijo(minuto: 30, texto: "gel")],
                        avisosRepetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20,
                                                        hastaMinuto: nil, texto: "agua")])
        plan.tramos = [
            Tramo(nombre: "Calentamiento", kilometros: 2, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
            Tramo(nombre: "Bloque", kilometros: 5, ritmoMinSegKm: 300, ritmoMaxSegKm: 330),
        ]
        plan.avisosKm = [AvisoKm(kilometro: 5, cadaKm: nil, texto: "mitad")]
        return plan
    }

    func testMigracionSeparaAudioDeEntrenamiento() {
        let almacen = MigracionV2.migrar(planV1: planV1(), huellaCumplida: nil,
                                         fecha: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(almacen.audio.pistas, ["a.mp3", "b.mp3"])
        XCTAssertEqual(almacen.audio.avisosFijos.count, 1)
        XCTAssertEqual(almacen.audio.avisosKm.count, 1)

        let programado = almacen.planActivo!.semanas[0].programados[0]
        XCTAssertEqual(programado.definicion.segmentos.count, 2)
        XCTAssertEqual(programado.definicion.segmentos[0].ritmo, .libre)
        XCTAssertEqual(programado.definicion.segmentos[1].ritmo,
                       .absoluto(minSegKm: 300, maxSegKm: 330))
        XCTAssertEqual(programado.resolucion, .pendiente)
        XCTAssertNil(programado.dia)
        XCTAssertFalse(almacen.activado)
    }

    // Puente de huella (se usa en Fase E, del lado del reloj).
    func testHuellaCumplidaMarcaCumplido() {
        let plan = planV1()
        let almacen = MigracionV2.migrar(planV1: plan,
                                         huellaCumplida: plan.huellaEntrenamiento,
                                         fecha: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados[0].resolucion, .cumplido)
        let otra = MigracionV2.migrar(planV1: plan, huellaCumplida: "otra-huella",
                                      fecha: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(otra.planActivo!.semanas[0].programados[0].resolucion, .pendiente)
    }

    func testPlanSinTramosMigraSoloAudio() {
        var plan = planV1()
        plan.tramos = nil
        let almacen = MigracionV2.migrar(planV1: plan, huellaCumplida: nil,
                                         fecha: Date(timeIntervalSince1970: 0))
        XCTAssertNil(almacen.planActivo)
        XCTAssertEqual(almacen.audio.pistas.count, 2)
    }

    // Migrar dos veces: el ensayo se regenera (sin duplicar), y un
    // almacén ACTIVADO no se toca jamás.
    func testMigrarDosVecesNoDuplicaNiPisaActivado() throws {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-migracion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        let url = directorio.appendingPathComponent("dominio-v2.json")

        PlanStore.migrarADominioV2SiHaceFalta(planV1: planV1(), en: url,
                                              fecha: Date(timeIntervalSince1970: 0))
        PlanStore.migrarADominioV2SiHaceFalta(planV1: planV1(), en: url,
                                              fecha: Date(timeIntervalSince1970: 0))
        var almacen = try JSONDecoder().decode(AlmacenV2.self, from: Data(contentsOf: url))
        XCTAssertEqual(almacen.planActivo!.semanas.count, 1)
        XCTAssertEqual(almacen.planActivo!.semanas[0].programados.count, 1)

        // Activado = fuente de verdad: la migración no lo pisa.
        almacen.activado = true
        almacen.planActivo!.nombre = "Fuente de verdad"
        try JSONEncoder().encode(almacen).write(to: url)
        PlanStore.migrarADominioV2SiHaceFalta(planV1: planV1(), en: url,
                                              fecha: Date(timeIntervalSince1970: 99))
        let final = try JSONDecoder().decode(AlmacenV2.self, from: Data(contentsOf: url))
        XCTAssertEqual(final.planActivo!.nombre, "Fuente de verdad")
        try? FileManager.default.removeItem(at: directorio)
    }
}
