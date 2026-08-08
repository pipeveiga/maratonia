# 👤 Cuentas en Maratonia — estado y plan

## Hoy (implementado): cuenta iCloud (CloudKit)

- Tu iCloud ES tu cuenta: sin registro, sin contraseñas, cero fricción.
- Base de datos real: el plan se respalda automáticamente en la base
  **privada** del iCloud de cada usuario (el desarrollador no puede verla)
  y se restaura al reinstalar o cambiar de teléfono.
- Ventajas: funciona ya, no cambia el formulario de privacidad
  ("Data Not Collected" se mantiene), y App Review no puede objetar nada
  porque no hay login que exigir.

## Próximo paso (planificado): login con Google / Apple / email+contraseña

Requiere un backend de autenticación externo. Elección: **Firebase**
(Auth + Firestore), el estándar de la industria, gratis en nuestra escala.

### ⚠️ Dos reglas de Apple que condicionan el diseño

1. **Guideline 4.8**: si ofrecés login con Google, es OBLIGATORIO ofrecer
   también "Sign in with Apple". (Ya contemplado: van los tres.)
2. **Guideline 5.1.1(v)**: NO se puede exigir login para funciones que no
   lo necesitan. El login tiene que ser **opcional** y aportar algo real
   (sincronización entre dispositivos, compartir planes con amigos,
   ranking, etc.). Una app que pide cuenta "porque sí" es rechazo seguro.

### Impacto en privacidad (importante para la ficha)

Con Firebase, el formulario "App Privacy" deja de ser "Data Not
Collected": hay que declarar recolección de email e identificadores, y
PRIVACIDAD.md debe reescribirse mencionando a Firebase como procesador.
Es el costo de tener cuentas multi-proveedor.

### Pasos que tiene que hacer Felipe (consola, ~30 min — guiados)

1. `console.firebase.google.com` → crear proyecto "Maratonia".
2. Agregar app iOS con bundle `com.pipeveiga.maraton` → descargar
   **GoogleService-Info.plist** → subirlo al repo (sin ese archivo el
   código de Firebase no compila; por eso este paso va primero).
3. Authentication → habilitar Google, Apple y Email/Password.
4. En Xcode (guiado): capability "Sign in with Apple" + URL scheme del
   client ID de Google.

### Lo que implemento yo cuando el plist esté en el repo

- Paquete Firebase (Auth + Firestore) vía Swift Package Manager.
- Pantalla de login opcional (Apple / Google / email) + crear cuenta +
  recuperar contraseña + cerrar sesión + eliminar cuenta (obligatorio
  por App Review 5.1.1(v): toda app con cuentas debe poder borrarlas).
- Perfil en Firestore y sincronización del plan por usuario.
- Migración de la política de privacidad y del formulario App Privacy.

### Recomendación de secuencia

Lanzar la 1.0 con la cuenta iCloud (cero riesgo de rechazo, privacidad
impecable) y sumar el login multi-proveedor en la 1.1 junto con una
función que lo justifique (ej. compartir planes con amigos). Si igual se
quiere para la 1.0: hacer primero los pasos de consola de arriba.
