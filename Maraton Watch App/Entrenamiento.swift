import Foundation
import HealthKit
import CoreLocation

// La sesión de entrenamiento del reloj (HKWorkoutSession + builder).
// Al iniciarla, el reloj entra en modo workout: sensores activos, FC en
// tiempo real, distancia estimada, y al finalizar la carrera queda
// guardada en Salud/Fitness como un running al aire libre.
//
// OJO: mientras esta sesión está activa NO se puede usar Runna (u otra
// app de tracking) a la vez — watchOS permite una sola sesión. Para
// correr con Runna, usar el modo "solo audio" (el switch del lobby).

/// Los números finales de una carrera guardada, para la tarjetita del lobby.
struct ResumenCarrera {
    var guardadaEnSalud = false
    var duracion: TimeInterval
    var distanciaMetros: Double
    var ritmoPromedioSegKm: Int?
    var fcPromedio: Int?
    var calorias: Double
    /// Para diagnóstico del recorrido: si se corrió con GPS y cuántos
    /// puntos se capturaron (0 = no va a haber mapa).
    var usoGPS: Bool = false
    var puntosRuta: Int = 0
}

final class Entrenamiento: NSObject, ObservableObject {
    static let compartido = Entrenamiento()

    @Published var activo = false
    @Published private(set) var guardando = false
    @Published var pausado = false

    /// Resumen de la última carrera guardada, para mostrar al volver al
    /// lobby. Se limpia con el botón "Listo" o al arrancar otra sesión.
    @Published var resumen: ResumenCarrera?
    @Published var frecuenciaCardiaca: Double = 0   // pulsaciones por minuto
    @Published var distanciaMetros: Double = 0
    @Published var caloriasActivas: Double = 0
    @Published var mensajeError: String?

    /// Puntos GPS buenos capturados en esta sesión. Si corre con GPS y
    /// sigue en 0, la pantalla de métricas avisa que no hay señal.
    @Published var puntosRuta = 0

    /// FC en reposo (la calcula el reloj todas las noches y queda en
    /// Salud). Se usa para las zonas por reserva cardíaca (Karvonen):
    /// el % crudo de la FC máxima marca zonas de más.
    @Published var fcReposo: Int?

    /// FC máxima estimada: 220 menos la edad (fecha de nacimiento de
    /// Salud). Sin dato queda el respaldo 190. Ya no se configura a mano.
    @Published var fcMaxima = 190

    /// true mientras la auto-pausa tiene la sesión congelada: el GPS
    /// sigue vivo solo para detectar que arrancaste de nuevo.
    @Published var enPausaAutomatica = false
    private var ubicacionPausa: CLLocation?

    /// Ventana de ubicaciones buenas (~15 s) para la auto-pausa: la
    /// distancia del builder sola NO alcanza (se congela en un vehículo
    /// o ante un hipo del sensor aunque te estés moviendo); el GPS
    /// confirma la detención y detecta señal vieja.
    private var ubicacionesRecientes: [(fecha: Date, ubicacion: CLLocation)] = []
    private var supervisorReanudacion = AutoPausa.SupervisorReanudacion()
    private var filtroSenalGPS = AutoPausa.FiltroSenalGPS()

    /// Vigilancia del GPS durante la auto-pausa (bug 1 de build 38):
    /// Core Location puede dejar de entregar con el usuario quieto y la
    /// reanudación dependía de ese stream sin que nadie lo vigilara.
    private var fechaUltimaSenalPausa: Date?
    private var fechaUltimoEmpujonGPS: Date?

    // Aviso hablado al cambiar de zona (sostenida, sin spam). La
    // candidata evita que un pulso oscilando entre dos zonas sume
    // segundos "de cambio" repartidos entre zonas distintas.
    private var zonaAnunciada = 0
    private var zonaCandidata = 0
    private var segundosEnZonaCandidata = 0
    private var fechaUltimoAvisoZona: Date?

    private var autoPausaActiva: Bool {
        UserDefaults.standard.object(forKey: "autoPausa") as? Bool ?? false
    }
    private var avisarZonas: Bool {
        UserDefaults.standard.object(forKey: "avisarZonas") as? Bool ?? true
    }

