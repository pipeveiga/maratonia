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

/// Identidad de los objetos del DOMINIO (programados, snapshots): que
/// editar contenido o reprogramar no cambie el ID. Distinto de
/// IdentidadCuentaTests, que prueba la identidad del USUARIO.
final class IdentidadDominioTests: XCTestCase {

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
        // Un entrenamiento mixto informa AMBAS medidas (Fase D): la
        // distancia y la parte por tiempo. La expectativa se arma con
        // los mismos helpers para no depender del idioma del runner.
        // OJO: resumenEstructura arma "segmentos" con un literal en
        // español (no pasa por el catálogo) — por eso acá va literal.
        // Hueco de localización conocido, anotado en el informe.
        XCTAssertEqual(definicion.resumenEstructura, "7 km + 2 min · 3 segmentos")
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

// MARK: - Fase E: proyección del día y resultados del reloj

final class FaseETests: XCTestCase {

    private func definicion() -> DefinicionEntrenamiento {
        DefinicionEntrenamiento(tipo: .facil, nombre: "Rodaje", segmentos: [
            Segmento(nombre: "Rodaje", distanciaKm: 5),
        ])
    }

    private func almacenConPlan(dia: DiaLocal) -> (AlmacenV2, UUID) {
        var almacen = AlmacenV2()
        almacen.activado = true
        let programado = EntrenamientoProgramado(definicion: definicion(), dia: dia)
        almacen.planActivo = PlanUsuario(nombre: "Plan", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        return (almacen, programado.id)
    }

    private func storeDePrueba(_ almacen: AlmacenV2) -> AlmacenStore {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-fase-e-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        let url = directorio.appendingPathComponent("dominio-v2.json")
        try? JSONEncoder().encode(almacen).write(to: url)
        return AlmacenStore(url: url,
                            urlLegacy: directorio.appendingPathComponent("plan.json"),
                            conectadoAlReloj: false)
    }

    func testProyeccionVigenciaPorDiaYVersion() {
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 9)
        var proyeccion = ProyeccionDia(generadaEl: Date(), dia: hoy)
        XCTAssertTrue(proyeccion.vigente(hoy: hoy))
        XCTAssertFalse(proyeccion.vigente(hoy: DiaLocal(anio: 2026, mes: 8, dia: 10)))
        // Versión del futuro: se ignora en vez de malinterpretarse.
        proyeccion.version = ProyeccionDia.versionActual + 1
        XCTAssertFalse(proyeccion.vigente(hoy: hoy))
    }

    func testProyeccionDeHoyConYSinEntrenamiento() {
        let hoy = DiaLocal(fecha: Date())
        let (almacen, id) = almacenConPlan(dia: hoy)
        let store = storeDePrueba(almacen)
        let proyeccion = store.proyeccionDeHoy()
        XCTAssertEqual(proyeccion.programadoID, id)
        XCTAssertEqual(proyeccion.definicion?.nombre, "Rodaje")
        XCTAssertEqual(proyeccion.dia, hoy)

        // Día sin entrenamiento: proyección "vacía" pero con el día —
        // el reloj se entera de que hoy no hay nada pendiente.
        let (sinHoy, _) = almacenConPlan(dia: hoy.sumando(dias: 3))
        let storeVacio = storeDePrueba(sinHoy)
        let vacia = storeVacio.proyeccionDeHoy()
        XCTAssertNil(vacia.programadoID)
        XCTAssertNil(vacia.definicion)
        XCTAssertEqual(vacia.dia, hoy)
    }

    func testResultadoVinculaYEsIdempotente() {
        let hoy = DiaLocal(fecha: Date())
        let (almacen, id) = almacenConPlan(dia: hoy)
        let store = storeDePrueba(almacen)
        let sesion = UUID()
        let resultado = ResultadoSesionWatch(sesionID: sesion, fecha: Date(),
                                             programadoID: id, estructuraCompleta: true)
        store.procesar(resultado: resultado)
        XCTAssertEqual(store.almacen.todosLosProgramados[0].resolucion, .cumplido)
        XCTAssertEqual(store.almacen.todosLosProgramados[0].sesionVinculadaID, sesion)
        XCTAssertEqual(store.almacen.sesiones.count, 1)

        // La cola de WC puede reentregar: nada se duplica ni cambia.
        store.procesar(resultado: resultado)
        XCTAssertEqual(store.almacen.sesiones.count, 1)
        XCTAssertEqual(store.almacen.todosLosProgramados[0].resolucion, .cumplido)
    }

    func testResultadoParcial() {
        let hoy = DiaLocal(fecha: Date())
        let (almacen, id) = almacenConPlan(dia: hoy)
        let store = storeDePrueba(almacen)
        store.procesar(resultado: ResultadoSesionWatch(sesionID: UUID(), fecha: Date(),
                                                       programadoID: id,
                                                       estructuraCompleta: false))
        XCTAssertEqual(store.almacen.todosLosProgramados[0].resolucion, .parcial)
    }

    func testResultadoConProgramadoDesconocidoSeRegistraLibre() {
        // El plan cambió mientras el reloj estaba offline: la evidencia
        // no se tira — queda como carrera libre.
        let (almacen, _) = almacenConPlan(dia: DiaLocal(fecha: Date()))
        let store = storeDePrueba(almacen)
        let sesion = UUID()
        store.procesar(resultado: ResultadoSesionWatch(sesionID: sesion, fecha: Date(),
                                                       programadoID: UUID(),
                                                       estructuraCompleta: true))
        XCTAssertEqual(store.almacen.todosLosProgramados[0].resolucion, .pendiente)
        XCTAssertEqual(store.almacen.sesiones.count, 1)
        XCTAssertTrue(store.almacen.sesiones[0].esLibre)
        XCTAssertEqual(store.almacen.sesiones[0].id, sesion)
    }

    func testResultadoTardioNoPisaVinculoExistente() {
        // Corriste el programado desde el iPhone; DESPUÉS llega un
        // resultado viejo del reloj para el mismo programado: no roba
        // el vínculo — se registra libre.
        let hoy = DiaLocal(fecha: Date())
        let (almacen, id) = almacenConPlan(dia: hoy)
        let store = storeDePrueba(almacen)
        let sesionTelefono = UUID()
        store.almacen.vincular(sesionID: sesionTelefono, fechaSesion: Date(),
                               aProgramado: id, completo: true)

        let sesionReloj = UUID()
        store.procesar(resultado: ResultadoSesionWatch(sesionID: sesionReloj, fecha: Date(),
                                                       programadoID: id,
                                                       estructuraCompleta: true))
        XCTAssertEqual(store.almacen.todosLosProgramados[0].sesionVinculadaID, sesionTelefono)
        XCTAssertEqual(store.almacen.sesiones.count, 2)
        XCTAssertTrue(store.almacen.sesiones.first { $0.id == sesionReloj }!.esLibre)
    }

    func testResultadoLibreSeRegistraLibre() {
        let (almacen, _) = almacenConPlan(dia: DiaLocal(fecha: Date()))
        let store = storeDePrueba(almacen)
        store.procesar(resultado: ResultadoSesionWatch(sesionID: UUID(), fecha: Date(),
                                                       programadoID: nil,
                                                       estructuraCompleta: false))
        XCTAssertEqual(store.almacen.sesiones.count, 1)
        XCTAssertTrue(store.almacen.sesiones[0].esLibre)
    }

    func testProtocoloCodableIdaYVuelta() throws {
        let proyeccion = ProyeccionDia(generadaEl: Date(timeIntervalSince1970: 100),
                                       dia: DiaLocal(anio: 2026, mes: 8, dia: 9),
                                       programadoID: UUID(),
                                       definicion: definicion(),
                                       nombrePlan: "Primeros 5K")
        let datos = try JSONEncoder().encode(proyeccion)
        XCTAssertEqual(try JSONDecoder().decode(ProyeccionDia.self, from: datos), proyeccion)

        let resultado = ResultadoSesionWatch(sesionID: UUID(),
                                             fecha: Date(timeIntervalSince1970: 200),
                                             programadoID: nil,
                                             estructuraCompleta: true)
        let datos2 = try JSONEncoder().encode(resultado)
        XCTAssertEqual(try JSONDecoder().decode(ResultadoSesionWatch.self, from: datos2), resultado)
    }
}

// MARK: - Fase F: perfil deportivo y referencias

final class FaseFTests: XCTestCase {

    func testAlmacenViejoSinPerfilDecodifica() throws {
        // dominio-v2.json escrito ANTES de Fase F (sin campo perfil):
        // tiene que seguir cargando — el onboarding es aditivo.
        var viejo = AlmacenV2()
        viejo.activado = true
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(viejo)) as! [String: Any]
        json.removeValue(forKey: "perfil")
        let datos = try JSONSerialization.data(withJSONObject: json)
        let cargado = try JSONDecoder().decode(AlmacenV2.self, from: datos)
        XCTAssertNil(cargado.perfil)
        XCTAssertNil(cargado.perfilDeportivo.objetivo)
        XCTAssertFalse(cargado.perfilDeportivo.testPendiente)
    }

    func testRegistrarReferenciaEsIdempotentePorContenido() {
        var almacen = AlmacenV2()
        let fecha = Date(timeIntervalSince1970: 1000)
        let marca = ReferenciaRendimiento(fecha: fecha, fuente: .marcaManual,
                                          distanciaMetros: 5000, segundos: 1500)
        almacen.registrarReferencia(marca)
        almacen.registrarReferencia(marca)   // reintento del onboarding
        XCTAssertEqual(almacen.referencias.count, 1)

        // Otra marca del mismo día con distinto tiempo SÍ entra.
        almacen.registrarReferencia(ReferenciaRendimiento(
            fecha: fecha, fuente: .marcaManual, distanciaMetros: 5000, segundos: 1499))
        XCTAssertEqual(almacen.referencias.count, 2)
    }

