# AUTH_SETUP — Autenticación de Maratonia

## Decisión de proveedor

**Elegido: Firebase Auth** para Google + email/contraseña (cuando se
configure), con **Sign in with Apple NATIVO** (AuthenticationServices,
sin SDK externo). Justificación:
- SIWA nativo no necesita backend: subject ID estable, private relay,
  revocación — funciona hoy y no agrega dependencias al build.
- Firebase Auth es la vía más rápida y probada en iOS para email +
  Google: registro, login, reset de contraseña, borrado de cuenta y
  vinculación multi-proveedor ya resueltos (nada de auth casera).
- Alternativa evaluada: Supabase Auth — válida, pero su SDK iOS y el
  flujo de vinculación multi-proveedor están menos maduros que los de
  Firebase para este caso.

## Lo que YA está implementado (en el repo)

- `CuentaUsuario` con **userID (UUID) como identidad interna** —
  separado de Apple subject, Google subject y email; el email jamás es
  clave primaria; multi-proveedor por diseño (`vincular` idempotente).
- `AlmacenV2.usuarioID`: el dominio deportivo pertenece al userID.
  Crear cuenta ASOCIA los datos existentes (migración sin duplicados;
  HealthKit intacto).
- **Sign in with Apple completo**: botón oficial (HIG), nombre/email
  capturados solo la primera vez, chequeo de revocación al abrir,
  sesión persistida localmente.
- LoginView / BienvenidaView (instalación limpia, cuenta OPCIONAL con
  "Más adelante") / sección de cuenta en Perfil con **Cerrar sesión**
  y **Eliminar cuenta** (borra cuenta + respaldo iCloud propio;
  explica que Apple Health no se toca).
- Gating por configuración: los botones de Google y email **no
  aparecen** hasta que exista `GoogleService-Info.plist` en el bundle.
- Entitlement `com.apple.developer.applesignin` agregado.

## Lo que FALTA configurar EXTERNAMENTE (lo hace el usuario)

### 1. Sign in with Apple (para que funcione el botón YA implementado)
1. developer.apple.com → Certificates, Identifiers & Profiles →
   Identifiers → `com.pipeveiga.maraton` → activar capability
   **Sign In with Apple** → Save.
2. En Xcode (MacinCloud): target Maraton → Signing & Capabilities —
   con automatic signing, al detectar la entitlement regenera el
   perfil solo. Si el Archive falla por provisioning: borrar la clave
   `com.apple.developer.applesignin` de `Maraton/Maraton.entitlements`
   y archivar sin cuentas (todo lo demás sigue funcionando).

### 2. Firebase (para habilitar Google + email en 1.1)
1. console.firebase.google.com → crear proyecto "Maratonia".
2. Agregar app iOS con bundle ID `com.pipeveiga.maraton`.
3. Descargar `GoogleService-Info.plist` → agregarlo al target Maraton
   en Xcode (con eso los botones aparecen solos).
4. Authentication → Sign-in method → habilitar **Email/Password**,
   **Google** y **Apple**.
5. Plantillas → email de **reset de contraseña** (es automático de
   Firebase; solo revisar el remitente).
6. Xcode → target Maraton → agregar paquetes SPM:
   `https://github.com/firebase/firebase-ios-sdk` (producto
   FirebaseAuth) y `https://github.com/google/GoogleSignIn-iOS`.
7. Info del target → URL Types → agregar el `REVERSED_CLIENT_ID` del
   plist como URL scheme (lo pide Google Sign-In).
8. Borrado de cuenta: Firebase expone `currentUser.delete()` — el
   botón "Eliminar cuenta" ya existe; al integrar el SDK se le suma
   esa llamada (hoy borra cuenta local + respaldo iCloud).
9. Avisarme ("Firebase configurado") y conecto los providers reales
   detrás del protocolo existente — la UI no cambia.

## Reglas que NO se negocian
- Sin contraseñas guardadas localmente, jamás.
- Sin tokens persistidos de más (SIWA usa credential state, no tokens).
- El userID interno nunca cambia al agregar/quitar proveedores.