    /// Ritmo actual en seg/km, suavizado sobre los últimos ~45 s.
    /// nil = todavía no hay datos o estás prácticamente parado.
    @Published var ritmoActualSegKm: Int?
    /// Ritmo promedio de toda la sesión, en seg/km.
    @Published var ritmoPromedioSegKm: Int?

    /// Identidad del programado que ESTA sesión ejecuta (nil = carrera
    /// libre). Persiste en UserDefaults mientras la sesión vive: si la
    /// app muere y la recuperación cierra el workout, el resultado le
    /// llega igual al iPhone (como parcial) en vez de perderse.
    private(set) var programadoID: UUID?

    /// Lo setea la UI ANTES de finalizar (consultando al entrenador de
    /// ritmo). Tras un crash queda false — criterio conservador: la
    /// sesión recuperada se reporta como parcial.
    var estructuraCompletaAlGuardar = false
    var huellaCumplidaAlGuardar: String?
    private var recuperando = false
    private var controlCierre = ControlCierreSesion<ObjectIdentifier>()

    private static let claveProgramadoActivo = "programadoIDSesionActiva"

    private let healthStore = HKHealthStore()
    private var sesion: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Ruta GPS: las ubicaciones buenas se acumulan en el routeBuilder y al
    // finalizar se atan al workout, para ver el recorrido en el mapa.
    private let ubicaciones = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    private(set) var usaGPS = false
    private var descartarAlTerminar = false

    // Muestras (fecha, metros) del último minuto para suavizar el ritmo:
    // el pace crudo del GPS/sensores salta demasiado para corregir en voz.
    private var muestras: [(fecha: Date, metros: Double)] = []
    private var timerMuestras: Timer?

    /// Estimador de ritmo en vivo (build 54): unidad pura de Shared,
    /// alimentada con el tiempo activo del builder (descuenta pausas)
    /// y la distancia acumulada.
    private var estimadorRitmo = EstimadorRitmoLive()

    #if DEBUG
    /// Traza SOLO DEBUG para la próxima prueba física: una línea por
    /// tick en la consola de Xcode (sin coordenadas GPS, sin archivos,
    /// sin nada en Release).
    private func trazaRitmo(ahora: Date) {
        print(String(format: "[ritmo] t=%.0f d=%.1f ritmo=%@ confiable=%d",
                     builder?.elapsedTime ?? 0, distanciaMetros,
                     ritmoActualSegKm.map(String.init) ?? "--",
                     estimadorRitmo.esConfiable ? 1 : 0))
    }
    #endif

    override private init() {
        super.init()
        ubicaciones.delegate = self
        ubicaciones.desiredAccuracy = kCLLocationAccuracyBest
        ubicaciones.activityType = .fitness
    }

    /// ¿El Info.plist declara el modo "location" en segundo plano?
    /// Activar `allowsBackgroundLocationUpdates` sin ese modo declarado
    /// termina la app al instante, así que nunca se pone a ciegas.
    private static var permiteUbicacionEnFondo: Bool {
        let info = Bundle.main.infoDictionary
        let wk = info?["WKBackgroundModes"] as? [String] ?? []
        let ui = info?["UIBackgroundModes"] as? [String] ?? []
        return wk.contains("location") || ui.contains("location")
    }