    func testReferenciaVigenteEsLaMasReciente() {
        var almacen = AlmacenV2()
        almacen.registrarReferencia(ReferenciaRendimiento(
            fecha: Date(timeIntervalSince1970: 5000), fuente: .test5K,
            distanciaMetros: 5000, segundos: 1400))   // más nueva, más lenta
        almacen.registrarReferencia(ReferenciaRendimiento(
            fecha: Date(timeIntervalSince1970: 1000), fuente: .marcaManual,
            distanciaMetros: 5000, segundos: 1200))   // vieja, más rápida
        // Gana la MÁS RECIENTE (estado actual), no la mejor histórica.
        XCTAssertEqual(almacen.referenciaVigente?.segundos, 1400)
        XCTAssertEqual(almacen.referenciaVigente?.fuente, .test5K)
    }

    func testResultadoDeTestRegistraYApagaPendiente() {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-fase-f-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        var inicial = AlmacenV2()
        inicial.activado = true
        inicial.perfil = PerfilDeportivo(objetivo: .mejorar5K, testPendiente: true)
        let url = directorio.appendingPathComponent("dominio-v2.json")
        try? JSONEncoder().encode(inicial).write(to: url)

        let store = AlmacenStore(url: url,
                                 urlLegacy: directorio.appendingPathComponent("plan.json"),
                                 conectadoAlReloj: false)
        store.registrarResultadoDeTest(distanciaMetros: 5000, segundos: 1450,
                                       fecha: Date(timeIntervalSince1970: 7000))
        XCTAssertEqual(store.almacen.referencias.count, 1)
        XCTAssertEqual(store.almacen.referencias[0].fuente, .test5K)
        XCTAssertEqual(store.almacen.perfilDeportivo.testPendiente, false)

        // Reentrega del mismo resultado: idempotente.
        store.registrarResultadoDeTest(distanciaMetros: 5000, segundos: 1450,
                                       fecha: Date(timeIntervalSince1970: 7000))
        XCTAssertEqual(store.almacen.referencias.count, 1)
        try? FileManager.default.removeItem(at: directorio)
    }

    func testOnboardingEsAditivo() {
        // Un usuario CON plan y sesiones hace el onboarding: nada de lo
        // suyo se toca.
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-fase-f-adit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        var inicial = AlmacenV2()
        inicial.activado = true
        inicial.planActivo = PlanUsuario(nombre: "Mi plan", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [])
        inicial.sesiones = [RegistroSesion(id: UUID(), fecha: Date(), vinculoProgramadoID: nil)]
        inicial.audio.pistas = ["a.mp3"]
        let url = directorio.appendingPathComponent("dominio-v2.json")
        try? JSONEncoder().encode(inicial).write(to: url)

        let store = AlmacenStore(url: url,
                                 urlLegacy: directorio.appendingPathComponent("plan.json"),
                                 conectadoAlReloj: false)
        let perfil = PerfilDeportivo(objetivo: .diez, diasPorSemana: 3,
                                     fechaObjetivo: nil, fechaOnboarding: Date())
        store.guardarOnboarding(perfil, marca: ReferenciaRendimiento(
            fecha: Date(timeIntervalSince1970: 500), fuente: .marcaManual,
            distanciaMetros: 10000, segundos: 3300))

        XCTAssertEqual(store.almacen.perfilDeportivo.objetivo, .diez)
        XCTAssertEqual(store.almacen.referencias.count, 1)
        XCTAssertEqual(store.almacen.planActivo?.nombre, "Mi plan")
        XCTAssertEqual(store.almacen.sesiones.count, 1)
        XCTAssertEqual(store.almacen.audio.pistas, ["a.mp3"])
        try? FileManager.default.removeItem(at: directorio)
    }
}

// MARK: - Fase G (infraestructura): baseline, metodologías, Riegel

final class FaseGTests: XCTestCase {

    func testBaselineDerivaDeReferenciaConLinaje() {
        let referencia = ReferenciaRendimiento(fecha: Date(timeIntervalSince1970: 100),
                                               fuente: .test5K,
                                               distanciaMetros: 5000, segundos: 1500)
        let baseline = PerformanceBaseline(referencia: referencia)
        XCTAssertEqual(baseline?.referenciaID, referencia.id)
        XCTAssertEqual(baseline?.fuente, .test5K)
        XCTAssertEqual(baseline?.ritmoSegKm, 300)   // 25:00 al 5K = 5:00/km

        XCTAssertNil(PerformanceBaseline(referencia: nil))
        XCTAssertNil(PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: Date(), fuente: .marcaManual, distanciaMetros: 0, segundos: 100)))
    }

    func testMetodologiaActivaResuelveYSinBaselineQuedaPendiente() {
        // Desde el build 53 hay metodología activa (maratonia@1, con
        // fuentes citadas en METODOLOGIA.md). La regla dura sigue en
        // pie por el otro lado: SIN baseline no se inventa nada.
        XCTAssertNotNil(Metodologias.activa)
        let baseline = PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: Date(), fuente: .test5K, distanciaMetros: 5000, segundos: 1500))
        if case .pendiente = Metodologias.resolver(.umbral, baseline: baseline) {
            XCTFail("con baseline válido el umbral debe resolverse")
        }
        XCTAssertEqual(Metodologias.resolver(.facil, baseline: nil), .pendiente(.facil))
    }

    func testRiegelValoresConocidos() {
        // 5K en 25:00 → 10K ≈ 25:00 × 2^1.06 = 52:07 (3127 s).
        XCTAssertEqual(Riegel.tiempoEquivalente(segundos: 1500, deMetros: 5000,
                                                aMetros: 10000), 3127)
        // Identidad: misma distancia, mismo tiempo.
        XCTAssertEqual(Riegel.tiempoEquivalente(segundos: 1500, deMetros: 5000,
                                                aMetros: 5000), 1500)
        // Hacia abajo: 10K en 52:07 → 5K ≈ 25:00 (redondeo ±1 s).
        let cincoK = Riegel.tiempoEquivalente(segundos: 3127, deMetros: 10000, aMetros: 5000)!
        XCTAssertLessThanOrEqual(abs(cincoK - 1500), 1)
    }

    func testRiegelRechazaExtrapolacionesAbusivas() {
        // 5K → maratón es factor 8.4x: fuera del rango honesto.
        XCTAssertNil(Riegel.tiempoEquivalente(segundos: 1500, deMetros: 5000,
                                              aMetros: 42195))
        XCTAssertNil(Riegel.tiempoEquivalente(segundos: 1500, deMetros: 5000, aMetros: 1000))
        XCTAssertNil(Riegel.tiempoEquivalente(segundos: 0, deMetros: 5000, aMetros: 10000))
        // 21K → 42K (factor 2) sí.
        XCTAssertNotNil(Riegel.tiempoEquivalente(segundos: 6600, deMetros: 21097.5,
                                                 aMetros: 42195))
    }
}

// MARK: - Progreso v1 (lógica pura)

final class CalculoProgresoTests: XCTestCase {

    /// Calendario FIJO (semana arranca lunes) para que el test no
    /// dependa del locale de la máquina.
    private var calendario: Calendar = {
        var calendario = Calendar(identifier: .gregorian)
        calendario.firstWeekday = 2
        return calendario
    }()

    private func fecha(_ dia: Int, _ mes: Int, _ anio: Int, hora: Int = 12) -> Date {
        calendario.date(from: DateComponents(year: anio, month: mes, day: dia, hour: hora))!
    }

    func testSemanasIncluyeLasVacias() {
        // Lunes 10/8/2026. Semanas (lunes a domingo):
        // idx0 = 20-26/7 · idx1 = 27/7-2/8 · idx2 = 3-9/8 · idx3 = 10-16/8
        let hoy = fecha(10, 8, 2026)
        let sesiones = [
            SesionMetrica(fecha: hoy, metros: 5000, segundos: 1500),           // idx3
            SesionMetrica(fecha: fecha(9, 8, 2026), metros: 3000, segundos: 1000),  // domingo, idx2
            SesionMetrica(fecha: fecha(20, 7, 2026), metros: 8000, segundos: 2400), // idx0
        ]
        let semanas = CalculoProgreso.semanas(sesiones: sesiones, cuantas: 4,
                                              hoy: hoy, calendario: calendario)
        XCTAssertEqual(semanas.count, 4)
        XCTAssertEqual(semanas.map(\.carreras), [1, 0, 1, 1])  // la vacía existe con cero
        XCTAssertEqual(semanas[0].metros, 8000)
        XCTAssertEqual(semanas[3].metros, 5000)
        // Orden: más vieja primero, la actual al final.
        XCTAssertLessThan(semanas[0].inicio, semanas[3].inicio)
        // Una sesión fuera de la ventana no aparece.
        let corta = CalculoProgreso.semanas(sesiones: sesiones, cuantas: 2,
                                            hoy: hoy, calendario: calendario)
        XCTAssertEqual(corta.reduce(0) { $0 + $1.carreras }, 2)
    }

