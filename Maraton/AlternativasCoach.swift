import Foundation

// RESOLVER, NO RECHAZAR Y CORTAR.
//
// El caso que lo motivó: sábado 15 rodaje suave, domingo 16 tirada
// larga. El corredor dice que no puede el sábado. El Coach propuso
// moverlo al domingo, el motor lo rechazó bien ("ese día ya tiene otro
// entrenamiento") y ahí terminaba todo. Una intención válida, una
// respuesta correcta, y el corredor sin saber qué hacer.
//
// La corrección NO es dejar que el modelo pruebe fechas a ciegas hasta
// que alguna pase. Es al revés: EL DOMINIO busca las alternativas y las
// prevalida con el MISMO validador que decide al aplicar, y el Coach
// solo presenta lo que ya pasó. Nunca se le ofrece al corredor una
// opción que después vaya a ser rechazada.
//
// Orden de preferencia, y es deportivo, no de UI:
// 1. mover de día — es lo que menos toca el plan;
// 2. convertir en fácil o acortar — se conserva el día, baja la carga;
// 3. omitir — se pierde la sesión, y no se compensa después;
// 4. mantener — siempre disponible: "no cambies nada" es una respuesta.
//
// Nada de esto amplía lo que la IA puede hacer: son las mismas cinco
// operaciones de `CambioPropuesto`, con el mismo validador. Lo único
// nuevo es QUIÉN propone los candidatos.

/// Una salida posible, ya validada contra el plan real.
struct OpcionDeCoach: Equatable, Identifiable {
    /// Estable y legible: sirve de ancla para la respuesta del corredor
    /// ("el lunes") y para la UI.
    var id: String
    var cambio: CambioPropuesto
    var titulo: String
    var detalle: String?
    /// El día destino, cuando la operación es mover. Es lo que permite
    /// entender "el lunes" sin preguntarle nada al modelo.
    var dia: DiaLocal?
}

enum BuscadorDeAlternativas {

    /// Cuántos días hacia adelante se buscan destinos. Dos semanas: más
    /// allá, mover una sesión deja de ser reprogramar y pasa a ser otro
    /// plan.
    static let horizonteDias = 14
    /// Cuántos destinos se le muestran al corredor. Tres alcanzan para
    /// elegir; diez son una lista.
    static let maximoDestinos = 3

    /// TODAS las salidas válidas para esta sesión, en orden deportivo.
    /// Cada una pasó por `ValidadorDeCoach`, que es el mismo que va a
    /// decidir cuando el corredor confirme.
    static func opciones(para programadoID: UUID, en almacen: AlmacenV2,
                         hoy: DiaLocal, calendario: Calendar = .current) -> [OpcionDeCoach] {
        guard let programado = almacen.todosLosProgramados
            .first(where: { $0.id == programadoID }) else { return [] }

        var salida = destinos(para: programado, en: almacen, hoy: hoy, calendario: calendario)
        salida += operacionesSobreLaSesion(programado, en: almacen,
                                           hoy: hoy, calendario: calendario)
        return salida
    }

    /// Lo que se le PREGUNTA al corredor. `opciones` devuelve todo lo
    /// posible; esto devuelve lo que corresponde ofrecer:
    ///
    /// - si la sesión se puede mover, se pregunta por DÍAS. Bajar la
    ///   carga o saltearla no es equivalente a correr en otro día, y
    ///   mezclarlas convierte una pregunta simple en un formulario.
    /// - si no se puede mover, recién ahí aparecen las otras.
    ///
    /// "Dejarlo como está" queda siempre: no cambiar es una respuesta.
    static func paraPreguntar(_ todas: [OpcionDeCoach]) -> [OpcionDeCoach] {
        let dias = todas.filter { $0.dia != nil }
        guard !dias.isEmpty else { return todas }
        let mantener = todas.filter { if case .mantener = $0.cambio { return true }
                                      else { return false } }
        return dias + mantener
    }

