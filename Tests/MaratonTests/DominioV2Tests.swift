import XCTest
import UIKit
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

final class ExportacionCompartirTests: XCTestCase {

    // Regresión del bug del logo ausente en el PNG transparente: el
    // nombre fijo hacía que el share sheet sirviera archivos viejos.
    func testNombreDeExportacionUnicoYPNG() {
        let a = CarreraDetalleView.nombreDeExportacion()
        let b = CarreraDetalleView.nombreDeExportacion()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("maratonia-carrera-"))
        XCTAssertTrue(a.hasSuffix(".png"))
    }

    // El asset del logo tiene que existir en el bundle: si se renombra
    // o se pierde, la tarjeta compartible sale sin marca.
    func testLogoExisteEnElBundle() {
        XCTAssertNotNil(UIImage(named: "LogoMaratonia"),
                        "Falta el imageset LogoMaratonia en Assets.xcassets")
    }
}

final class EstructuraYMetadataTests: XCTestCase {

    func testDistanciaTotalYResumen() {
        var definicion = DefinicionEntrenamiento(tipo: .series, nombre: "Series")
        XCTAssertNil(definicion.distanciaTotalKm)
        definicion.segmentos = [
            Segmento(nombre: "Calentamiento", distanciaKm: 2),
            Segmento(nombre: "Bloque", distanciaKm: 5,
                     ritmo: .absoluto(minSegKm: 300, maxSegKm: 330)),
            Segmento(nombre: "Pausa", duracionSegundos: 120),
        ]
        XCTAssertEqual(definicion.distanciaTotalKm, 7)
        XCTAssertEqual(definicion.resumenEstructura, "7 km · 3 segmentos")
    }

    // Puente al motor: absoluto conserva ritmos, libre y simbólico van
    // sin rango (nunca inventar números); desde Fase D los segmentos
    // por duración también son ejecutables (tramos por tiempo).
    func testTramosEjecutables() {
        let definicion = DefinicionEntrenamiento(tipo: .series, nombre: "Mixto", segmentos: [
            Segmento(nombre: "A", distanciaKm: 2),
            Segmento(nombre: "B", distanciaKm: 3, ritmo: .absoluto(minSegKm: 280, maxSegKm: 310)),
            Segmento(nombre: "C", distanciaKm: 1, ritmo: .simbolico(.umbral)),
            Segmento(nombre: "D", duracionSegundos: 120, ritmo: .libre),
            Segmento(nombre: "E"),   // sin ninguna meta: no ejecutable
        ])
        let tramos = definicion.tramosEjecutables
        XCTAssertEqual(tramos.count, 4)
        XCTAssertNil(tramos[0].ritmoMinSegKm)
        XCTAssertEqual(tramos[1].ritmoMinSegKm, 280)
        XCTAssertEqual(tramos[1].ritmoMaxSegKm, 310)
        XCTAssertNil(tramos[2].ritmoMinSegKm)  // simbólico → libre por ahora
        XCTAssertEqual(tramos.map(\.nombre), ["A", "B", "C", "D"])
        XCTAssertTrue(tramos[3].esPorTiempo)
        XCTAssertEqual(tramos[3].duracionSegundos, 120)
    }

    // Un segmento con LAS DOS metas ejecuta por distancia (regla fija).
    func testSegmentoConAmbasMetasPrioridadDistancia() {
        let definicion = DefinicionEntrenamiento(tipo: .facil, nombre: "Ambas", segmentos: [
            Segmento(nombre: "A", distanciaKm: 5, duracionSegundos: 600),
        ])
        let tramos = definicion.tramosEjecutables
        XCTAssertEqual(tramos.count, 1)
        XCTAssertFalse(tramos[0].esPorTiempo)
        XCTAssertEqual(tramos[0].kilometros, 5)
    }

    func testResumenEstructuraConTiempo() {
        let mixto = DefinicionEntrenamiento(tipo: .series, nombre: "Mixto", segmentos: [
            Segmento(nombre: "A", distanciaKm: 6),
            Segmento(nombre: "B", duracionSegundos: 720),
        ])
        XCTAssertEqual(mixto.resumenEstructura, "6 km + 12 min · 2 segmentos")
        let soloTiempo = DefinicionEntrenamiento(tipo: .recuperacion, nombre: "Trote", segmentos: [
            Segmento(nombre: "A", duracionSegundos: 1800),
        ])
        XCTAssertEqual(soloTiempo.resumenEstructura, "30 min · 1 segmento")
        XCTAssertNil(soloTiempo.distanciaTotalKm)
        XCTAssertEqual(soloTiempo.duracionPorTiempoSegundos, 1800)
    }