    func testRachaNoSeCortaPorLaSemanaActualVacia() {
        let hoy = fecha(10, 8, 2026)   // lunes: semana actual recién arranca
        // 3 semanas corridas, la actual todavía sin carreras.
        let sesiones = [
            SesionMetrica(fecha: fecha(3, 8, 2026), metros: 5000, segundos: 1500),
            SesionMetrica(fecha: fecha(27, 7, 2026), metros: 5000, segundos: 1500),
            SesionMetrica(fecha: fecha(20, 7, 2026), metros: 5000, segundos: 1500),
        ]
        let semanas = CalculoProgreso.semanas(sesiones: sesiones, cuantas: 6,
                                              hoy: hoy, calendario: calendario)
        XCTAssertEqual(CalculoProgreso.rachaSemanas(semanas), 3)

        // Un agujero de una semana ANTES sí corta.
        let conAgujero = [
            SesionMetrica(fecha: fecha(3, 8, 2026), metros: 5000, segundos: 1500),
            SesionMetrica(fecha: fecha(13, 7, 2026), metros: 5000, segundos: 1500),
        ]
        let semanas2 = CalculoProgreso.semanas(sesiones: conAgujero, cuantas: 6,
                                               hoy: hoy, calendario: calendario)
        XCTAssertEqual(CalculoProgreso.rachaSemanas(semanas2), 1)
    }

    func testCumplimientoSoloCuentaVencidosOHoy() {
        var almacen = AlmacenV2()
        let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)
        let definicion = DefinicionEntrenamiento(tipo: .facil, nombre: "R", segmentos: [])
        var cumplido = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: -3))
        cumplido.resolucion = .cumplido
        var parcial = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: -2))
        parcial.resolucion = .parcial
        let vencido = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: -1))
        let hoyPendiente = EntrenamientoProgramado(definicion: definicion, dia: hoy)
        let futuro = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: 2))
        let sinFecha = EntrenamientoProgramado(definicion: definicion, dia: nil)
        almacen.planActivo = PlanUsuario(
            nombre: "P", origen: .personalizado, fechaAdopcion: Date(timeIntervalSince1970: 0),
            semanas: [SemanaPlan(numero: 1,
                                 programados: [cumplido, parcial, vencido, hoyPendiente,
                                               futuro, sinFecha])])
        let (hechos, total) = CalculoProgreso.cumplimiento(almacen: almacen, hoy: hoy)
        XCTAssertEqual(hechos, 2)   // cumplido + parcial
        // El futuro, el sin-fecha y el PENDIENTE DE HOY no cuentan
        // (hoy a la mañana no es deuda); el de hoy entra al resolverse.
        XCTAssertEqual(total, 3)
        var almacen2 = almacen
        almacen2.planActivo!.semanas[0].programados[3].resolucion = .cumplido
        let (hechos2, total2) = CalculoProgreso.cumplimiento(almacen: almacen2, hoy: hoy)
        XCTAssertEqual(hechos2, 3)
        XCTAssertEqual(total2, 4)
    }

    func testDestacadosIgnoraSprintsCortos() {
        let sesiones = [
            SesionMetrica(fecha: Date(), metros: 200, segundos: 40),      // sprint: afuera
            SesionMetrica(fecha: Date(), metros: 5000, segundos: 1500),   // 5:00/km
            SesionMetrica(fecha: Date(), metros: 12000, segundos: 4200),  // 5:50/km, más larga
        ]
        let (masLarga, mejorRitmo) = CalculoProgreso.destacados(sesiones)
        XCTAssertEqual(masLarga?.metros, 12000)
        XCTAssertEqual(mejorRitmo?.metros, 5000)
        let vacio = CalculoProgreso.destacados([])
        XCTAssertNil(vacio.masLarga)
        XCTAssertNil(vacio.mejorRitmo)
    }
}

// MARK: - Build 39, bug 2: estado post-entrenamiento en el reloj

final class EstadoPostEntrenamientoWatchTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)

    private func definicion() -> DefinicionEntrenamiento {
        DefinicionEntrenamiento(tipo: .facil, nombre: "Rodaje", segmentos: [
            Segmento(nombre: "Rodaje", distanciaKm: 5),
        ])
    }

    func testProyeccionLlevaElResultadoDeHoyResuelto() {
        // iPhone: el programado de hoy quedó parcial → la proyección
        // deja de ofrecerlo y lleva el RESULTADO.
        var almacen = AlmacenV2()
        almacen.activado = true
        var programado = EntrenamientoProgramado(definicion: definicion(), dia: hoy)
        programado.resolucion = .parcial
        almacen.planActivo = PlanUsuario(nombre: "Plan", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-b39-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        let url = directorio.appendingPathComponent("dominio-v2.json")
        try? JSONEncoder().encode(almacen).write(to: url)
        let store = AlmacenStore(url: url,
                                 urlLegacy: directorio.appendingPathComponent("plan.json"),
                                 conectadoAlReloj: false)

        let proyeccion = store.proyeccionDeHoy(fecha: hoy.fecha()!)
        XCTAssertNil(proyeccion.programadoID)      // ya no se ofrece
        XCTAssertNil(proyeccion.definicion)
        XCTAssertEqual(proyeccion.resolucionDeHoy, .parcial)
        XCTAssertEqual(proyeccion.nombreDeHoy, "Rodaje")
        XCTAssertEqual(proyeccion.tipoDeHoy, .facil)

        // Con el programado PENDIENTE, los campos de resultado van vacíos.
        var pendiente = almacen
        pendiente.planActivo!.semanas[0].programados[0].resolucion = .pendiente
        try? JSONEncoder().encode(pendiente).write(to: url)
        let store2 = AlmacenStore(url: url,
                                  urlLegacy: directorio.appendingPathComponent("plan.json"),
                                  conectadoAlReloj: false)
        let proyeccion2 = store2.proyeccionDeHoy(fecha: hoy.fecha()!)
        XCTAssertNotNil(proyeccion2.programadoID)
        XCTAssertNil(proyeccion2.resolucionDeHoy)
        try? FileManager.default.removeItem(at: directorio)
    }

    func testHomeDelRelojNoOfreceDosVecesElMismoProgramado() {
        // Proyección con pendiente; el reloj YA lo corrió localmente:
        // no se ofrece de nuevo y se muestra el resultado local.
        let id = UUID()
        let proyeccion = ProyeccionDia(generadaEl: Date(), dia: hoy,
                                       programadoID: id, definicion: definicion(),
                                       nombrePlan: "Plan")
        // Antes de correr: se ofrece, no hay resultado.
        XCTAssertNotNil(proyeccion.entrenamientoOfrecible(hoy: hoy, completadosLocal: []))
        XCTAssertNil(proyeccion.resultadoDeHoy(hoy: hoy, completadosLocal: [],
                                               estructuraLocal: [:]))
        // Después de correrlo (parcial, local): no se ofrece; resultado ◐.
        XCTAssertNil(proyeccion.entrenamientoOfrecible(hoy: hoy, completadosLocal: [id]))
        let parcial = proyeccion.resultadoDeHoy(hoy: hoy, completadosLocal: [id],
                                                estructuraLocal: [id: false])
        XCTAssertEqual(parcial?.nombre, "Rodaje")
        XCTAssertEqual(parcial?.resolucion, .parcial)
        // Estructura completa local → ✓ Completado.
        let completo = proyeccion.resultadoDeHoy(hoy: hoy, completadosLocal: [id],
                                                 estructuraLocal: [id: true])
        XCTAssertEqual(completo?.resolucion, .cumplido)
    }

    func testElIPhoneManda_SobreElEstadoLocal() {
        // Cuando la proyección YA trae la resolución del iPhone, esa
        // gana sobre lo local (el iPhone es el dueño del calendario).
        let id = UUID()
        var proyeccion = ProyeccionDia(generadaEl: Date(), dia: hoy,
                                       programadoID: nil, definicion: nil,
                                       nombrePlan: "Plan")
        proyeccion.resolucionDeHoy = .cumplido
        proyeccion.nombreDeHoy = "Rodaje"
        let resultado = proyeccion.resultadoDeHoy(hoy: hoy, completadosLocal: [id],
                                                  estructuraLocal: [id: false])
        XCTAssertEqual(resultado?.resolucion, .cumplido)
    }

    func testResultadoDeAyerNoContamina() {
        // La proyección de AYER con resultado no muestra nada hoy.
        var proyeccion = ProyeccionDia(generadaEl: Date(),
                                       dia: hoy.sumando(dias: -1),
                                       programadoID: nil, definicion: nil,
                                       nombrePlan: "Plan")
        proyeccion.resolucionDeHoy = .cumplido
        proyeccion.nombreDeHoy = "Rodaje"
        XCTAssertNil(proyeccion.resultadoDeHoy(hoy: hoy, completadosLocal: [],
                                               estructuraLocal: [:]))
    }

    func testProyeccionViejaSinCamposNuevosDecodifica() throws {
        // Un iPhone build 38 manda la proyección SIN los campos de
        // resultado: el reloj 39 la decodifica igual (retrocompatible,
        // misma versión de esquema).
        let vieja = ProyeccionDia(generadaEl: Date(timeIntervalSince1970: 50),
                                  dia: hoy, programadoID: UUID(),
                                  definicion: definicion(), nombrePlan: "Plan")
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(vieja)) as! [String: Any]
        json.removeValue(forKey: "resolucionDeHoy")
        json.removeValue(forKey: "nombreDeHoy")
        json.removeValue(forKey: "tipoDeHoy")
        let datos = try JSONSerialization.data(withJSONObject: json)
        let decodificada = try JSONDecoder().decode(ProyeccionDia.self, from: datos)
        XCTAssertNil(decodificada.resolucionDeHoy)
        XCTAssertNotNil(decodificada.programadoID)
    }
}