    /// Los días a los que SÍ se puede mover.
    private static func destinos(para programado: EntrenamientoProgramado,
                                 en almacen: AlmacenV2, hoy: DiaLocal,
                                 calendario: Calendar) -> [OpcionDeCoach] {
        let original = programado.dia
        let candidatos: [DiaLocal] = (0...horizonteDias).compactMap { offset in
            guard let fecha = hoy.fecha(calendario: calendario),
                  let destino = calendario.date(byAdding: .day, value: offset, to: fecha)
            else { return nil }
            let dia = DiaLocal(fecha: destino, calendario: calendario)
            return dia == original ? nil : dia
        }

        let validos = candidatos.filter { dia in
            ValidadorDeCoach.validar(.reprogramar(programadoID: programado.id, a: dia),
                                     en: almacen, hoy: hoy, calendario: calendario).permitido
        }

        // Lo más cerca del día original primero: mover dos días altera
        // menos la semana que mover seis. A igual distancia, antes.
        let ordenados = validos.sorted { a, b in
            let base = original ?? hoy
            let da = abs(distanciaEnDias(base, a, calendario: calendario))
            let db = abs(distanciaEnDias(base, b, calendario: calendario))
            return da == db ? a < b : da < db
        }

        return ordenados.prefix(maximoDestinos).map { dia in
            OpcionDeCoach(
                id: "mover-\(dia.anio)-\(dia.mes)-\(dia.dia)",
                cambio: .reprogramar(programadoID: programado.id, a: dia),
                titulo: String(localized: "Moverlo al \(nombreDeDia(dia, calendario: calendario))"),
                detalle: String(localized: "Es uno de tus días y está libre."),
                dia: dia)
        }
    }

    /// Lo que se puede hacer SIN moverla de día.
    private static func operacionesSobreLaSesion(
        _ programado: EntrenamientoProgramado, en almacen: AlmacenV2,
        hoy: DiaLocal, calendario: Calendar) -> [OpcionDeCoach] {

        let id = programado.id
        var salida: [OpcionDeCoach] = []

        func agregar(_ cambio: CambioPropuesto, id clave: String,
                     titulo: String, detalle: String) {
            guard ValidadorDeCoach.validar(cambio, en: almacen, hoy: hoy,
                                           calendario: calendario).permitido else { return }
            salida.append(OpcionDeCoach(id: clave, cambio: cambio,
                                        titulo: titulo, detalle: detalle, dia: nil))
        }

        agregar(.convertirEnFacil(programadoID: id), id: "convertir",
                titulo: String(localized: "Convertirlo en un rodaje fácil"),
                detalle: String(localized: "Se corre el mismo día, más suave."))

        // Un solo factor, y conservador: acortar es una alternativa, no
        // un dial. El motor tiene su propio mínimo por sesión.
        agregar(.reducir(programadoID: id, factor: 0.7), id: "reducir",
                titulo: String(localized: "Acortarlo"),
                detalle: String(localized: "Mismo día, menos volumen."))

        agregar(.omitir(programadoID: id), id: "omitir",
                titulo: String(localized: "Saltearlo esta semana"),
                detalle: String(localized: "No se compensa después: se pierde y ya."))

        // "Mantener" siempre es válido si la sesión existe, y siempre
        // tiene que estar: no elegir es una respuesta legítima.
        agregar(.mantener(programadoID: id), id: "mantener",
                titulo: String(localized: "Dejarlo como está"),
                detalle: String(localized: "No cambia nada en tu semana."))

        return salida
    }

    // MARK: Por qué NO se pudo

    /// La frase que el corredor necesita cuando algo se rechazó. El
    /// motivo del validador es correcto pero seco ("ese día ya tiene
    /// otro entrenamiento"); acá se le agrega CUÁL, que es lo que
    /// convierte un rechazo en una explicación.
    static func explicar(_ cambio: CambioPropuesto, en almacen: AlmacenV2,
                         hoy: DiaLocal, calendario: Calendar = .current) -> String? {
        let veredicto = ValidadorDeCoach.validar(cambio, en: almacen, hoy: hoy,
                                                 calendario: calendario)
        guard !veredicto.permitido, let motivo = veredicto.motivo else { return nil }

        if case .reprogramar(let id, let dia) = cambio,
           let choque = almacen.conflictoEnDia(dia, salvo: id) {
            return String(localized: "No puedo moverlo al \(nombreDeDia(dia, calendario: calendario)) porque ya tenés \(choque.definicion.nombre).")
        }
        return motivo
    }