    func testMetadataProgramadoIDIdaYVuelta() {
        let id = UUID()
        let metadata = MetadatosSesion.metadata(programadoID: id)
        XCTAssertEqual(MetadatosSesion.programadoID(en: metadata), id)
        XCTAssertNil(MetadatosSesion.programadoID(en: nil))
        XCTAssertNil(MetadatosSesion.programadoID(en: ["otra": "cosa"]))
        XCTAssertNil(MetadatosSesion.programadoID(
            en: [MetadatosSesion.claveProgramadoID: "no-es-uuid"]))
    }

    // Editar la definición DESPUÉS de vincular no rompe el historial.
    func testEditarDefinicionConservaVinculo() throws {
        var almacen = AlmacenV2()
        let programado = EntrenamientoProgramado(
            definicion: DefinicionEntrenamiento(tipo: .facil, nombre: "Rodaje"),
            dia: DiaLocal(anio: 2026, mes: 8, dia: 10))
        almacen.planActivo = PlanUsuario(nombre: "P", fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        let sesion = UUID()
        almacen.vincular(sesionID: sesion, fechaSesion: Date(timeIntervalSince1970: 1),
                         aProgramado: programado.id, completo: true)
        almacen.planActivo!.semanas[0].programados[0].definicion.nombre = "Editado"
        let releido = try JSONDecoder().decode(AlmacenV2.self,
                                               from: JSONEncoder().encode(almacen))
        XCTAssertEqual(releido.planActivo!.semanas[0].programados[0].sesionVinculadaID, sesion)
        XCTAssertEqual(releido.planActivo!.semanas[0].programados[0].resolucion, .cumplido)
        XCTAssertEqual(releido.sesiones.first?.vinculoProgramadoID, programado.id)
    }

    // Si HealthKit falla, NADIE llama vincular: el programado queda
    // pendiente también tras serializar (sin cumplidos fantasma).
    func testSinVinculoNoHayCumplidoFantasma() throws {
        var almacen = AlmacenV2()
        let programado = EntrenamientoProgramado(
            definicion: DefinicionEntrenamiento(tipo: .facil, nombre: "Rodaje"),
            dia: DiaLocal(anio: 2026, mes: 8, dia: 10))
        almacen.planActivo = PlanUsuario(nombre: "P", fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        let releido = try JSONDecoder().decode(AlmacenV2.self,
                                               from: JSONEncoder().encode(almacen))
        XCTAssertEqual(releido.planActivo!.semanas[0].programados[0].resolucion, .pendiente)
        XCTAssertNil(releido.planActivo!.semanas[0].programados[0].sesionVinculadaID)
    }
}

final class CatalogoTests: XCTestCase {

    // El JSON embebido decodifica: si un template está roto, esto
    // falla acá y no en la cara del usuario.
    func testCargaDePlanesBase() {
        let planes = Catalogo.planesDisponibles()
        XCTAssertEqual(planes.count, 2)
        XCTAssertEqual(planes[0].id, "primeros-5k")
        XCTAssertEqual(planes[0].planBaseID, "primeros-5k@1")
        XCTAssertEqual(planes[0].semanas.count, planes[0].semanasTotales)
        XCTAssertEqual(planes[1].planBaseID, "10k-continuo@1")
        XCTAssertEqual(planes[1].semanas.count, 8)
        XCTAssertTrue(planes.allSatisfy(\.provisional))
        // Cada semana respeta los días declarados y ningún día se sale de 1...7.
        for plan in planes {
            for semana in plan.semanas {
                XCTAssertEqual(semana.entrenamientos.count, plan.diasPorSemana)
                XCTAssertTrue(semana.entrenamientos.allSatisfy { (1...7).contains($0.diaDeSemana) })
            }
        }
    }
}

final class AdopcionTests: XCTestCase {

    private var base: PlanBase { Catalogo.planesDisponibles()[0] }
    private let adopcion = Date(timeIntervalSince1970: 0)

    func testSnapshotConIDsNuevosYProcedencia() {
        let a = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10), fechaAdopcion: adopcion)
        let b = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10), fechaAdopcion: adopcion)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.semanas[0].programados[0].id, b.semanas[0].programados[0].id)
        XCTAssertEqual(a.origen, .catalogo(planBaseID: "primeros-5k@1"))
        XCTAssertEqual(a.semanas.count, base.semanasTotales)
    }

    // Modificar el template DESPUÉS de adoptar no toca la instancia.
    func testTemplateNoMutaInstancia() {
        var template = base
        let usuario = template.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10),
                                       fechaAdopcion: adopcion)
        template.semanas[0].entrenamientos[0].nombre = "CAMBIADO"
        template.version = 99
        XCTAssertEqual(usuario.semanas[0].programados[0].definicion.nombre,
                       "Caminata y trote 1")
        XCTAssertEqual(usuario.origen, .catalogo(planBaseID: "primeros-5k@1"))
    }

    // Fechas determinísticas: inicio lunes 10/8 → días 1/3/5 de la
    // semana 1 caen 10, 12 y 14; semana 2 arranca el 17.
    func testFechasDeterministicas() {
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10),
                                fechaAdopcion: adopcion)
        let dias1 = plan.semanas[0].programados.map(\.dia)
        XCTAssertEqual(dias1, [DiaLocal(anio: 2026, mes: 8, dia: 10),
                               DiaLocal(anio: 2026, mes: 8, dia: 12),
                               DiaLocal(anio: 2026, mes: 8, dia: 14)])
        XCTAssertEqual(plan.semanas[1].programados[0].dia, DiaLocal(anio: 2026, mes: 8, dia: 17))
    }

    // Cruce de mes: inicio 30/8 → el día 3 de la semana 1 es 1/9.
    func testFechasCruzanMes() {
        let plan = base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 30),
                                fechaAdopcion: adopcion)
        XCTAssertEqual(plan.semanas[0].programados[1].dia, DiaLocal(anio: 2026, mes: 9, dia: 1))
        XCTAssertEqual(plan.semanas[1].programados[0].dia, DiaLocal(anio: 2026, mes: 9, dia: 6))
    }

    func testRoundTripConOrigenDeCatalogo() throws {
        var almacen = AlmacenV2()
        almacen.adoptarPlan(base.adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10),
                                         fechaAdopcion: adopcion))
        almacen.adoptarPlan(Catalogo.planesDisponibles()[1]
            .adoptar(inicio: DiaLocal(anio: 2026, mes: 9, dia: 7), fechaAdopcion: adopcion))
        let releido = try JSONDecoder().decode(AlmacenV2.self,
                                               from: JSONEncoder().encode(almacen))
        XCTAssertEqual(releido, almacen)
        XCTAssertEqual(releido.historialDePlanes.count, 1)  // el 5K quedó archivado
        XCTAssertEqual(releido.planActivo?.nombre, "Rumbo a 10K")
    }
}