// MARK: - Build 40: gestión del programado y semana actual

final class GestionProgramadoTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)   // lunes

    private func almacenConTres() -> (AlmacenV2, UUID, UUID, UUID) {
        var almacen = AlmacenV2()
        almacen.activado = true
        let definicion = DefinicionEntrenamiento(tipo: .facil, nombre: "Rodaje", segmentos: [])
        let lunes = EntrenamientoProgramado(definicion: definicion, dia: hoy)
        let miercoles = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: 2))
        var viernes = EntrenamientoProgramado(definicion: definicion, dia: hoy.sumando(dias: 4))
        viernes.resolucion = .cumplido
        viernes.sesionVinculadaID = UUID()
        almacen.planActivo = PlanUsuario(nombre: "P", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1,
                                                              programados: [lunes, miercoles, viernes])])
        return (almacen, lunes.id, miercoles.id, viernes.id)
    }

    func testReprogramarConservaIdentidadYOriginal() {
        var (almacen, lunesID, _, _) = almacenConTres()
        let nuevoDia = hoy.sumando(dias: 1)
        XCTAssertTrue(almacen.reprogramar(programadoID: lunesID, a: nuevoDia))
        let movido = almacen.todosLosProgramados.first { $0.id == lunesID }!
        XCTAssertEqual(movido.id, lunesID)              // MISMO programadoID
        XCTAssertEqual(movido.dia, nuevoDia)
        XCTAssertEqual(movido.diaOriginal, hoy)         // la historia queda
        XCTAssertEqual(movido.resolucion, .pendiente)   // no es un estado
        XCTAssertEqual(almacen.todosLosProgramados.count, 3)  // nada nuevo

        // Segundo movimiento: diaOriginal NO se pisa (sigue la primera).
        almacen.reprogramar(programadoID: lunesID, a: hoy.sumando(dias: 3))
        XCTAssertEqual(almacen.todosLosProgramados.first { $0.id == lunesID }?.diaOriginal, hoy)
    }

    func testReprogramarSoloPendientes() {
        var (almacen, _, _, viernesID) = almacenConTres()
        XCTAssertFalse(almacen.reprogramar(programadoID: viernesID, a: hoy))
        XCTAssertFalse(almacen.reprogramar(programadoID: UUID(), a: hoy))  // inexistente
    }

    func testConflictoEnDia() {
        let (almacen, lunesID, miercolesID, _) = almacenConTres()
        // Mover el lunes al miércoles choca con el de miércoles.
        XCTAssertEqual(almacen.conflictoEnDia(hoy.sumando(dias: 2), salvo: lunesID)?.id,
                       miercolesID)
        // El propio día no choca consigo mismo.
        XCTAssertNil(almacen.conflictoEnDia(hoy, salvo: lunesID))
        // Un día vacío no choca.
        XCTAssertNil(almacen.conflictoEnDia(hoy.sumando(dias: 1), salvo: lunesID))
    }

    func testOmitirYDeshacer() {
        var (almacen, lunesID, _, viernesID) = almacenConTres()
        XCTAssertTrue(almacen.omitir(programadoID: lunesID))
        XCTAssertEqual(almacen.todosLosProgramados.first { $0.id == lunesID }?.resolucion,
                       .omitido)
        // Sigue existiendo (no se borra) y no se puede re-omitir.
        XCTAssertEqual(almacen.todosLosProgramados.count, 3)
        XCTAssertFalse(almacen.omitir(programadoID: lunesID))
        // Un cumplido no se omite.
        XCTAssertFalse(almacen.omitir(programadoID: viernesID))

        // Deshacer: omitido sin sesión → pendiente.
        XCTAssertTrue(almacen.deshacerOmision(programadoID: lunesID))
        XCTAssertEqual(almacen.todosLosProgramados.first { $0.id == lunesID }?.resolucion,
                       .pendiente)
        // Un cumplido con sesión jamás se "deshace".
        XCTAssertFalse(almacen.deshacerOmision(programadoID: viernesID))
    }

    func testSemanaActualLunesADomingo() {
        let (almacen, lunesID, miercolesID, viernesID) = almacenConTres()
        let semana = almacen.semanaActual(hoy: hoy.sumando(dias: 2))  // miércoles
        XCTAssertEqual(semana.count, 7)
        XCTAssertEqual(semana[0].dia, hoy)                       // arranca el lunes
        XCTAssertEqual(semana[6].dia, hoy.sumando(dias: 6))      // termina el domingo
        XCTAssertTrue(semana[2].esHoy)
        XCTAssertEqual(semana.filter(\.esHoy).count, 1)
        XCTAssertEqual(semana[0].programado?.id, lunesID)
        XCTAssertEqual(semana[2].programado?.id, miercolesID)
        XCTAssertEqual(semana[4].programado?.id, viernesID)
        XCTAssertNil(semana[1].programado)                       // descanso
    }

    func testLunesDeLaSemanaDesdeCualquierDia() {
        // 10/8/2026 es lunes; el domingo 16 sigue siendo de ESA semana.
        XCTAssertEqual(hoy.lunesDeLaSemana(), hoy)
        XCTAssertEqual(hoy.sumando(dias: 6).lunesDeLaSemana(), hoy)   // domingo
        XCTAssertEqual(hoy.sumando(dias: 7).lunesDeLaSemana(), hoy.sumando(dias: 7))
        XCTAssertEqual(hoy.sumando(dias: 3).lunesDeLaSemana(), hoy)   // jueves
    }
}

// MARK: - Build 40: cuenta regresiva del objetivo

final class CuentaRegresivaTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)

    func testCuentaRegresivaEnSemanasYDias() {
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 98), hoy: hoy),
                       String(localized: "Faltan \(14) semanas para tu carrera"))
        // Hasta 13 días la cuenta va en DÍAS (más preciso que "1
        // semana"): el borde de semanas empieza en 14.
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 7), hoy: hoy),
                       String(localized: "Faltan \(7) días para tu carrera"))
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 13), hoy: hoy),
                       String(localized: "Faltan \(13) días para tu carrera"))
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 14), hoy: hoy),
                       String(localized: "Faltan \(2) semanas para tu carrera"))
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 5), hoy: hoy),
                       String(localized: "Faltan \(5) días para tu carrera"))
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: 1), hoy: hoy),
                       String(localized: "Tu carrera es mañana"))
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy, hoy: hoy),
                       String(localized: "¡Tu carrera es hoy!"))
        XCTAssertNil(TextosObjetivo.cuentaRegresiva(hasta: nil, hoy: hoy))
        // Fecha pasada: texto NEUTRO, sin reproches.
        XCTAssertEqual(TextosObjetivo.cuentaRegresiva(hasta: hoy.sumando(dias: -3), hoy: hoy),
                       String(localized: "La fecha de tu carrera ya pasó — actualizala cuando quieras"))
    }
}

// MARK: - RC1: identidad y cuenta

// @MainActor: IdentidadStore está aislado a MainActor (build 45);
// XCTest ejecuta estos tests en el hilo principal.
@MainActor
final class IdentidadCuentaTests: XCTestCase {

    private func urlTemporal() -> URL {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cuenta-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        return directorio.appendingPathComponent("cuenta.json")
    }

    func testUserIDEstableYSeparadoDeProveedores() {
        let url = urlTemporal()
        var dominioAsociado: UUID?
        let identidad = IdentidadStore(url: url) { dominioAsociado = $0 }

        identidad.iniciarSesion(con: ProveedorVinculado(
            tipo: .apple, subjectID: "apple-subject-1",
            email: "relay@privaterelay.appleid.com", fechaVinculacion: Date()),
            nombre: "Felipe")
        let userID = identidad.cuenta!.userID
        XCTAssertNotNil(userID)
        XCTAssertEqual(dominioAsociado, userID)

        // Vincular OTRO proveedor no cambia el userID (multi-proveedor).
        identidad.iniciarSesion(con: ProveedorVinculado(
            tipo: .email, subjectID: "pipe@gmail.com",
            email: "pipe@gmail.com", fechaVinculacion: Date()))
        XCTAssertEqual(identidad.cuenta!.userID, userID)
        XCTAssertEqual(identidad.cuenta!.proveedores.count, 2)

        // Reiniciar la app (nuevo store, mismo archivo): la cuenta y el
        // userID persisten.
        let recargada = IdentidadStore(url: url)
        XCTAssertEqual(recargada.cuenta?.userID, userID)
        XCTAssertTrue(recargada.haySesion)
    }

    func testVincularEsIdempotente() {
        var cuenta = CuentaUsuario(nombre: nil, fechaCreacion: Date())
        let apple = ProveedorVinculado(tipo: .apple, subjectID: "s1",
                                       email: nil, fechaVinculacion: Date())
        cuenta.vincular(apple)
        cuenta.vincular(apple)   // doble tap / doble callback
        XCTAssertEqual(cuenta.proveedores.count, 1)
        // Mismo TIPO con otro subject sí entra (cuenta re-creada en Apple).
        cuenta.vincular(ProveedorVinculado(tipo: .apple, subjectID: "s2",
                                           email: nil, fechaVinculacion: Date()))
        XCTAssertEqual(cuenta.proveedores.count, 2)
    }

