import SwiftUI
import AuthenticationServices

// LA PRIMERA PANTALLA.
//
// Una promesa, tres botones y nada más. El texto legal existe y es
// accesible, pero no es lo primero que lee alguien que quiere correr:
// va abajo, chico, sin bloquear.
//
// No es la pantalla de "creá una cuenta para desbloquear": es la de
// "esta es TU Maratonia, en todos tus dispositivos". Por eso la promesa
// va arriba y los proveedores abajo, y por eso no hay ni un beneficio
// enumerado — eso es un paywall, y esto no lo es.

struct PuertaDeEntrada: View {
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject private var auth = ServicioAuth.compartido
    @State private var mostrandoEmail = false
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        ZStack {
            DV2.gradienteSuperficie.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: DV2.Espacio.xl)

                VStack(spacing: DV2.Espacio.m) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Maratonia")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tu entrenamiento, en todos tus dispositivos.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DV2.Espacio.xl)
                }

                Spacer()

                VStack(spacing: DV2.Espacio.m) {
                    SignInWithAppleButton(.continue) { solicitud in
                        auth.prepararSolicitudApple(solicitud)
                    } onCompletion: { resultado in
                        auth.completarApple(resultado, identidad: identidad)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous))

                    if ServicioAuth.esquemaGoogleConfigurado {
                        boton(titulo: String(localized: "Continuar con Google"),
                              icono: "g.circle.fill") {
                            auth.entrarConGoogle(identidad: identidad)
                        }
                    }

                    boton(titulo: String(localized: "Continuar con email"),
                          icono: "envelope.fill") {
                        mostrandoEmail = true
                    }
                }
                .padding(.horizontal, DV2.Espacio.xl)
                .disabled(auth.ocupado)
                .opacity(auth.ocupado ? 0.5 : 1)
                .overlay {
                    if auth.ocupado { ProgressView().tint(.white) }
                }

                if let mensaje = auth.mensaje ?? identidad.mensajeError {
                    Text(mensaje)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DV2.Espacio.xl)
                        .padding(.top, DV2.Espacio.m)
                }

                // El legal, discreto: presente y tocable, no una pared.
                HStack(spacing: DV2.Espacio.xs) {
                    Link(String(localized: "Términos"),
                         destination: URL(string: "https://maratonia.site/terms/")!)
                    Text("·")
                    Link(String(localized: "Privacidad"),
                         destination: URL(string: "https://maratonia.site/privacy/")!)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, DV2.Espacio.xl)
                .padding(.bottom, DV2.Espacio.l)
            }
        }
        .sheet(isPresented: $mostrandoEmail) {
            EmailAuthView(identidad: identidad)
        }
    }

    private func boton(titulo: String, icono: String,
                       accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: DV2.Espacio.s) {
                Image(systemName: icono)
                Text(titulo).font(.headline)
            }
            .foregroundStyle(DV2.Marca.profundo)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: DV2.radioBoton,
                                                     style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Lo que se ve mientras la cuenta trae su Maratonia. Solo aparece si
/// de verdad tarda: en el caso normal no se ve nunca.
struct RestaurandoView: View {
    var body: some View {
        ZStack {
            DV2.Superficie.fondo.ignoresSafeArea()
            VStack(spacing: DV2.Espacio.l) {
                ProgressView()
                    .controlSize(.large)
                Text("Restaurando tu plan…")
                    .font(DV2.Tipo.tituloChico)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