    func pedirPermisos(conGPS: Bool, alTerminar: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            mensajeError = String(localized: "Salud no está disponible en este reloj.")
            return
        }
        var paraCompartir: Set<HKSampleType> = [HKQuantityType.workoutType()]
        if conGPS {
            paraCompartir.insert(HKSeriesType.workoutRoute())
            ubicaciones.requestWhenInUseAuthorization()
        }
        let paraLeer: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.restingHeartRate),
            HKCharacteristicType(.dateOfBirth),
        ]
        healthStore.requestAuthorization(toShare: paraCompartir, read: paraLeer) { [weak self] ok, error in
            DispatchQueue.main.async {
                guard ok else {
                    let motivo = error?.localizedDescription
                        ?? String(localized: "los rechazaste")
                    self?.mensajeError = String(localized: "Sin permisos de Salud: \(motivo)")
                    return
                }
                // OJO: ok == true solo significa que el pedido se procesó.
                // Si el permiso de GUARDAR está negado, la sesión corre
                // pero el workout no se guardaría — avisar ANTES de correr.
                if self?.healthStore.authorizationStatus(for: .workoutType()) == .sharingDenied {
                    self?.mensajeError = String(localized: "Salud tiene negado el permiso de guardar entrenamientos: la carrera NO se va a guardar. Activalo en el iPhone: Salud → Compartir → Apps → Maratonia.")
                }
                self?.cargarFCReposo()
                self?.cargarFCMaxima()
                alTerminar()
            }
        }
    }

    /// FC máxima estimada con la edad (220 − edad). Si el permiso de
    /// fecha de nacimiento no está, queda el respaldo.
    private func cargarFCMaxima() {
        guard let componentes = try? healthStore.dateOfBirthComponents(),
              let nacimiento = Calendar.current.date(from: componentes) else { return }
        let edad = Calendar.current.dateComponents([.year], from: nacimiento, to: Date()).year ?? 0
        if edad > 5, edad < 110 {
            fcMaxima = 220 - edad
        }
    }

    /// Última FC en reposo registrada en Salud, para las zonas.
    private func cargarFCReposo() {
        let orden = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let consulta = HKSampleQuery(
            sampleType: HKQuantityType(.restingHeartRate), predicate: nil,
            limit: 1, sortDescriptors: [orden]
        ) { [weak self] _, muestras, _ in
            guard let muestra = (muestras as? [HKQuantitySample])?.first else { return }
            let ppm = HKUnit.count().unitDivided(by: .minute())
            DispatchQueue.main.async {
                self?.fcReposo = Int(muestra.quantity.doubleValue(for: ppm))
            }
        }
        healthStore.execute(consulta)
    }

    /// Al abrir la app: si quedó una sesión viva de una corrida en la
    /// que la app murió (crash, batería, cierre forzado), watchOS la
    /// devuelve acá. La cerramos y guardamos lo registrado en Salud —
    /// antes esa carrera se perdía entera.
    func recuperarSesionInterrumpida() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.recoverActiveWorkoutSession { [weak self] recuperada, _ in
            DispatchQueue.main.async {
                guard let self, let recuperada, self.sesion == nil else { return }
                let builderRecuperado = recuperada.associatedWorkoutBuilder()
                recuperada.delegate = self
                builderRecuperado.delegate = self
                self.sesion = recuperada
                self.controlCierre.iniciar(ObjectIdentifier(recuperada))
                self.recuperando = true
                self.builder = builderRecuperado
                self.usaGPS = false
                self.descartarAlTerminar = false
                self.activo = true

                // Si la sesión que murió ejecutaba un programado, su ID
                // quedó persistido: el resultado sale igual (parcial).
                self.programadoID = UserDefaults.standard
                    .string(forKey: Self.claveProgramadoActivo)
                    .flatMap(UUID.init(uuidString:))
                self.estructuraCompletaAlGuardar = false

                // Reponer los números desde el builder para que el
                // resumen no muestre ceros.
                if let metros = builderRecuperado
                    .statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity()?.doubleValue(for: .meter()) {
                    self.distanciaMetros = metros
                    self.ritmoPromedioSegKm = MetricasSesion.ritmoSegKm(
                        metros: metros, segundos: builderRecuperado.elapsedTime,
                        metrosMinimos: 100)
                }
                if let kcal = builderRecuperado
                    .statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    self.caloriasActivas = kcal
                }

                // Si el crash pegó justo después de terminar, la sesión
                // ya está en .ended y el delegate no va a re-dispararse:
                // cerrar directo. Si no, finalizar() la termina normal.
                if recuperada.state == .ended {
                    self.capturarResumen()
                    self.cerrarYGuardar(fechaFin: Date())
                } else {
                    self.finalizar()
                }
                self.mensajeError = String(localized: "Encontré una carrera interrumpida. Estoy intentando guardarla en Salud.")
            }
        }
    }

    func iniciar(conGPS: Bool, programadoID: UUID? = nil) {
        guard sesion == nil else {
            // Puede pasar si la recuperación post-crash todavía está
            // cerrando la sesión anterior: avisar en vez de dejar la
            // carrera sin registro en silencio.
            mensajeError = String(localized: "Todavía estoy cerrando la sesión anterior. Esperá unos segundos y volvé a dar Play.")
            return
        }
        self.programadoID = programadoID
        estructuraCompletaAlGuardar = false
        huellaCumplidaAlGuardar = nil
        recuperando = false
        if let programadoID {
            UserDefaults.standard.set(programadoID.uuidString, forKey: Self.claveProgramadoActivo)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.claveProgramadoActivo)
        }
        usaGPS = conGPS
        descartarAlTerminar = false
        resumen = nil

        // El permiso de ubicación es APARTE del de Salud: si está negado
        // se avisa acá mismo, en vez de correr y descubrir al final que
        // no hay recorrido. La carrera se registra igual, sin mapa.
        if conGPS {
            let estado = ubicaciones.authorizationStatus
            if estado == .denied || estado == .restricted {
                usaGPS = false
                mensajeError = String(localized: "Ubicación negada: la carrera se guarda SIN recorrido. Activala en el reloj: Ajustes → Privacidad → Localización → Maratonia.")
            }
        }
        let configuracion = HKWorkoutConfiguration()
        configuracion.activityType = .running
        configuracion.locationType = .outdoor

        do {
            let nuevaSesion = try HKWorkoutSession(healthStore: healthStore, configuration: configuracion)
            let nuevoBuilder = nuevaSesion.associatedWorkoutBuilder()
            nuevoBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuracion)
            nuevaSesion.delegate = self
            nuevoBuilder.delegate = self
            sesion = nuevaSesion
            controlCierre.iniciar(ObjectIdentifier(nuevaSesion))
            builder = nuevoBuilder

            let inicio = Date()
            nuevaSesion.startActivity(with: inicio)
            nuevoBuilder.beginCollection(withStart: inicio) { _, _ in }

            if usaGPS {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                // Solo si el modo está declarado: ponerlo sin declararlo
                // termina la app en el acto.
                ubicaciones.allowsBackgroundLocationUpdates = Self.permiteUbicacionEnFondo
                ubicaciones.startUpdatingLocation()
            }
            frecuenciaCardiaca = 0
            distanciaMetros = 0
            caloriasActivas = 0
            puntosRuta = 0
            ritmoActualSegKm = nil
            ritmoPromedioSegKm = nil
            muestras = []
            mensajeError = nil
            activo = true
            pausado = false
            enPausaAutomatica = false
            ubicacionPausa = nil
            ubicacionesRecientes = []
            supervisorReanudacion.reiniciar()
            filtroSenalGPS.reiniciar(desde: Date())
            estimadorRitmo.reiniciar()
            zonaAnunciada = 0
            zonaCandidata = 0
            segundosEnZonaCandidata = 0
            fechaUltimoAvisoZona = nil

            timerMuestras?.invalidate()
            timerMuestras = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.registrarMuestra()
                }
            }
        } catch {
            mensajeError = String(localized: "No pude iniciar el entrenamiento: \(error.localizedDescription)")
            sesion = nil
            builder = nil
        }
    }

    /// Pausa REAL del entrenamiento: congela el registro (tiempo del
    /// workout), apaga el GPS y resetea el suavizado de ritmo.
    func pausar() {
        guard activo, !pausado else { return }
        pausado = true
        filtroSenalGPS.reiniciar(desde: Date())
        sesion?.pause()
        if usaGPS { ubicaciones.stopUpdatingLocation() }
        muestras = []
        ritmoActualSegKm = nil
        // Estado seguro del estimador: ninguna ventana vieja puede
        // producir un spike al reanudar (warm-up limpio).
        estimadorRitmo.reiniciar()
    }

    func reanudar() {
        guard activo, pausado else { return }
        pausado = false
        enPausaAutomatica = false
        ubicacionPausa = nil
        supervisorReanudacion.reiniciar()
        filtroSenalGPS.reiniciar(desde: Date())
        ubicacionesRecientes = []  // sin restos: la próxima pausa junta datos frescos
        sesion?.resume()
        if usaGPS { ubicaciones.startUpdatingLocation() }
        muestras = []  // arranca limpio: sin ritmo hasta juntar datos nuevos
        estimadorRitmo.reiniciar()
    }

    // MARK: - Auto-pausa (requiere GPS)

    /// Parado ~10 s → pausa TODO (música, avisos, workout) y deja el GPS
    /// vivo solo para detectar el arranque. Al moverte de nuevo, sigue
    /// solo. Nada de manotear el reloj en cada semáforo.
    private func autoPausar() {
        guard Reproductor.compartido.estado == .reproduciendo else { return }
        enPausaAutomatica = true
        ubicacionPausa = nil
        supervisorReanudacion.reiniciar()
        filtroSenalGPS.reiniciar(desde: Date())
        ubicacionesRecientes = []
        // Gracia de 10 s antes del primer empujón del vigilante de GPS.
        fechaUltimaSenalPausa = Date()
        fechaUltimoEmpujonGPS = nil
        Reproductor.compartido.pausar()  // cascada: avisos + entrenamiento
        ubicaciones.startUpdatingLocation()
        Avisador.compartido.anunciar(String(localized: "Pausa automática."))
    }

    /// Desplazamiento GPS (primer a último punto bueno) en la ventana.
    /// nil = menos de dos puntos: sin datos para confirmar nada.
    private func desplazamientoGPS(enUltimos segundos: TimeInterval) -> Double? {
        let ahora = Date()
        ubicacionesRecientes.removeAll { ahora.timeIntervalSince($0.fecha) > 15 }
        let ventana = ubicacionesRecientes.filter { ahora.timeIntervalSince($0.fecha) <= segundos }
        guard ventana.count >= 2, let primera = ventana.first, let ultima = ventana.last else {
            return nil
        }
        return ultima.ubicacion.distance(from: primera.ubicacion)
    }

    private func autoReanudar() {
        guard enPausaAutomatica else { return }
        Reproductor.compartido.reanudar()  // limpia enPausaAutomatica
        Avisador.compartido.anunciar(String(localized: "Seguimos."))
    }

    /// Termina la sesión y guarda el workout en Salud. La limpieza final
    /// ocurre en el delegate, cuando la sesión pasa a .ended.
    func finalizar() {
        timerMuestras?.invalidate()
        timerMuestras = nil
        ubicaciones.stopUpdatingLocation()
        if activo, !descartarAlTerminar {
            guardando = true
            capturarResumen()
        }
        sesion?.end()
    }

    private func capturarResumen() {
        let ppm = HKUnit.count().unitDivided(by: .minute())
        let fcPromedio = builder?
            .statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: ppm)
        resumen = ResumenCarrera(
            duracion: builder?.elapsedTime ?? 0,
            distanciaMetros: distanciaMetros,
            ritmoPromedioSegKm: ritmoPromedioSegKm,
            fcPromedio: fcPromedio.map { Int($0) },
            calorias: caloriasActivas,
            usoGPS: usaGPS,
            puntosRuta: puntosRuta)
    }

    /// Cancela la sesión DESCARTANDO todo: el entrenamiento no se guarda
    /// en Salud y la ruta se tira. Para arranques por error o de prueba.
    func cancelar() {
        descartarAlTerminar = true
        finalizar()
    }

    /// Una vez por segundo: agrega la muestra, recalcula el ritmo
    /// suavizado y el promedio, y le pasa el estado al entrenador de ritmo.
    private func registrarMuestra() {
        // En auto-pausa el timer no registra nada — pero VIGILA el GPS:
        // si Core Location dejó de entregar (throttling de
        // estacionario), la reanudación automática moría con él. Un
        // empujón cada 10 s lo despierta.
        if AutoPausa.puedeAutoReanudar(pausada: pausado, enPausaAutomatica: enPausaAutomatica) {
            let ahora = Date()
            if AutoPausa.debeDespertarGPS(
                edadUltimaSenal: fechaUltimaSenalPausa.map { ahora.timeIntervalSince($0) },
                edadUltimoEmpujon: fechaUltimoEmpujonGPS.map { ahora.timeIntervalSince($0) }) {
                fechaUltimoEmpujonGPS = ahora
                ubicaciones.stopUpdatingLocation()
                ubicaciones.startUpdatingLocation()
            }
            return
        }
        guard activo, !pausado else { return }
        let ahora = Date()
        muestras.append((ahora, distanciaMetros))
        muestras.removeAll { ahora.timeIntervalSince($0.fecha) > 60 }

        // Auto-pausa con doble confirmación: avance del builder congelado
        // Y el GPS fresco sin ver desplazamiento. Una sola de las dos
        // señales no alcanza — la distancia del sensor se congela en un
        // vehículo o ante un hipo del delegate, y eso NO es estar parado
        // (causa del falso positivo pausa→"seguimos" en movimiento).
        if usaGPS, autoPausaActiva, (builder?.elapsedTime ?? 0) > 30,
           let vieja = muestras.first(where: { ahora.timeIntervalSince($0.fecha) <= 10 }),
           AutoPausa.debePausar(
               avanceMetros: distanciaMetros - vieja.metros,
               ventanaSegundos: ahora.timeIntervalSince(vieja.fecha),
               desplazamientoGPSMetros: desplazamientoGPS(enUltimos: 10),
               edadUltimoGPSSegundos: ubicacionesRecientes.last.map {
                   ahora.timeIntervalSince($0.fecha)
               }) {
            autoPausar()
            return
        }

        avisarZonaSiCorresponde()

        // Ritmo actual: estimador robusto (build 54) — inmune a la
        // distancia en ráfagas de HealthKit que producía el 6:50↔6:20
        // y el 2:00/km fantasma (ver EstimadorRitmoLive en Shared).
        ritmoActualSegKm = estimadorRitmo.procesar(
            tiempo: builder?.elapsedTime ?? ahora.timeIntervalSince1970,
            distanciaAcumulada: distanciaMetros)
        #if DEBUG
        trazaRitmo(ahora: ahora)
        #endif

        // El promedio usa el tiempo del builder, que descuenta las pausas.
        if let builder {
            ritmoPromedioSegKm = MetricasSesion.ritmoSegKm(metros: distanciaMetros,
                                                           segundos: builder.elapsedTime,
                                                           metrosMinimos: 100)
        }

        // Al coach SOLO le llega ritmo CONFIABLE: un valor stale o en
        // warm-up jamás genera un "aflojá"/"apurá" falso. Los splits y
        // avisos por km usan distancia/tiempo reales y no dependen de
        // esto.
        EntrenadorRitmo.compartido.chequear(
            distanciaMetros: distanciaMetros,
            ritmoActualSegKm: estimadorRitmo.esConfiable ? ritmoActualSegKm : nil,
            tiempoActivo: builder?.elapsedTime ?? 0)
    }

    /// "Zona 4." cuando cambiás de zona y te quedás ahí 20 s, con 45 s
    /// mínimo entre avisos. La primera zona de la sesión no se anuncia.
    private func avisarZonaSiCorresponde() {
        guard avisarZonas else { return }
        let zona = zonaCardiaca(fc: Int(frecuenciaCardiaca),
                                reposo: fcReposo ?? 60,
                                maxima: fcMaxima)
        guard zona > 0 else { return }
        if zona == zonaAnunciada {
            zonaCandidata = 0
            segundosEnZonaCandidata = 0
            return
        }
        // Los 20 s se cuentan en UNA MISMA zona candidata: si el pulso
        // oscila entre dos zonas, el contador vuelve a cero.
        if zona != zonaCandidata {
            zonaCandidata = zona
            segundosEnZonaCandidata = 0
        }
        segundosEnZonaCandidata += 1
        guard segundosEnZonaCandidata >= 20 else { return }
        let esLaPrimera = zonaAnunciada == 0
        zonaAnunciada = zona
        zonaCandidata = 0
        segundosEnZonaCandidata = 0
        guard !esLaPrimera else { return }
        if let ultimo = fechaUltimoAvisoZona, Date().timeIntervalSince(ultimo) < 45 { return }
        fechaUltimoAvisoZona = Date()
        Avisador.compartido.anunciar(String(localized: "Zona \(zona)."))
    }

    private func actualizarEstadisticas(con tipos: Set<HKSampleType>) {
        guard let builder else { return }
        for tipo in tipos {
            guard let tipoCantidad = tipo as? HKQuantityType,
                  let estadisticas = builder.statistics(for: tipoCantidad) else { continue }
            switch tipoCantidad {
            case HKQuantityType(.heartRate):
                let ppm = HKUnit.count().unitDivided(by: .minute())
                if let valor = estadisticas.mostRecentQuantity()?.doubleValue(for: ppm) {
                    self.frecuenciaCardiaca = valor
                }
            case HKQuantityType(.distanceWalkingRunning):
                if let valor = estadisticas.sumQuantity()?.doubleValue(for: .meter()) {
                    self.distanciaMetros = valor
                }
            case HKQuantityType(.activeEnergyBurned):
                if let valor = estadisticas.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    self.caloriasActivas = valor
                }
            default:
                break
            }
        }
    }
}