    func testMigracionUsuarioExistenteSinDuplicados() {
        // Usuario con datos y SIN cuenta crea una: los datos se asocian
        // al userID y NADA se duplica ni se pierde.
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-merge-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        var dominio = AlmacenV2()
        dominio.activado = true
        dominio.planActivo = PlanUsuario(nombre: "Mi plan", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0), semanas: [])
        dominio.sesiones = [RegistroSesion(id: UUID(), fecha: Date(), vinculoProgramadoID: nil)]
        let urlDominio = directorio.appendingPathComponent("dominio-v2.json")
        try? JSONEncoder().encode(dominio).write(to: urlDominio)
        let almacen = AlmacenStore(url: urlDominio,
                                   urlLegacy: directorio.appendingPathComponent("plan.json"),
                                   conectadoAlReloj: false)
        XCTAssertNil(almacen.almacen.usuarioID)

        let identidad = IdentidadStore(url: directorio.appendingPathComponent("cuenta.json"))
        IdentidadStore.conectar(identidad, con: almacen)
        identidad.iniciarSesion(con: ProveedorVinculado(
            tipo: .apple, subjectID: "s1", email: nil, fechaVinculacion: Date()))

        XCTAssertEqual(almacen.almacen.usuarioID, identidad.cuenta?.userID)
        XCTAssertEqual(almacen.almacen.planActivo?.nombre, "Mi plan")   // intacto
        XCTAssertEqual(almacen.almacen.sesiones.count, 1)               // sin duplicar
        try? FileManager.default.removeItem(at: directorio)
    }

    func testCerrarSesionNoEsEliminar() {
        let url = urlTemporal()
        let identidad = IdentidadStore(url: url)
        identidad.iniciarSesion(con: ProveedorVinculado(
            tipo: .apple, subjectID: "s1", email: nil, fechaVinculacion: Date()))
        identidad.cerrarSesion()
        XCTAssertFalse(identidad.haySesion)
        XCTAssertNotNil(identidad.cuenta)   // la cuenta y los datos quedan

        // Eliminar sí borra la cuenta local y desasocia el dominio.
        var dominioAsociado: UUID? = UUID()
        identidad.asociarDominio = { dominioAsociado = $0 }
        identidad.eliminarCuenta(borrandoRespaldo: nil)
        XCTAssertNil(identidad.cuenta)
        XCTAssertNil(dominioAsociado)
        XCTAssertNil(IdentidadStore(url: url).cuenta)   // no revive al reabrir
    }

    func testUsuarioNuevoYViejosDecodifican() throws {
        // dominio-v2.json anterior a RC1 (sin usuarioID) sigue cargando.
        var viejo = AlmacenV2()
        viejo.activado = true
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(viejo)) as! [String: Any]
        json.removeValue(forKey: "usuarioID")
        let datos = try JSONSerialization.data(withJSONObject: json)
        let cargado = try JSONDecoder().decode(AlmacenV2.self, from: datos)
        XCTAssertNil(cargado.usuarioID)
    }
}

// MARK: - RC1: motor de planes (§42)

final class MotorPlanesTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)   // lunes

    private func pedido(_ objetivo: ObjetivoDeportivo,
                        fecha: DiaLocal? = nil,
                        dias: Int = 3,
                        referencia: ReferenciaRendimiento? = nil,
                        aceptaSinBaseline: Bool = false) -> PedidoDePlan {
        PedidoDePlan(objetivo: objetivo, fechaObjetivo: fecha,
                     diasPorSemana: dias, referencia: referencia,
                     aceptaSinBaseline: aceptaSinBaseline, hoy: hoy)
    }

    private func propuesta(_ resultado: ResultadoPlanificacion) -> PropuestaPlan? {
        if case .propuesta(let p) = resultado { return p }
        return nil
    }

    func testObjetivo5KGeneraPropuestaCompleta() throws {
        let resultado = MotorPlanificacion.proponer(pedido(.primeros5K))
        let plan = try XCTUnwrap(propuesta(resultado))
        XCTAssertEqual(plan.semanas, 6)
        XCTAssertEqual(plan.sesionesPorSemana, 3)
        XCTAssertEqual(plan.planUsuario.origen,
                       .catalogo(planBaseID: "primeros-5k@2"))
        // Calendario sin fechas duplicadas accidentales.
        let dias = plan.planUsuario.semanas.flatMap(\.programados).compactMap(\.dia)
        XCTAssertEqual(dias.count, Set(dias).count)
        XCTAssertEqual(dias.count, 18)   // 6 semanas × 3 (arranca lunes: nada se pierde)
        // Round-trip del plan generado.
        let datos = try JSONEncoder().encode(plan.planUsuario)
        XCTAssertEqual(try JSONDecoder().decode(PlanUsuario.self, from: datos),
                       plan.planUsuario)
    }

    func testObjetivo10KGeneraPropuesta() throws {
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(pedido(.diez))))
        XCTAssertEqual(plan.semanas, 8)
        XCTAssertEqual(plan.planUsuario.origen, .catalogo(planBaseID: "10k-continuo@2"))
    }

    func testArquetipoSinContenidoRespondeHonesto() {
        // 21K/42K/mejorar-5K ya tienen contenido (build 53). La
        // invariante que importa es otra y sigue viva: un arquetipo SIN
        // contenido validado hace que el motor lo diga, en vez de
        // inventar workouts. Se prueba con biblioteca inyectada para no
        // depender del estado del catálogo.
        let vacio = PlanArquetipo(
            id: "futuro", version: 1, objetivo: .maraton, nombre: "Futuro",
            semanasMinimas: 12, semanasRecomendadas: 16,
            diasMinimos: 3, diasMaximos: 5,
            recomiendaBaseline: false, contenido: nil)
        guard case .sinContenido(let cual) =
            MotorPlanificacion.proponer(pedido(.maraton), biblioteca: [vacio]) else {
            return XCTFail("sin contenido el motor debe responder sinContenido")
        }
        XCTAssertEqual(cual, .maraton)
        // Y los que SÍ tienen contenido ahora proponen de verdad.
        for objetivo in [ObjetivoDeportivo.mediaMaraton, .maraton, .mejorar5K] {
            let arquetipo = BibliotecaArquetipos.v1().first { $0.objetivo == objetivo }
            XCTAssertEqual(arquetipo?.listoParaProponer, true, "\(objetivo) sin contenido")
        }
    }

    func testBaselinePresenteAusenteYSinReferencia() throws {
        // Biblioteca sintética: arquetipo CON contenido que recomienda
        // baseline (los reales con baseline aún no tienen contenido).
        var arquetipo = BibliotecaArquetipos.v1().first { $0.id == "10k-continuo" }!
        arquetipo.recomiendaBaseline = true
        let biblioteca = [arquetipo]

        // Sin referencia → ofrece test (falta baseline).
        guard case .faltaBaseline = MotorPlanificacion.proponer(
            pedido(.diez), biblioteca: biblioteca) else {
            return XCTFail("esperaba faltaBaseline")
        }
        // Con referencia → propuesta, y la referencia queda CONSERVADA.
        let marca = ReferenciaRendimiento(fecha: Date(timeIntervalSince1970: 0),
                                          fuente: .test5K,
                                          distanciaMetros: 5000, segundos: 1470)
        let conMarca = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(
            pedido(.diez, referencia: marca), biblioteca: biblioteca)))
        XCTAssertEqual(conMarca.planUsuario.referenciaUsadaID, marca.id)
        XCTAssertEqual(conMarca.referenciaUsada?.segundos, 1470)
        // El corredor decide arrancar SIN baseline: el plan existe con
        // ritmos sin resolver (el test 5K jamás es obligatorio).
        XCTAssertNotNil(propuesta(MotorPlanificacion.proponer(
            pedido(.diez, aceptaSinBaseline: true), biblioteca: biblioteca)))
    }

    func testDisponibilidadRecortaPorRolNoPorFila() throws {
        // 2 días: cada semana conserva su sesión de MAYOR prioridad de
        // rol — la LARGA sobrevive siempre que exista.
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(
            pedido(.diez, dias: 2))))
        XCTAssertEqual(plan.sesionesPorSemana, 2)
        for semana in plan.planUsuario.semanas {
            XCTAssertEqual(semana.programados.count, 2)
            XCTAssertTrue(semana.programados.contains {
                PlanArquetipo.rol(de: $0.definicion.tipo) == .tiradaLarga
                    || PlanArquetipo.rol(de: $0.definicion.tipo) == .carrera
            }, "la larga no puede recortarse con 2 días")
        }
        // 5 días con arquetipo de máximo 3: usa 3 y lo dice.
        let cinco = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(
            pedido(.diez, dias: 5))))
        XCTAssertEqual(cinco.sesionesPorSemana, 3)
        XCTAssertEqual(cinco.diasPedidos, 5)
        // 1 día: por debajo del mínimo del arquetipo.
        guard case .diasInsuficientes(let minimo) =
            MotorPlanificacion.proponer(pedido(.diez, dias: 1)) else {
            return XCTFail("esperaba diasInsuficientes")
        }
        XCTAssertEqual(minimo, 2)
    }

    func testCarreraAlineadaAlFinalExacto() throws {
        // Carrera el sábado 19/9/2026: 6 semanas exactas desde este
        // lunes. La última sesión cae EL DÍA de la carrera y no hay
        // nada después.
        let carrera = DiaLocal(anio: 2026, mes: 9, dia: 19)
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(
            pedido(.primeros5K, fecha: carrera))))
        let dias = plan.planUsuario.semanas.flatMap(\.programados).compactMap(\.dia)
        XCTAssertEqual(dias.max(), carrera)
        XCTAssertFalse(dias.contains { carrera < $0 })
        XCTAssertEqual(plan.fechaCarrera, carrera)
        // El plan arranca en la semana de HOY (6 semanas justas).
        XCTAssertEqual(plan.fechaInicio.lunesDeLaSemana(), hoy)
    }

    func testCarreraLejanaArrancaEnElFuturoSinEstirar() throws {
        // Carrera en 10 semanas con plan de 6: el plan NO se estira —
        // arranca más adelante para terminar en la carrera.
        let carrera = DiaLocal(anio: 2026, mes: 10, dia: 17)
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(
            pedido(.primeros5K, fecha: carrera))))
        XCTAssertEqual(plan.semanas, 6)
        XCTAssertTrue(hoy < plan.fechaInicio)
        let dias = plan.planUsuario.semanas.flatMap(\.programados).compactMap(\.dia)
        XCTAssertEqual(dias.max(), carrera)
    }

    func testTiempoInsuficienteNoComprime() {
        // "10K en 2 semanas": jamás un plan peligroso comprimido.
        let carrera = hoy.sumando(dias: 13)
        guard case .tiempoInsuficiente(let disponibles, let minimas) =
            MotorPlanificacion.proponer(pedido(.diez, fecha: carrera)) else {
            return XCTFail("esperaba tiempoInsuficiente")
        }
        XCTAssertEqual(minimas, 8)
        XCTAssertLessThan(disponibles, minimas)
    }

    func testSemanaParcialInicial() throws {
        // Hoy jueves, sin carrera: los días ya pasados de la primera
        // semana no se programan; el resto queda intacto.
        let jueves = DiaLocal(anio: 2026, mes: 8, dia: 13)
        var pedidoJueves = pedido(.primeros5K)
        pedidoJueves.hoy = jueves
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(pedidoJueves)))
        let dias = plan.planUsuario.semanas.flatMap(\.programados).compactMap(\.dia)
        XCTAssertFalse(dias.contains { $0 < jueves })
        XCTAssertEqual(plan.planUsuario.semanas.first?.programados.count, 1)  // solo el viernes
        XCTAssertEqual(plan.planUsuario.semanas.count, 6)
    }

    func testActualizarArquetipoNoTocaPlanAdoptado() throws {
        var almacen = AlmacenV2()
        almacen.activado = true
        let plan = try XCTUnwrap(propuesta(MotorPlanificacion.proponer(pedido(.primeros5K))))
        almacen.adoptarPlan(plan.planUsuario)
        let snapshot = almacen.planActivo

        // "Sale la versión 3 del arquetipo": la biblioteca cambia, el
        // plan activo es un snapshot por valor — idéntico.
        var bibliotecaNueva = BibliotecaArquetipos.v1()
        bibliotecaNueva[0].version = 3
        _ = MotorPlanificacion.proponer(pedido(.primeros5K), biblioteca: bibliotecaNueva)
        XCTAssertEqual(almacen.planActivo, snapshot)
        if case .catalogo(let id) = snapshot!.origen {
            XCTAssertEqual(id, "primeros-5k@2")   // la procedencia no se reescribe
        }
    }

    func testValidadorDeCoach() {
        var almacen = AlmacenV2()
        almacen.activado = true
        let programado = EntrenamientoProgramado(
            definicion: DefinicionEntrenamiento(tipo: .facil, nombre: "R", segmentos: []),
            dia: hoy.sumando(dias: 2))
        almacen.planActivo = PlanUsuario(nombre: "P", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0),
                                         semanas: [SemanaPlan(numero: 1, programados: [programado])])
        // Reprogramar hacia adelante: permitido.
        XCTAssertTrue(ValidadorDeCoach.validar(
            .reprogramar(programadoID: programado.id, a: hoy.sumando(dias: 4)),
            en: almacen, hoy: hoy).permitido)
        // Hacia el pasado: rechazado.
        XCTAssertFalse(ValidadorDeCoach.validar(
            .reprogramar(programadoID: programado.id, a: hoy.sumando(dias: -1)),
            en: almacen, hoy: hoy).permitido)
        // Ajustar volumen sin metodología: rechazado SIEMPRE.
        XCTAssertFalse(ValidadorDeCoach.validar(
            .ajustarVolumenSemana(numero: 1, factor: 1.4),
            en: almacen, hoy: hoy).permitido)
        // Omitir inexistente: rechazado.
        XCTAssertFalse(ValidadorDeCoach.validar(
            .omitir(programadoID: UUID()), en: almacen, hoy: hoy).permitido)
    }
}

