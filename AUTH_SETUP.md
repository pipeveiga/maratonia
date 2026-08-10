# AUTH_SETUP — Autenticación de Maratonia (IMPLEMENTADA, build 44)

## Arquitectura final de identidad

**Firebase Authentication es la ÚNICA autoridad de identidad remota.**
Los tres proveedores terminan en la misma cuenta de Firebase:

- **Apple**: botón nativo (AuthenticationServices, HIG) y FEDERADO
  contra Firebase con `OAuthProvider.appleCredential(withIDToken:
  rawNonce:fullName:)` + nonce SHA-256 (CryptoKit). Si Firebase no
  está configurado (falta el plist), Apple sigue funcionando en modo
  nativo puro — cero regresión.
- **Google**: GoogleSignIn-iOS → `GoogleAuthProvider.credential` →
  Firebase. El `clientID` sale de `FirebaseApp.app()!.options` —
  ningún ID hardcodeado.
- **Email/contraseña**: `createUser` / `signIn` / `sendPasswordReset`
  de FirebaseAuth. La contraseña vive SOLO en Firebase; la app jamás
  la guarda ni implementa auth casera.

**La identidad del DOMINIO sigue siendo interna**: `CuentaUsuario.
userID` (UUID) es la clave de `AlmacenV2.usuarioID`. El UID de
Firebase es un ATRIBUTO del proveedor vinculado
(`ProveedorVinculado.firebaseUID`), nunca clave del dominio. Cambiar,
agregar o quitar proveedores no toca plan, calendario, referencias,
carreras, preferencias ni HealthKit.

**No se auto-fusionan cuentas por email coincidente**: si un email ya
entra por otro proveedor, Firebase devuelve el error 17012 y la app
lo explica ("usá ese botón") — decisión explícita, sin merges mágicos.

## Qué hay en el código (todo real, sin mocks)

| Pieza | Archivo |
|---|---|
| Servicio de auth (configure, Apple federado, Google, email, reset, signOut, delete + revocación Apple, mapeo de errores ES/EN) | `Maraton/ServicioAuth.swift` |
| Identidad de dominio + LoginView + EmailAuthView + sección Cuenta en Perfil | `Maraton/Identidad.swift` |
| `FirebaseApp.configure()` al arrancar + `onOpenURL` para el callback de Google | `Maraton/MaratonApp.swift` |
| URL scheme del callback de Google (merge de Info.plist) | `Maraton/Info.plist` |
| SPM: firebase-ios-sdk (solo FirebaseAuth) 11.x + GoogleSignIn-iOS 8.x, SOLO target iOS | `project.pbxproj` |

El Watch NO enlaza Firebase ni GoogleSignIn y funciona sin sesión.
No hay Analytics, Firestore, Crashlytics, Messaging ni RemoteConfig.

Gating de runtime (cero botones muertos):
- Sin `GoogleService-Info.plist` en el bundle → no se configura
  Firebase; solo aparece Apple (nativo).
- Sin URL scheme real de Google en Info.plist → el botón de Google no
  aparece aunque Firebase esté configurado.

## Lo que FALTA hacer a mano (Felipe, en orden)

1. **Subir el plist**: poner el `GoogleService-Info.plist` descargado
   de Firebase en `Maraton/GoogleService-Info.plist` del repo (ya
   está referenciado en el proyecto; hasta que exista, el build FALLA
   en la fase de recursos del target iOS — es intencional, no un bug).
   ⚠️ Verificar en Xcode que su Target Membership sea SOLO "Maraton"
   (no el Watch App).
2. **URL scheme de Google**: abrir `Maraton/Info.plist` y reemplazar
   `REVERSED-CLIENT-ID-PENDIENTE` por el valor de `REVERSED_CLIENT_ID`
   que figura DENTRO del GoogleService-Info.plist (formato
   `com.googleusercontent.apps.XXXX`).
3. **Resolver SPM**: al abrir el proyecto en Xcode (MacinCloud),
   File → Packages → Resolve Package Versions (primera vez tarda:
   firebase-ios-sdk es grande). No agregar productos extra.
4. **Firebase console** (ya hecho según confirmaste): Email/Password
   habilitado, Email Link deshabilitado, Google habilitado. Para que
   el login con Apple federado funcione, habilitar también **Apple**
   en Authentication → Sign-in method (no pide clave privada para
   apps iOS nativas; solo activarlo).
5. **Probar físico** con la checklist del informe de build 44.

## Borrado de cuenta (App Store 5.1.1(v)) — semántica exacta

1. Confirmación explícita con texto honesto de alcance.
2. Se revoca el token de Apple (`revokeToken(withAuthorizationCode:)`)
   si hay código fresco de esta sesión de app — requisito de Apple
   para apps con SIWA + borrado de cuenta.
3. `currentUser.delete()` en Firebase. Si Firebase exige login
   reciente (error 17014), la app NO borra nada local: guía a
   reautenticarse y reintentar.
4. Solo con el remoto borrado: se elimina `cuenta.json`, se desasocia
   el dominio y se borra el respaldo propio en iCloud (CloudKit).
5. Apple Health NO se toca (los workouts son del usuario; se
   administran desde la app Salud) — la app lo dice en el diálogo.

Limitación documentada (no simulada): sin backend propio no podemos
borrar server-side logs de Firebase Auth más allá de lo que borra
`delete()` — que elimina el usuario y sus datos de auth. Es el
mecanismo oficial de Firebase y cumple el requisito de App Store.

## Reglas que NO se negocian
- Sin contraseñas guardadas localmente, jamás.
- Sin client IDs / API keys hardcodeados en código.
- **Ninguna API key de OpenAI en la app** — la futura integración GPT
  va por backend/proxy seguro, nunca dentro del binario iOS.
- El userID interno nunca cambia al agregar/quitar proveedores.
- El Watch jamás enlaza Firebase.