final class HoyTests: XCTestCase {

    private func almacenConPlan(inicio: DiaLocal) -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.adoptarPlan(Catalogo.planesDisponibles()[0]
            .adoptar(inicio: inicio, fechaAdopcion: Date(timeIntervalSince1970: 0)))
        return almacen
    }

    func testHayUnoHoy() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 12)
        let almacen = almacenConPlan(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10))
        XCTAssertEqual(almacen.entrenamientoDeHoy(hoy)?.definicion.nombre, "Caminata y trote 2")
    }

    func testNingunoHoy() {
        let almacen = almacenConPlan(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10))
        XCTAssertNil(almacen.entrenamientoDeHoy(DiaLocal(anio: 2026, mes: 8, dia: 11)))
    }

    // Un vencido de ayer NO es "hoy" (se lista aparte, sin arrastres).
    func testVencidoAnteriorNoEsHoy() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 11)
        let almacen = almacenConPlan(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10))
        XCTAssertNil(almacen.entrenamientoDeHoy(hoy))
        XCTAssertEqual(almacen.vencidos(hoy).count, 1)
    }

    // Cumplido hoy → ya no "toca" (no aparece como pendiente).
    func testCumplidoHoyNoAparece() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)
        var almacen = almacenConPlan(inicio: hoy)
        let programado = almacen.entrenamientoDeHoy(hoy)!
        almacen.vincular(sesionID: UUID(), fechaSesion: Date(timeIntervalSince1970: 1),
                         aProgramado: programado.id, completo: true)
        XCTAssertNil(almacen.entrenamientoDeHoy(hoy))
        XCTAssertEqual(almacen.vencidos(hoy).count, 0)
    }

    func testProximosOrdenadosYLimitados() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)
        let almacen = almacenConPlan(inicio: hoy)
        let proximos = almacen.proximosEntrenamientos(despuesDe: hoy, maximo: 3)
        XCTAssertEqual(proximos.count, 3)
        XCTAssertEqual(proximos[0].dia, DiaLocal(anio: 2026, mes: 8, dia: 12))
        XCTAssertEqual(proximos[1].dia, DiaLocal(anio: 2026, mes: 8, dia: 14))
        XCTAssertEqual(proximos[2].dia, DiaLocal(anio: 2026, mes: 8, dia: 17))
    }
}