// MARK: - Build 44: auth real (Firebase) — lógica testeable sin red

// @MainActor por IdentidadStore (ver IdentidadTests).
@MainActor
final class AuthSprintTests: XCTestCase {

    // Validación local de credenciales (la UI se apoya en esto para
    // habilitar botones; el veredicto final siempre es de Firebase).
    func testEmailValido() {
        XCTAssertTrue(ValidacionCredenciales.emailValido("pipe@gmail.com"))
        XCTAssertTrue(ValidacionCredenciales.emailValido("  pipe@gmail.com  "))   // trim
        XCTAssertTrue(ValidacionCredenciales.emailValido("a@b.co"))
        XCTAssertFalse(ValidacionCredenciales.emailValido(""))
        XCTAssertFalse(ValidacionCredenciales.emailValido("sin-arroba"))
        XCTAssertFalse(ValidacionCredenciales.emailValido("@dominio.com"))
        XCTAssertFalse(ValidacionCredenciales.emailValido("pipe@sinpunto"))
        XCTAssertFalse(ValidacionCredenciales.emailValido("pipe@.com"))
        XCTAssertFalse(ValidacionCredenciales.emailValido("pipe@dominio."))
        XCTAssertFalse(ValidacionCredenciales.emailValido("dos@arro@bas.com"))
        XCTAssertFalse(ValidacionCredenciales.emailValido("con espacio@x.com"))
    }

    func testPasswordValidaYCoincidencia() {
        XCTAssertTrue(ValidacionCredenciales.passwordValida("12345678"))
        XCTAssertFalse(ValidacionCredenciales.passwordValida("1234567"))
        XCTAssertTrue(ValidacionCredenciales.passwordsCoinciden("abcd1234", "abcd1234"))
        XCTAssertFalse(ValidacionCredenciales.passwordsCoinciden("abcd1234", "abcd1235"))
        XCTAssertFalse(ValidacionCredenciales.passwordsCoinciden("", ""))   // vacías no "coinciden"
    }

    // cuenta.json anterior al build 44 (sin firebaseUID) sigue cargando:
    // el campo es opcional con default nil.
    func testProveedorSinFirebaseUIDDecodifica() throws {
        let proveedor = ProveedorVinculado(
            tipo: .apple, subjectID: "s1", email: nil, fechaVinculacion: Date())
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(proveedor)) as! [String: Any]
        json.removeValue(forKey: "firebaseUID")
        let datos = try JSONSerialization.data(withJSONObject: json)
        let cargado = try JSONDecoder().decode(ProveedorVinculado.self, from: datos)
        XCTAssertNil(cargado.firebaseUID)
        XCTAssertEqual(cargado.subjectID, "s1")
    }

    func testFirebaseUIDViajaEnElVinculoNoEnLaCuenta() throws {
        // El UID de Firebase es atributo del vínculo y sobrevive el
        // round-trip; el userID del dominio es independiente de él.
        var cuenta = CuentaUsuario(nombre: nil, fechaCreacion: Date())
        var vinculo = ProveedorVinculado(
            tipo: .google, subjectID: "g-sub", email: "pipe@gmail.com",
            fechaVinculacion: Date())
        vinculo.firebaseUID = "fb-uid-123"
        cuenta.vincular(vinculo)

        let recargada = try JSONDecoder().decode(
            CuentaUsuario.self, from: JSONEncoder().encode(cuenta))
        XCTAssertEqual(recargada.proveedores.first?.firebaseUID, "fb-uid-123")
        XCTAssertEqual(recargada.userID, cuenta.userID)
        XCTAssertNotEqual(recargada.userID.uuidString, "fb-uid-123")
    }

    // Logout → login con el MISMO proveedor no duplica vínculos ni
    // cambia la identidad del dominio (flujo real de la UI).
    func testLogoutLoginNoDuplicaNiCambiaUserID() {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-auth-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directorio) }
        let identidad = IdentidadStore(url: directorio.appendingPathComponent("cuenta.json"))

        var vinculo = ProveedorVinculado(
            tipo: .google, subjectID: "g-sub", email: "pipe@gmail.com",
            fechaVinculacion: Date())
        vinculo.firebaseUID = "fb-uid-123"
        identidad.iniciarSesion(con: vinculo)
        let userID = identidad.cuenta!.userID

        identidad.cerrarSesion()
        XCTAssertFalse(identidad.haySesion)

        identidad.iniciarSesion(con: vinculo)   // vuelve a entrar
        XCTAssertTrue(identidad.haySesion)
        XCTAssertEqual(identidad.cuenta!.userID, userID)
        XCTAssertEqual(identidad.cuenta!.proveedores.count, 1)
    }

    // Apple + Google + email sobre la misma cuenta local: tres vínculos,
    // un solo userID (la autoridad remota es Firebase; acá se protege
    // que el dominio no se fragmente).
    func testTresProveedoresUnaIdentidad() {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-auth-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directorio) }
        let identidad = IdentidadStore(url: directorio.appendingPathComponent("cuenta.json"))

        for (tipo, subject) in [(ProveedorVinculado.Tipo.apple, "a-sub"),
                                (.google, "g-sub"),
                                (.email, "pipe@gmail.com")] {
            var v = ProveedorVinculado(tipo: tipo, subjectID: subject,
                                       email: nil, fechaVinculacion: Date())
            v.firebaseUID = "fb-uid-unico"
            identidad.iniciarSesion(con: v)
        }
        XCTAssertEqual(identidad.cuenta?.proveedores.count, 3)
        XCTAssertEqual(Set(identidad.cuenta!.proveedores.map(\.tipo)).count, 3)
    }
}