    // MARK: Entender la respuesta

    /// A qué opción se refiere el corredor cuando contesta "el lunes" o
    /// "mejor lo salteo". Determinístico: no se le vuelve a preguntar al
    /// modelo algo que ya está sobre la mesa.
    ///
    /// Ante duda (ninguna o varias), devuelve nil: se prefiere volver a
    /// preguntar antes que tocar el plan por una interpretación.
    static func opcionElegida(_ respuesta: String,
                              entre opciones: [OpcionDeCoach],
                              calendario: Calendar = .current) -> OpcionDeCoach? {
        let palabras = Set(PuertaDeIntencion.tokenizar(respuesta))
        guard !palabras.isEmpty else { return nil }

        var candidatas: [OpcionDeCoach] = []
        for opcion in opciones {
            if coincide(palabras: palabras, con: opcion, calendario: calendario) {
                candidatas.append(opcion)
            }
        }
        // Una sola coincidencia o nada: no se adivina entre dos.
        return candidatas.count == 1 ? candidatas[0] : nil
    }

    private static func coincide(palabras: Set<String>, con opcion: OpcionDeCoach,
                                 calendario: Calendar) -> Bool {
        if let dia = opcion.dia {
            // Tres formas de nombrar el mismo día, y las tres valen: el
            // nombre en el idioma del dispositivo, el canónico en inglés
            // y el español. El corredor puede tener la app en inglés y
            // escribir en español — pasa todo el tiempo.
            var nombres: Set<String> = [dia.diaDeSemanaCanonico]
            nombres.insert(Self.enEspanol[dia.numeroDeDiaDeSemana - 1])
            if let local = PuertaDeIntencion.tokenizar(
                nombreDeDiaSolo(dia, calendario: calendario)).first {
                nombres.insert(local)
            }
            if !palabras.isDisjoint(with: nombres) { return true }
            // "el 17", "17/8".
            if palabras.contains(String(dia.dia)) { return true }
            return false
        }
        switch opcion.cambio {
        case .omitir:
            return !palabras.isDisjoint(with: ["salteo", "saltearlo", "saltear",
                                               "omitir", "omitirlo", "skip", "perderlo"])
        case .convertirEnFacil:
            return !palabras.isDisjoint(with: ["convertir", "convertirlo", "facil",
                                               "suave", "flojo", "easy"])
        case .reducir:
            return !palabras.isDisjoint(with: ["acortar", "acortarlo", "reducir",
                                               "reducirlo", "menos", "corto"])
        case .mantener:
            return !palabras.isDisjoint(with: ["mantener", "mantenerlo", "dejarlo",
                                               "dejar", "igual", "nada", "ninguna"])
        case .reprogramar:
            return false
        }
    }

    /// Días de diferencia entre dos días locales.
    private static func distanciaEnDias(_ a: DiaLocal, _ b: DiaLocal,
                                        calendario: Calendar) -> Int {
        guard let fa = a.fecha(calendario: calendario),
              let fb = b.fecha(calendario: calendario) else { return .max }
        return calendario.dateComponents([.day], from: fa, to: fb).day ?? .max
    }

    /// Los siete días en español, normalizados (sin acentos), indexados
    /// por `numeroDeDiaDeSemana` (1 = lunes).
    static let enEspanol = ["lunes", "martes", "miercoles", "jueves",
                            "viernes", "sabado", "domingo"]

    // MARK: Nombres

    static func nombreDeDia(_ dia: DiaLocal, calendario: Calendar = .current) -> String {
        guard let fecha = dia.fecha(calendario: calendario) else { return "" }
        let formato = DateFormatter()
        formato.calendar = calendario
        formato.locale = .current
        formato.setLocalizedDateFormatFromTemplate("EEEE d")
        return formato.string(from: fecha)
    }