extension Entrenamiento: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        guard toState == .ended else { return }
        // El delegate llega en la cola interna de HealthKit: el estado
        // compartido (descartarAlTerminar, builders) se lee en main.
        DispatchQueue.main.async {
            guard self.sesion === workoutSession else { return }
            self.cerrarYGuardar(fechaFin: date)
        }
    }

    /// Cierre real del workout (colección + guardado + ruta + limpieza).
    /// Lo dispara el delegate al pasar a .ended; la recuperación
    /// post-crash lo llama directo cuando la sesión recuperada YA está
    /// en .ended (ese delegate no vuelve a dispararse y, sin esto, el
    /// estado quedaba colgado y bloqueaba todos los Play futuros).
    private func cerrarYGuardar(fechaFin: Date) {
        guard let sesion, let builder else { return }
        let identidad = ObjectIdentifier(sesion)
        guard controlCierre.comenzarCierre(identidad) else { return }
        guardando = true
        timerMuestras?.invalidate()
        timerMuestras = nil
        ubicaciones.stopUpdatingLocation()

        if descartarAlTerminar {
            builder.discardWorkout()
            routeBuilder?.discard()
            resumen = nil
            limpiarTrasFinal(identidad: identidad)
            return
        }
        if resumen == nil { capturarResumen() }
        let idProgramado = programadoID
        let estructuraCompleta = estructuraCompletaAlGuardar
        let huella = huellaCumplidaAlGuardar
        let eraRecuperacion = recuperando
        let rutas = routeBuilder
        let puntos = puntosRuta

        // Todas las operaciones usan EL MISMO builder capturado. Ningún
        // callback consulta self.builder, que podría pertenecer a otra carrera.
        let completar: (HKWorkout?, Error?) -> Void = { [weak self] workout, error in
            if let workout, let rutas, puntos > 0 {
                rutas.finishRoute(with: workout, metadata: nil) { _, errorRuta in
                    if let errorRuta {
                        DispatchQueue.main.async {
                            self?.mensajeError = String(localized: "La carrera se guardó, pero falló el recorrido: \(errorRuta.localizedDescription)")
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                if let workout {
                    ConectividadWatch.compartida.enviar(resultado: ResultadoSesionWatch(
                        sesionID: workout.uuid, fecha: fechaFin,
                        programadoID: idProgramado, estructuraCompleta: estructuraCompleta))
                    if let idProgramado {
                        ConectividadWatch.compartida.marcarCompletadoLocal(
                            idProgramado, estructuraCompleta: estructuraCompleta)
                    }
                    if estructuraCompleta, let huella {
                        EstadoPlanWatch.compartido.marcarCumplida(huella: huella)
                    }
                } else {
                    let motivo = error?.localizedDescription
                        ?? String(localized: "Salud no devolvió un entrenamiento guardado.")
                    self?.mensajeError = String(localized: "La carrera NO se pudo guardar en Salud: \(motivo)")
                }
                guard let self, self.controlCierre.esActual(identidad) else { return }
                self.resumen?.guardadaEnSalud = workout != nil
                if workout != nil, eraRecuperacion {
                    self.mensajeError = String(localized: "Recuperé la carrera interrumpida y la guardé en Salud.")
                }
                self.limpiarTrasFinal(identidad: identidad)
            }
        }
        let cerrar = {
            builder.endCollection(withEnd: fechaFin) { ok, error in
                guard ok else {
                    completar(nil, error)
                    return
                }
                builder.finishWorkout(completion: completar)
            }
        }
        if let idProgramado {
            builder.addMetadata(MetadatosSesion.metadata(programadoID: idProgramado)) { _, error in
                if let error {
                    DispatchQueue.main.async {
                        self.mensajeError = String(localized: "No pude asociar el plan en Salud: \(error.localizedDescription)")
                    }
                }
                cerrar()
            }
        } else {
            cerrar()
        }
    }

    private func limpiarTrasFinal(identidad: ObjectIdentifier) {
        guard controlCierre.finalizar(identidad) else { return }
        timerMuestras?.invalidate()
        timerMuestras = nil
        ubicaciones.stopUpdatingLocation()
        guardando = false
        activo = false
        pausado = false
        enPausaAutomatica = false
        ubicacionPausa = nil
        sesion = nil
        builder = nil
        routeBuilder = nil
        descartarAlTerminar = false
        programadoID = nil
        estructuraCompletaAlGuardar = false
        huellaCumplidaAlGuardar = nil
        recuperando = false
        UserDefaults.standard.removeObject(forKey: Self.claveProgramadoActivo)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            let identidad = ObjectIdentifier(workoutSession)
            guard self.controlCierre.esActual(identidad) else { return }
            self.mensajeError = String(localized: "Entrenamiento: \(error.localizedDescription)")
            self.resumen?.guardadaEnSalud = false
            self.limpiarTrasFinal(identidad: identidad)
        }
    }

}

extension Entrenamiento: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let ahora = Date()
        let senalesFrescas = locations.sorted { $0.timestamp < $1.timestamp }.filter {
            filtroSenalGPS.aceptar(fecha: $0.timestamp,
                                   precision: $0.horizontalAccuracy, ahora: ahora)
        }
        // Auto-pausa → reanudación automática por desplazamiento
        // sostenido O velocidad GPS sostenida (SupervisorReanudacion en
        // Shared). La pausa MANUAL nunca entra acá (puedeAutoReanudar).
        if AutoPausa.puedeAutoReanudar(pausada: pausado, enPausaAutomatica: enPausaAutomatica) {
            guard let ubicacion = senalesFrescas.last else { return }
            fechaUltimaSenalPausa = ubicacion.timestamp
            let desplazamiento = ubicacionPausa.map { ubicacion.distance(from: $0) }
            if ubicacionPausa == nil { ubicacionPausa = ubicacion }
            if supervisorReanudacion.procesar(
                desplazamiento: desplazamiento,
                velocidad: ubicacion.speed >= 0 ? ubicacion.speed : nil,
                umbral: max(15, ubicacion.horizontalAccuracy),
                fecha: ubicacion.timestamp) {
                autoReanudar()
            }
            return
        }

        guard activo, !pausado, let routeBuilder else { return }
        // Solo puntos con precisión decente; los malos ensucian el mapa.
        let buenas = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50 }
        guard !buenas.isEmpty else { return }
        routeBuilder.insertRouteData(buenas) { _, _ in }
        // CLLocationManager se creó en main. Conservar el timestamp
        // medido: un lote demorado no cuenta como GPS recién adquirido.
        for ubicacion in senalesFrescas {
            ubicacionesRecientes.append((ubicacion.timestamp, ubicacion))
        }
        puntosRuta += buenas.count
    }

    /// Si el permiso se concede DESPUÉS de arrancar (el cartel apareció
    /// con la sesión ya en marcha), acá se enciende el GPS que había
    /// quedado mudo. Antes esto se perdía y la carrera salía sin mapa.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard activo, usaGPS else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.mensajeError = String(localized: "Ubicación negada: esta carrera queda sin recorrido. Activala en Ajustes → Privacidad → Localización → Maratonia.")
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Sin GPS momentáneo (túnel, arranque): no es fatal, la ruta sigue
        // con los puntos que haya. Pero permiso negado sí se avisa.
        if let clError = error as? CLError, clError.code == .denied {
            DispatchQueue.main.async {
                self.mensajeError = String(localized: "Ubicación negada: esta carrera queda sin recorrido. Activala en Ajustes → Privacidad → Localización → Maratonia.")
            }
        }
    }
}

extension Entrenamiento: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Cola interna de HealthKit → leer el builder siempre en main.
        DispatchQueue.main.async {
            guard self.builder === workoutBuilder else { return }
            self.actualizarEstadisticas(con: collectedTypes)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