// MARK: - Sprint final: días concretos + distribución (B1/B2)

final class DiasConcretosTests: XCTestCase {

    private let hoy = DiaLocal(anio: 2026, mes: 8, dia: 10)   // lunes
    private var lunes: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private func diaDeSemana(_ dia: DiaLocal) -> Int {
        // 1 = lunes … 7 = domingo (convención del dominio).
        let fecha = dia.fecha(calendario: lunes)!
        let wd = lunes.component(.weekday, from: fecha)   // 1 = domingo
        return wd == 1 ? 7 : wd - 1
    }

    func testDistribuirMapeaSoloDiasElegidos() {
        let base = ContenidoPlanes.mediaMaraton()
        let dias = [2, 4, 6, 7]
        let distribuida = MotorPlanificacion.distribuir(base, enDias: dias)
        for semana in distribuida.semanas {
            let asignados = semana.entrenamientos.map(\.diaDeSemana)
            XCTAssertEqual(asignados.count, Set(asignados).count, "días duplicados")
            XCTAssertTrue(asignados.allSatisfy { dias.contains($0) })
            // La última sesión del template (larga/carrera) cae en el
            // último día disponible.
            XCTAssertEqual(asignados.max(), semana.entrenamientos.isEmpty ? nil : 7)
        }
    }

    func testDistribuirRepartidoConMasDiasQueSesiones() {
        // 3 sesiones en 5 días elegidos: primera en el primero, última
        // en el último, la del medio repartida.
        let base = PlanBase(id: "t", version: 1, nombre: "t", descripcion: "",
                            distanciaObjetivoKm: 5, semanasTotales: 1, diasPorSemana: 3,
                            provisional: true, semanas: [SemanaBase(numero: 1, entrenamientos: [
                                EntrenamientoBase(diaDeSemana: 2, tipo: .umbral, nombre: "a", descripcion: "", segmentos: []),
                                EntrenamientoBase(diaDeSemana: 4, tipo: .facil, nombre: "b", descripcion: "", segmentos: []),
                                EntrenamientoBase(diaDeSemana: 7, tipo: .largo, nombre: "c", descripcion: "", segmentos: []),
                            ])])
        let d = MotorPlanificacion.distribuir(base, enDias: [1, 3, 4, 6, 7])
        XCTAssertEqual(d.semanas[0].entrenamientos.map(\.diaDeSemana), [1, 4, 7])
    }

    func testProponerConDiasConcretos() throws {
        let referencia = ReferenciaRendimiento(fecha: Date(), fuente: .marcaManual,
                                               distanciaMetros: 5000, segundos: 1470)
        let pedido = PedidoDePlan(objetivo: .mediaMaraton, fechaObjetivo: nil,
                                  diasPorSemana: 4, diasConcretos: [2, 4, 6, 7],
                                  referencia: referencia, hoy: hoy)
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        XCTAssertEqual(p.diasPedidos, 4)
        for semana in p.planUsuario.semanas {
            for programado in semana.programados {
                guard let dia = programado.dia else { continue }
                XCTAssertTrue([2, 4, 6, 7].contains(diaDeSemana(dia)),
                              "sesión en día no elegido: \(dia)")
            }
        }
    }

    func testCarreraPineadaAunqueNoSeaDiaElegido() throws {
        // Carrera un miércoles (día 3, NO elegido): la carrera va a su
        // fecha real igual — la fecha de la carrera manda.
        let carrera = DiaLocal(anio: 2026, mes: 11, dia: 4)   // miércoles
        let referencia = ReferenciaRendimiento(fecha: Date(), fuente: .marcaManual,
                                               distanciaMetros: 5000, segundos: 1470)
        let pedido = PedidoDePlan(objetivo: .mediaMaraton, fechaObjetivo: carrera,
                                  diasPorSemana: 4, diasConcretos: [2, 4, 6, 7],
                                  referencia: referencia, hoy: hoy)
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        let ultima = p.planUsuario.semanas.last!.programados.last!
        XCTAssertEqual(ultima.dia, carrera)
    }

    func testPerfilViejoSinDiasElegidosDecodifica() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PerfilDeportivo())) as! [String: Any]
        json.removeValue(forKey: "diasElegidos")
        let datos = try JSONSerialization.data(withJSONObject: json)
        let perfil = try JSONDecoder().decode(PerfilDeportivo.self, from: datos)
        XCTAssertNil(perfil.diasElegidos)
    }
}

// MARK: - Sprint final: metodología de ritmos + contenido (B3-B7)

final class MetodologiaTests: XCTestCase {

    private var baseline: PerformanceBaseline {
        PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: Date(), fuente: .test5K, distanciaMetros: 5000, segundos: 1470))!
    }

    func testZonasOrdenadasDeRapidaALenta() {
        let m = MetodologiaMaratoniaV1()
        let rep = m.resolver(.repeticion, baseline: baseline)!
        let int = m.resolver(.intervalo, baseline: baseline)!
        let umb = m.resolver(.umbral, baseline: baseline)!
        let mar = m.resolver(.maraton, baseline: baseline)!
        let fac = m.resolver(.facil, baseline: baseline)!
        let rec = m.resolver(.recuperacion, baseline: baseline)!
        XCTAssertLessThan(rep.minSegKm, int.minSegKm)
        XCTAssertLessThan(int.minSegKm, umb.minSegKm)
        XCTAssertLessThan(umb.minSegKm, mar.minSegKm)
        XCTAssertLessThan(mar.maxSegKm, fac.minSegKm)
        XCTAssertLessThan(fac.maxSegKm, rec.maxSegKm)
    }

    func testValoresRazonablesPara5KEn2430() {
        // 5K en 24:30 → ritmo de carrera 294 s/km. El umbral (esfuerzo
        // de ~60 min) debe ser más lento que eso pero cercano.
        let m = MetodologiaMaratoniaV1()
        let umb = m.resolver(.umbral, baseline: baseline)!
        XCTAssertTrue((295...330).contains(umb.minSegKm), "umbral: \(umb)")
        let mar = m.resolver(.maraton, baseline: baseline)!
        XCTAssertTrue((310...350).contains(mar.minSegKm), "maratón: \(mar)")
    }

    func testReferenciaFueraDeRangoQuedaSimbolica() {
        let corta = PerformanceBaseline(referencia: ReferenciaRendimiento(
            fecha: Date(), fuente: .marcaManual, distanciaMetros: 800, segundos: 150))!
        XCTAssertNil(MetodologiaMaratoniaV1().resolver(.umbral, baseline: corta))
        XCTAssertNil(MetodologiaMaratoniaV1().resolver(.facil, baseline: corta))
    }

    func testMetodologiaActivaResuelve() {
        if case .pendiente = Metodologias.resolver(.umbral, baseline: baseline) {
            XCTFail("la metodología v1 debería resolver umbral")
        }
    }

    func testContenidoGrandeListo() {
        let biblioteca = BibliotecaArquetipos.v1()
        for objetivo in [ObjetivoDeportivo.mejorar5K, .mediaMaraton, .maraton] {
            let arquetipo = biblioteca.first { $0.objetivo == objetivo }!
            XCTAssertTrue(arquetipo.listoParaProponer, "\(objetivo) sin contenido")
        }
        XCTAssertEqual(ContenidoPlanes.maraton().semanasTotales, 16)
        XCTAssertEqual(ContenidoPlanes.mediaMaraton().semanasTotales, 12)
        XCTAssertEqual(ContenidoPlanes.mejorar5K().semanasTotales, 8)
    }

    func testLargaConTopeYDescargas() {
        let plan = ContenidoPlanes.maraton()
        var largas: [Int: Double] = [:]
        for semana in plan.semanas {
            if let larga = semana.entrenamientos.first(where: { $0.tipo == .largo }) {
                largas[semana.numero] = larga.segmentos.compactMap(\.distanciaKm).reduce(0, +)
            }
        }
        XCTAssertLessThanOrEqual(largas.values.max() ?? 0, 30)
        // Descargas: semana 4 < semana 3, semana 8 < semana 7.
        XCTAssertLessThan(largas[4]!, largas[3]!)
        XCTAssertLessThan(largas[8]!, largas[7]!)
        // Taper: la última larga antes de la carrera es corta.
        XCTAssertLessThan(largas[15]!, largas[13]! / 2)
    }

    func testConBaselineLosRitmosQuedanResueltos() throws {
        let referencia = ReferenciaRendimiento(fecha: Date(), fuente: .test5K,
                                               distanciaMetros: 5000, segundos: 1470)
        var lunes = Calendar(identifier: .gregorian); lunes.firstWeekday = 2
        let pedido = PedidoDePlan(objetivo: .maraton, fechaObjetivo: nil,
                                  diasPorSemana: 4, diasConcretos: [2, 4, 6, 7],
                                  referencia: referencia,
                                  hoy: DiaLocal(anio: 2026, mes: 8, dia: 10))
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        for semana in p.planUsuario.semanas {
            for programado in semana.programados {
                for segmento in programado.definicion.segmentos {
                    if case .simbolico = segmento.ritmo {
                        XCTFail("quedó simbólico con baseline presente: \(segmento.nombre)")
                    }
                }
            }
        }
    }

    func testSinBaselineQuedaSimbolicoYFunciona() throws {
        var lunes = Calendar(identifier: .gregorian); lunes.firstWeekday = 2
        let pedido = PedidoDePlan(objetivo: .maraton, fechaObjetivo: nil,
                                  diasPorSemana: 4, referencia: nil,
                                  aceptaSinBaseline: true,
                                  hoy: DiaLocal(anio: 2026, mes: 8, dia: 10))
        guard case .propuesta(let p) = MotorPlanificacion.proponer(pedido, calendario: lunes) else {
            return XCTFail("sin propuesta")
        }
        let simbolicos = p.planUsuario.semanas.flatMap(\.programados)
            .flatMap(\.definicion.segmentos)
            .filter { if case .simbolico = $0.ritmo { return true } else { return false } }
        XCTAssertFalse(simbolicos.isEmpty, "sin baseline los ritmos deben quedar simbólicos")
    }
}