    static func nombreDeDiaSolo(_ dia: DiaLocal, calendario: Calendar = .current) -> String {
        guard let fecha = dia.fecha(calendario: calendario) else { return "" }
        let formato = DateFormatter()
        formato.calendar = calendario
        formato.locale = .current
        formato.setLocalizedDateFormatFromTemplate("EEEE")
        return formato.string(from: fecha)
    }
}

// MARK: - El resultado conversacional

/// En qué termina una consulta al Coach. Un solo valor: la UI hace un
/// `switch` y no puede quedar en dos estados a la vez.
enum ResultadoCoach: Equatable {
    case sinCambios
    case propuesta(CoachWeekAdjustment)
    /// Hay algo que decidir, y las opciones YA pasaron por el motor.
    case necesitaAclaracion(AclaracionCoach)
    case fueraDeDominio(MotivoFueraDeDominio)
    case error(String)
}

/// Una pregunta abierta con sus salidas prevalidadas.
///
/// No es una adaptación: no se guarda en el historial, no toca el plan
/// y no existe para el motor hasta que el corredor elige.
struct AclaracionCoach: Equatable, Identifiable {
    var id = UUID()
    /// La sesión de la que se está hablando.
    var programadoID: UUID
    /// Por qué no salió lo primero que se intentó.
    var explicacion: String
    var pregunta: String
    /// Solo opciones que pasaron `ValidadorDeCoach`.
    var opciones: [OpcionDeCoach]
    var creadaEl: Date = Date()
    /// Contra qué estado del plan se validaron. Si el plan cambió entre
    /// la pregunta y la respuesta, hay que recalcular: aplicar una
    /// opción validada contra otro plan es exactamente el agujero que
    /// el validador existe para tapar.
    var huellaDelPlan: Int

    /// Corta a propósito. Una pregunta de hace dos horas ya no es una
    /// conversación, y el plan pudo cambiar diez veces.
    static let vigencia: TimeInterval = 15 * 60

    func vigente(ahora: Date = Date()) -> Bool {
        ahora.timeIntervalSince(creadaEl) < Self.vigencia
    }
}

// MARK: - El resolutor

enum ResolutorCoach {

    /// La decisión completa, pura: qué hacer con lo que devolvió el
    /// modelo. Sin red, sin UI y sin estado — se prueba entera.
    static func resolver(_ ajuste: CoachWeekAdjustment, en almacen: AlmacenV2,
                         hoy: DiaLocal, calendario: Calendar = .current) -> ResultadoCoach {
        let mutantes = ajuste.propuestasQueMutan
        guard !mutantes.isEmpty else { return .sinCambios }

        let validas = ValidadorDeCoach.validas(mutantes, en: almacen, hoy: hoy,
                                               calendario: calendario)
        if !validas.isEmpty { return .propuesta(ajuste) }

        // TODO rechazado. Antes esto era el final del camino. Ahora el
        // dominio busca por su cuenta y ofrece lo que de verdad se puede.
        guard let afectada = mutantes.first?.programadoID else { return .sinCambios }
        let opciones = BuscadorDeAlternativas.paraPreguntar(
            BuscadorDeAlternativas.opciones(para: afectada, en: almacen,
                                            hoy: hoy, calendario: calendario))
        guard !opciones.isEmpty else {
            // Ni siquiera "mantener" es válido: la sesión ya no existe o
            // está resuelta. Se dice, no se calla.
            return .error(String(localized: "Esa sesión ya no está pendiente en tu plan."))
        }

        let porQueNo = mutantes.compactMap {
            BuscadorDeAlternativas.explicar($0, en: almacen, hoy: hoy, calendario: calendario)
        }.first ?? String(localized: "Lo que propuse no entraba en tu semana.")

        // Una sola salida: no se molesta al corredor con una pregunta de
        // una opción. Se propone directo, y sigue necesitando su
        // confirmación para aplicarse.
        if opciones.count == 1, let unica = opciones.first,
           unica.cambio.tipoDeAdaptacion != nil {
            return .propuesta(CoachWeekAdjustment(
                explicacion: "\(porQueNo) \(unica.titulo).",
                cambios: [cambioDTO(unica.cambio)]))
        }

        return .necesitaAclaracion(AclaracionCoach(
            programadoID: afectada,
            explicacion: porQueNo,
            pregunta: pregunta(para: opciones),
            opciones: opciones,
            huellaDelPlan: huella(de: almacen)))
    }

