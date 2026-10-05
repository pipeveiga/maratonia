import XCTest

/// Recorre la app como una instalación nueva, con fixtures locales.
/// No usa una cuenta de Felipe ni llama a Firebase, Salud o StoreKit.
final class NavegacionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func abrir(conPlan: Bool = false, ingles: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-pruebaNavegacion", "YES",
                               "-pruebaNavegacionConPlan", conPlan ? "YES" : "NO",
                               "-AppleLanguages", ingles ? "(en)" : "(es)",
                               "-AppleLocale", ingles ? "en_US" : "es_AR"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
    }

    private func captura(_ nombre: String) {
        let adjunto = XCTAttachment(screenshot: app.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    private func comprobarTituloVisible(_ titulo: String) {
        let elemento = app.navigationBars.staticTexts[titulo].firstMatch
        let visible = NSPredicate { _, _ in elemento.exists && elemento.isHittable }
        let espera = XCTNSPredicateExpectation(predicate: visible, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [espera], timeout: 5), .completed)
    }

    func testUsuarioNuevoEncuentraCarreraPlanYHistorial() {
        abrir()
        XCTAssertTrue(app.staticTexts["Carrera libre"].exists)
        XCTAssertTrue(app.buttons["Empezar"].exists)
        captura("01-hoy-sin-plan")
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Tu plan empieza acá"].waitForExistence(timeout: 5))
        captura("02-plan-sin-plan")
        app.buttons["Crear mi plan"].tap()
        XCTAssertTrue(app.navigationBars["Tu objetivo"].waitForExistence(timeout: 5))
        captura("03-onboarding")
        app.buttons["Ahora no"].tap()
        XCTAssertTrue(app.staticTexts["Tu plan empieza acá"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Progreso"].tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Carreras"].tap()
        comprobarTituloVisible("Progreso")
        XCTAssertTrue(app.staticTexts["Tu mapa está esperando"].waitForExistence(timeout: 5))
        captura("04-historial-vacio")
        app.buttons["Salir a correr"].tap()
        XCTAssertTrue(app.staticTexts["Carrera libre"].waitForExistence(timeout: 5))
    }

    func testPlanAbreCalendarioSinBuscarUnEnlaceEscondido() {
        abrir(conPlan: true)
        XCTAssertTrue(app.buttons["detalleDeHoy"].exists)
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Semana 1 de 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rodaje fácil"].exists)
        captura("05-plan-activo")
        app.buttons["Opciones del plan"].tap()
        XCTAssertTrue(app.buttons["Cambiar objetivo o disponibilidad"].waitForExistence(timeout: 5))
        captura("06-opciones-plan")
    }

    func testOnboardingNoPermiteSaltearObjetivoDeslizando() {
        abrir()
        app.tabBars.buttons["Plan"].tap()
        app.buttons["Crear mi plan"].tap()
        XCTAssertTrue(app.staticTexts["¿Qué querés lograr?"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["¿Qué querés lograr?"].exists)
        XCTAssertFalse(app.staticTexts["¿Qué venís haciendo?"].exists)
    }

    func testRecorridoEnIngles() {
        abrir(ingles: true)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Your plan starts here"].waitForExistence(timeout: 5))
        captura("07-plan-en")
        app.tabBars.buttons["Progress"].tap()
        app.segmentedControls.buttons["Runs"].tap()
        comprobarTituloVisible("Progress")
        XCTAssertTrue(app.staticTexts["Your map is waiting"].waitForExistence(timeout: 5))
        captura("08-historial-en")
    }
}