// MARK: - Sprint final: Coach — schemas estrictos y privacidad del DTO

@MainActor
final class CoachTests: XCTestCase {

    func testDTONoFiltraGPSNiHealthKit() throws {
        var almacen = AlmacenV2()
        almacen.activado = true
        let contexto = ContextoCoach.desde(almacen, hoy: DiaLocal(anio: 2026, mes: 8, dia: 10))
        let json = String(data: try JSONEncoder().encode(contexto), encoding: .utf8)!.lowercased()
        for prohibido in ["lat", "lon", "coord", "ruta", "route", "heartrate", "workoutuuid"] {
            XCTAssertFalse(json.contains(prohibido), "el DTO filtra: \(prohibido)")
        }
    }

    func testAjusteParseaSoloCambiosValidos() throws {
        let id = UUID().uuidString.lowercased()
        let json = """
        {"explicacion":"x","cambios":[
          {"tipo":"reprogramar","programadoID":"\(id)","nuevoDia":"2026-08-13"},
          {"tipo":"omitir","programadoID":"\(id)","nuevoDia":null},
          {"tipo":"reprogramar","programadoID":"no-es-uuid","nuevoDia":"2026-08-14"},
          {"tipo":"reprogramar","programadoID":"\(id)","nuevoDia":"fecha-rota"},
          {"tipo":"borrarTodo","programadoID":"\(id)","nuevoDia":null}
        ]}
        """
        let ajuste = try JSONDecoder().decode(CoachWeekAdjustment.self, from: Data(json.utf8))
        // De 5 cambios, solo 2 sobreviven la traducción estricta.
        XCTAssertEqual(ajuste.propuestas.count, 2)
        if case .reprogramar(_, let dia) = ajuste.propuestas[0] {
            XCTAssertEqual(dia, DiaLocal(anio: 2026, mes: 8, dia: 13))
        } else { XCTFail() }
    }

    func testFechaIdaYVuelta() {
        let dia = DiaLocal(anio: 2026, mes: 12, dia: 5)
        XCTAssertEqual(ContextoCoach.dia(desde: ContextoCoach.texto(dia)), dia)
        XCTAssertNil(ContextoCoach.dia(desde: "2026-13-40"))
        XCTAssertNil(ContextoCoach.dia(desde: "ayer"))
    }

    func testValidadorFrenaPropuestasSobreNoExistentes() {
        // El coach propone tocar un programado que no existe: rechazado.
        let almacen = AlmacenV2()
        let cambio = CambioPropuesto.omitir(programadoID: UUID())
        XCTAssertFalse(ValidadorDeCoach.validar(cambio, en: almacen,
                                                hoy: DiaLocal(anio: 2026, mes: 8, dia: 10)).permitido)
    }

    func testGateDelCoachEsConsistente() {
        // disponible == (URL configurada Y Firebase arriba) — el gate
        // jamás muestra un Coach que no puede responder.
        XCTAssertEqual(ServicioCoach.disponible,
                       ServicioCoach.urlBase != nil && ServicioAuth.disponible)
        if let url = ServicioCoach.urlBase {
            XCTAssertEqual(url.scheme, "https")
        }
    }
}

// MARK: - Sprint UX: carreras ocultas, plurales y auto-pausa

final class UXSprintTests: XCTestCase {

    func testOcultarYRestaurarCarreraPersiste() {
        let suite = UserDefaults(suiteName: "test-ocultas-\(UUID().uuidString)")!
        let ocultas = CarrerasOcultas(defaults: suite)
        let id = UUID()
        XCTAssertFalse(ocultas.estaOculta(id))
        ocultas.ocultar(id)
        XCTAssertTrue(ocultas.estaOculta(id))
        // Persistencia: otra instancia sobre el mismo suite la ve.
        XCTAssertTrue(CarrerasOcultas(defaults: suite).estaOculta(id))
        ocultas.restaurar(id)
        XCTAssertFalse(ocultas.estaOculta(id))
        // Idempotencia: ocultar dos veces no duplica ni rompe.
        ocultas.ocultar(id); ocultas.ocultar(id)
        XCTAssertEqual(ocultas.ids().count, 1)
    }

    func testOcultarNoTocaOtrasCarreras() {
        let suite = UserDefaults(suiteName: "test-ocultas-\(UUID().uuidString)")!
        let ocultas = CarrerasOcultas(defaults: suite)
        let a = UUID(), b = UUID()
        ocultas.ocultar(a)
        XCTAssertFalse(ocultas.estaOculta(b))
        ocultas.restaurar(b)   // restaurar algo no oculto: inocuo
        XCTAssertTrue(ocultas.estaOculta(a))
    }

    func testPlurales() {
        XCTAssertEqual(Plurales.pistas(1), String(localized: "1 pista"))
        XCTAssertEqual(Plurales.tramos(1), String(localized: "1 tramo"))
        XCTAssertFalse(Plurales.pistas(2).hasPrefix("1 "))
        XCTAssertFalse(Plurales.entrenamientos(3).contains("1 entrenamiento"))
    }

    func testAutoPausaDefaultApagadaSinPisarPreferencia() {
        // La MISMA expresión que usan los motores:
        // object(forKey:) as? Bool ?? false
        let suite = UserDefaults(suiteName: "test-ap-\(UUID().uuidString)")!
        func valor() -> Bool { suite.object(forKey: "autoPausa") as? Bool ?? false }
        XCTAssertFalse(valor())            // instalación nueva → apagada
        suite.set(true, forKey: "autoPausa")
        XCTAssertTrue(valor())             // elección explícita se respeta
        suite.set(false, forKey: "autoPausa")
        XCTAssertFalse(valor())
    }

    func testCambioDePlanConservaHistorial() {
        // Cambiar de plan archiva el anterior y NO toca sesiones.
        var almacen = AlmacenV2()
        almacen.activado = true
        almacen.planActivo = PlanUsuario(nombre: "Viejo", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0), semanas: [])
        almacen.sesiones = [RegistroSesion(id: UUID(), fecha: Date(), vinculoProgramadoID: nil)]
        almacen.adoptarPlan(PlanUsuario(nombre: "Nuevo", origen: .personalizado,
                                        fechaAdopcion: Date(), semanas: []))
        XCTAssertEqual(almacen.planActivo?.nombre, "Nuevo")
        XCTAssertEqual(almacen.historialDePlanes.map(\.nombre), ["Viejo"])
        XCTAssertEqual(almacen.sesiones.count, 1)   // historial intacto
    }
}

// MARK: - Quitar plan sin reemplazo

final class AbandonarPlanTests: XCTestCase {

    func testAbandonarArchivaYNoBorraNada() {
        var almacen = AlmacenV2()
        almacen.activado = true
        almacen.planActivo = PlanUsuario(nombre: "De prueba", origen: .personalizado,
                                         fechaAdopcion: Date(timeIntervalSince1970: 0), semanas: [])
        almacen.sesiones = [RegistroSesion(id: UUID(), fecha: Date(), vinculoProgramadoID: nil)]
        almacen.abandonarPlan()
        XCTAssertNil(almacen.planActivo)
        XCTAssertEqual(almacen.historialDePlanes.map(\.nombre), ["De prueba"])
        XCTAssertEqual(almacen.sesiones.count, 1)          // nada borrado
        // HOY queda vacío: la app pasa a modo libre.
        XCTAssertNil(almacen.entrenamientoDeHoy(DiaLocal(fecha: Date())))
        // Sin plan, abandonar de nuevo es inocuo.
        almacen.abandonarPlan()
        XCTAssertEqual(almacen.historialDePlanes.count, 1)
    }

    func testAbandonarYAdoptarDespuesConservaHistorialDePlanes() {
        var almacen = AlmacenV2()
        almacen.planActivo = PlanUsuario(nombre: "A", origen: .personalizado,
                                         fechaAdopcion: Date(), semanas: [])
        almacen.abandonarPlan()
        almacen.adoptarPlan(PlanUsuario(nombre: "B", origen: .personalizado,
                                        fechaAdopcion: Date(), semanas: []))
        XCTAssertEqual(almacen.planActivo?.nombre, "B")
        XCTAssertEqual(almacen.historialDePlanes.map(\.nombre), ["A"])
    }
}