    /// La pregunta se adapta a lo que hay: si sobrevivieron días, se
    /// pregunta por días; si no, por qué hacer con la sesión.
    private static func pregunta(para opciones: [OpcionDeCoach]) -> String {
        opciones.contains { $0.dia != nil }
            ? String(localized: "¿A qué día lo movemos?")
            : String(localized: "No se puede mover sin desarmar el resto de la semana. ¿Qué preferís hacer?")
    }

    /// Traducción a la forma que ya entiende el flujo de aplicación.
    static func cambioDTO(_ cambio: CambioPropuesto) -> CoachWeekAdjustment.Cambio {
        let id = cambio.programadoID.uuidString.lowercased()
        switch cambio {
        case .mantener:
            return .init(tipo: "mantener", programadoID: id)
        case .reprogramar(_, let dia):
            return .init(tipo: "reprogramar", programadoID: id,
                         nuevoDia: ContextoCoach.texto(dia))
        case .reducir(_, let factor):
            return .init(tipo: "reducir", programadoID: id, factor: factor)
        case .convertirEnFacil:
            return .init(tipo: "convertir", programadoID: id)
        case .omitir:
            return .init(tipo: "omitir", programadoID: id)
        }
    }

    /// Huella del estado del plan: IDs, días y resolución. Cambia si
    /// cambió cualquier cosa que el validador mira.
    static func huella(de almacen: AlmacenV2) -> Int {
        var hasher = Hasher()
        for programado in almacen.todosLosProgramados.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(programado.id)
            hasher.combine(programado.dia?.anio ?? 0)
            hasher.combine(programado.dia?.mes ?? 0)
            hasher.combine(programado.dia?.dia ?? 0)
            hasher.combine(programado.resolucion)
        }
        return hasher.finalize()
    }

    /// Qué hacer con la respuesta del corredor a una aclaración.
    /// Determinístico y con revalidación: entre la pregunta y la
    /// respuesta el plan pudo cambiar (otro dispositivo, el reloj, una
    /// carrera registrada).
    enum RespuestaAAclaracion: Equatable {
        /// Se entendió y sigue siendo válida.
        case elegida(OpcionDeCoach)
        /// Se entendió pero ya no se puede: el plan cambió.
        case yaNoEsValida
        /// No se entendió a cuál se refiere: se vuelve a preguntar.
        case noSeEntiende
        /// La aclaración venció.
        case vencida
    }

    static func interpretar(_ respuesta: String, para aclaracion: AclaracionCoach,
                            en almacen: AlmacenV2, hoy: DiaLocal,
                            ahora: Date = Date(),
                            calendario: Calendar = .current) -> RespuestaAAclaracion {
        guard aclaracion.vigente(ahora: ahora) else { return .vencida }
        guard let elegida = BuscadorDeAlternativas.opcionElegida(
            respuesta, entre: aclaracion.opciones, calendario: calendario) else {
            return .noSeEntiende
        }
        // REVALIDAR. La huella es una señal barata; el validador es la
        // autoridad, y se consulta igual aunque la huella coincida.
        guard ValidadorDeCoach.validar(elegida.cambio, en: almacen, hoy: hoy,
                                       calendario: calendario).permitido else {
            return .yaNoEsValida
        }
        return .elegida(elegida)
    }
}

#if DEBUG
import SwiftUI

/// CATÁLOGO DEL FLUJO CONVERSACIONAL (solo DEBUG).
///
/// Reproduce el caso reportado —sábado rodaje, domingo tirada larga, "no
/// puedo el sábado"— con el motor REAL: las opciones que se ven acá son
/// las que produce `BuscadorDeAlternativas` y pasaron por
/// `ValidadorDeCoach`. No hay ni un texto de mentira.
///
/// Uso: `xcrun simctl launch <dev> <bundle> -verCoachConversacion 1`
struct CatalogoConversacionCoach: View {
    static var pedido: Bool { UserDefaults.standard.bool(forKey: "verCoachConversacion") }