final class CutoverTests: XCTestCase {

    private func directorioTemporal() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cutover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func planLegacy() -> Plan {
        var plan = Plan(nombre: "Legacy", pistas: ["x.mp3"], avisosFijos: [], avisosRepetidos: [])
        plan.tramos = [Tramo(nombre: "Bloque", kilometros: 5,
                             ritmoMinSegKm: 300, ritmoMaxSegKm: 330)]
        return plan
    }

    // Usuario existente: ensayo de Fase A → cutover → activado, y el
    // snapshot pasa a ser el PlanUsuario real sin perder nada.
    func testUsuarioExistenteHaceCutoverUnaVez() throws {
        let dir = try directorioTemporal()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urlV2 = dir.appendingPathComponent("dominio-v2.json")
        let urlLegacy = dir.appendingPathComponent("plan.json")
        try JSONEncoder().encode(planLegacy()).write(to: urlLegacy)
        PlanStore.migrarADominioV2SiHaceFalta(planV1: planLegacy(), en: urlV2,
                                              fecha: Date(timeIntervalSince1970: 0))

        let almacen = AlmacenStore.cargarConCutover(urlV2: urlV2, urlLegacy: urlLegacy,
                                                    fecha: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(almacen.activado)
        XCTAssertEqual(almacen.planActivo?.nombre, "Legacy")
        XCTAssertEqual(almacen.audio.pistas, ["x.mp3"])

        // La migración de ensayo YA NO pisa el almacén activado…
        PlanStore.migrarADominioV2SiHaceFalta(planV1: Plan.vacio, en: urlV2,
                                              fecha: Date(timeIntervalSince1970: 2))
        // …y el segundo arranque carga lo mismo, sin re-migrar.
        let segundo = AlmacenStore.cargarConCutover(urlV2: urlV2, urlLegacy: urlLegacy,
                                                    fecha: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(segundo, almacen)
    }

    // Las mutaciones post-cutover sobreviven a los arranques siguientes.
    func testMutacionesSobrevivenArranques() throws {
        let dir = try directorioTemporal()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urlV2 = dir.appendingPathComponent("dominio-v2.json")
        let urlLegacy = dir.appendingPathComponent("plan.json")

        var almacen = AlmacenStore.cargarConCutover(urlV2: urlV2, urlLegacy: urlLegacy,
                                                    fecha: Date(timeIntervalSince1970: 0))
        almacen.adoptarPlan(Catalogo.planesDisponibles()[0]
            .adoptar(inicio: DiaLocal(anio: 2026, mes: 8, dia: 10),
                     fechaAdopcion: Date(timeIntervalSince1970: 1)))
        try JSONEncoder().encode(almacen).write(to: urlV2)

        let releido = AlmacenStore.cargarConCutover(urlV2: urlV2, urlLegacy: urlLegacy,
                                                    fecha: Date(timeIntervalSince1970: 9))
        XCTAssertEqual(releido.planActivo?.nombre, "Primeros 5K")
    }

    // Usuario nuevo sin legacy: almacén limpio, sin entidades basura.
    func testUsuarioNuevoSinLegacy() throws {
        let dir = try directorioTemporal()
        defer { try? FileManager.default.removeItem(at: dir) }
        let almacen = AlmacenStore.cargarConCutover(
            urlV2: dir.appendingPathComponent("dominio-v2.json"),
            urlLegacy: dir.appendingPathComponent("plan.json"),
            fecha: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(almacen.activado)
        XCTAssertNil(almacen.planActivo)
        XCTAssertTrue(almacen.historialDePlanes.isEmpty)
        XCTAssertTrue(almacen.sesiones.isEmpty)
    }

    // Sin ensayo pero con legacy (orden de arranque invertido): migra
    // directo del legacy igual de bien.
    func testCutoverSinEnsayoMigraDelLegacy() throws {
        let dir = try directorioTemporal()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urlLegacy = dir.appendingPathComponent("plan.json")
        try JSONEncoder().encode(planLegacy()).write(to: urlLegacy)
        let almacen = AlmacenStore.cargarConCutover(
            urlV2: dir.appendingPathComponent("dominio-v2.json"),
            urlLegacy: urlLegacy, fecha: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(almacen.activado)
        XCTAssertEqual(almacen.planActivo?.nombre, "Legacy")
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