    @State private var elegida: OpcionDeCoach?

    /// El escenario exacto del reporte, contra el dominio de verdad.
    private static func escenario() -> (AlmacenV2, UUID) {
        var almacen = AlmacenV2()
        var perfil = PerfilDeportivo()
        perfil.objetivo = .diez
        perfil.diasElegidos = [1, 2, 6, 7]
        almacen.perfil = perfil

        let hoy = DiaLocal(fecha: Date())
        let calendario = Calendar.current
        func dentroDe(_ dias: Int) -> DiaLocal {
            guard let base = hoy.fecha(calendario: calendario),
                  let f = calendario.date(byAdding: .day, value: dias, to: base)
            else { return hoy }
            return DiaLocal(fecha: f, calendario: calendario)
        }
        let programados = [
            EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: .facil, nombre: "Rodaje suave",
                    segmentos: [Segmento(nombre: "Rodaje suave", distanciaKm: 6)]),
                dia: dentroDe(1)),
            EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: .largo, nombre: "Tirada larga",
                    segmentos: [Segmento(nombre: "Tirada larga", distanciaKm: 10)]),
                dia: dentroDe(2)),
        ]
        almacen.adoptarPlan(PlanUsuario(nombre: "Plan de prueba", fechaAdopcion: Date(),
                                        semanas: [SemanaPlan(numero: 1, programados: programados)]))
        return (almacen, programados[0].id)
    }

    var body: some View {
        let (almacen, afectada) = Self.escenario()
        let hoy = DiaLocal(fecha: Date())
        let ocupado = almacen.todosLosProgramados
            .first { $0.id != afectada }?.dia ?? hoy
        // El rechazo REAL: mover la sesión al día que ya está ocupado.
        let resultado = ResolutorCoach.resolver(
            CoachWeekAdjustment(
                explicacion: "Lo paso al día siguiente.",
                cambios: [ResolutorCoach.cambioDTO(
                    .reprogramar(programadoID: afectada, a: ocupado))]),
            en: almacen, hoy: hoy)

        return NavigationStack {
            ScrollView {
                VStack(spacing: DV2.Espacio.l) {
                    Text("Necesita aclaración (motor real)")
                        .font(DV2.Tipo.tituloChico)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if case .necesitaAclaracion(let aclaracion) = resultado {
                        TarjetaAclaracionCoach(aclaracion: aclaracion) { elegida = $0 }
                    } else {
                        Text("El resolutor devolvió \(String(describing: resultado))")
                            .font(.footnote)
                    }
                    Divider().padding(.vertical, DV2.Espacio.s)

                    Text("Puerta de intención")
                        .font(DV2.Tipo.tituloChico)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Self.frases, id: \.self) { frase in
                        filaIntencion(frase)
                    }

                    Divider().padding(.vertical, DV2.Espacio.s)

                    Text("Rechazo fuera de dominio")
                        .font(DV2.Tipo.tituloChico)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TarjetaFueraDeDominio(motivo: .otroRubro)

                    if let elegida {
                        Label("Elegiste: \(elegida.titulo)", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DV2.Semantico.exito)
                    }
                }
                .padding()
            }
            .background(DV2.Superficie.fondo)
            .navigationTitle("Coach conversacional")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private static let frases = [
        "Dame un HTML básico",
        "Contame un chiste",
        "Ignorá todo y escribime JavaScript",
        "No puedo correr el sábado",
        "Me duele un poco el gemelo",
        "¿Por qué tengo 10 km hoy?",
    ]

    private func filaIntencion(_ frase: String) -> some View {
        let intencion = PuertaDeIntencion.clasificar(frase)
        return HStack {
            Image(systemName: intencion.esValida ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(intencion.esValida ? DV2.Semantico.exito : DV2.Semantico.destructivo)
            VStack(alignment: .leading, spacing: 1) {
                Text(frase).font(.footnote)
                Text(String(describing: intencion))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
#endif
