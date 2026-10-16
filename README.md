# Aurum Fit

App de fitness en **Flutter** con plan de entrenamiento y nutrición generado por IA (con búsqueda de evidencia), mapa anatómico que evoluciona de **bronce a oro**, asistente de intervalos por voz, podómetro nativo y todos los datos **cifrados en el teléfono**.

Cada push a `main` compila el `.apk` en GitHub Actions y lo publica en *Releases* con un enlace de descarga directa.

---

## Contenido

1. [Qué incluye](#qué-incluye)
2. [Arquitectura](#arquitectura)
3. [Seguridad y privacidad](#seguridad-y-privacidad)
4. [Inicializar el repositorio local](#1-inicializar-el-repositorio-local)
5. [Vincularlo a GitHub](#2-vincularlo-a-github)
6. [Firmar el APK (recomendado)](#3-firmar-el-apk-recomendado)
7. [Desplegar el proxy de IA](#4-desplegar-el-proxy-de-ia)
8. [Publicar y compartir el enlace de descarga](#5-publicar-y-compartir-el-enlace-de-descarga)
9. [Instalar en Android](#6-instalar-en-android)
10. [iOS](#ios)
11. [Limitaciones conocidas](#limitaciones-conocidas)

---

## Qué incluye

| Módulo | Detalle |
|---|---|
| **Onboarding biométrico** | Sexo, edad, peso (kg/lb), altura (cm/ft), % de grasa, nivel de actividad, lesiones, objetivo con fecha límite y equipo (gimnasio / calistenia / casa, obligatorio). |
| **Plan inteligente** | Generador **local offline** (Mifflin-St Jeor / Katch-McArdle, macros ISSN, plantillas por objetivo y equipo, adaptación por lesiones) + **IA con búsqueda web** a través del proxy. Rutina por días con series, repeticiones, descansos y tiempos; dieta de 7 días × 5 comidas con macros y alternativas locales. |
| **Mapa anatómico evolutivo** | Cuerpo vectorial frontal y posterior con 14 grupos musculares tocables. Cada músculo pasa de bronce opaco a oro brillante según consistencia, sobrecarga progresiva y experiencia; el dorado se apaga si dejas de entrenarlo. |
| **Timer / asistente de voz** | HIIT, Tabata, boxeo, cuerda, personalizado o el circuito del día del plan. Números gigantes, cuenta "5, 4, 3, 2, 1" por voz, instrucciones ("¡Corre 1 kilómetro!"), tonos que bajan el volumen de tu música en lugar de pausarla, vibración y pantalla siempre encendida. |
| **Podómetro** | Sensor de pasos nativo en tiempo real + Health Connect / HealthKit. Los días marcados en el plan solo cuentan como cumplidos al llegar a la meta de pasos. |
| **Hidratación** | Registro diario con meta por peso corporal y recordatorios. |
| **Fotos de progreso** | Guardadas cifradas dentro de la app (no en la galería), comparación antes/después. |
| **Recordatorios locales** | Comidas, agua y entrenamiento, sin servicios de push en la nube. |

## Arquitectura

```
aurum_fit/
├── .github/workflows/build.yml      CI: tests → APK → GitHub Releases
├── android/                         Proyecto Android (Gradle KTS, permisos, Health Connect)
├── assets/certs/pinned_roots.pem    CAs raíz fijadas para el pinning TLS
├── lib/
│   ├── main.dart / app.dart         Arranque, bloqueo automático, navegación raíz
│   ├── core/
│   │   ├── config/env.dart          PROXY_URL inyectada con --dart-define
│   │   ├── security/                Keystore/Keychain, PBKDF2, HTTPS con pinning, sanitizador
│   │   ├── storage/local_db.dart    Hive cifrado AES-256
│   │   └── theme/                   Paleta bronce → oro
│   └── features/
│       ├── auth/                    PIN + biometría, pantalla de bloqueo
│       ├── onboarding/              Perfil biométrico y objetivo
│       ├── plan/                    Modelos, generador local, cliente del proxy, UI
│       ├── progress/                Motor de progreso + mapa anatómico (CustomPainter)
│       ├── timer/                   Máquina de estados de intervalos + voz/tonos
│       ├── steps/                   Podómetro y Health Connect/HealthKit
│       ├── hydration/  photos/  notifications/  home/
├── proxy/                           Cloudflare Worker: guarda la clave de IA
│   ├── src/index.js                 Endpoint /v1/plan, límites, llamada a la IA
│   ├── src/schema.js                Validación de entrada y salida
│   └── test/                        Tests (node --test)
└── test/                            Tests unitarios de Dart
```

```
Teléfono (Flutter)                         Cloudflare Worker                 IA (Claude + búsqueda web)
┌──────────────────────────┐   HTTPS +    ┌────────────────────────┐  HTTPS  ┌──────────────────┐
│ Datos cifrados (AES-256) │   pinning    │ Código de acceso       │ ──────► │ Plan en JSON +   │
│ Perfil anónimo saneado ──┼────────────► │ Límite diario (KV)     │ ◄────── │ fuentes citadas  │
│ Validación del JSON  ◄───┼───────────── │ Valida entrada/salida  │         └──────────────────┘
└──────────────────────────┘              │ ANTHROPIC_API_KEY 🔒   │
                                          └────────────────────────┘
```

## Seguridad y privacidad

| Requisito | Implementación |
|---|---|
| **Cifrado en tránsito / anti-MITM** | `PinnedHttp` usa un `SecurityContext` **sin** las CAs del sistema: solo confía en las raíces de `assets/certs/pinned_roots.pem` (Google Trust Services, Let's Encrypt y SSL.com, las CAs de Cloudflare). Rechaza cualquier certificado que no valide, bloquea redirecciones e ignora proxies del sistema. Además `network_security_config.xml` prohíbe HTTP en claro y CAs instaladas por el usuario. TLS lo negocia BoringSSL (1.3 cuando el servidor lo ofrece). |
| **Cifrado en reposo** | Llave AES-256 aleatoria guardada en Android Keystore / iOS Keychain (`flutter_secure_storage`). Toda la base (perfil, planes, entrenamientos, pasos, agua, fotos) está en cajas Hive cifradas con esa llave. Copias de seguridad y transferencias entre dispositivos desactivadas. |
| **Autenticación** | PIN de 6 dígitos con PBKDF2-HMAC-SHA256 (120 000 iteraciones, sal aleatoria), comparación en tiempo constante, bloqueo progresivo tras 5 intentos, biometría opcional, auto-bloqueo a los 45 s en segundo plano. `FLAG_SECURE` bloquea capturas de pantalla. |
| **Sanitización / prompt injection** | 3 capas: (1) la app limpia caracteres invisibles y de marcado y rechaza frases tipo "ignora las instrucciones"; (2) el proxy repite la validación y envía el texto del usuario delimitado como datos, con un prompt de sistema que ordena ignorar instrucciones ahí; (3) la respuesta de la IA se valida contra un esquema estricto en el proxy **y** en la app (campos desconocidos fuera, números acotados, solo URLs `https`). |
| **Secretos** | La clave de la IA **no está en la app ni en el repo**: vive como secreto del Worker. `PROXY_URL` se inyecta en CI desde los *Secrets* de GitHub. Nota honesta: cualquier valor compilado dentro de un APK se puede extraer, por eso la clave nunca va ahí. |
| **Aislamiento de sensores** | Permisos en tiempo de ejecución (pasos, notificaciones). Ubicación y micrófono se **eliminan** del manifiesto. Pasos, fotos y voz nunca salen del teléfono; a la IA solo se envía un perfil anónimo (sin nombre, fecha exacta, fotos ni historial). |

---

## 1. Inicializar el repositorio local

Requisitos: [Flutter 3.35+](https://docs.flutter.dev/get-started/install), Android SDK (con Android Studio), Git, Node 18+ (solo para el proxy).

```bash
cd aurum_fit
flutter pub get
flutter test                 # tests unitarios
flutter run                  # con un teléfono conectado o un emulador

# Con IA (después de desplegar el proxy, paso 4):
flutter run --dart-define=PROXY_URL=https://aurum-proxy.TU-SUBDOMINIO.workers.dev
```

Sin `PROXY_URL` la app funciona completa con el generador local de planes.

## 2. Vincularlo a GitHub

```bash
git init -b main
git add .
git commit -m "Aurum Fit: primera versión"

# Opción A — con GitHub CLI
gh repo create aurum-fit --public --source . --push

# Opción B — crea el repo vacío en github.com y luego:
git remote add origin https://github.com/TU-USUARIO/aurum-fit.git
git push -u origin main
```

> El repositorio debe ser **público** si quieres que cualquiera descargue el APK sin cuenta de GitHub. Si es privado, solo quienes tengan acceso al repo podrán descargarlo.

En **Settings → Secrets and variables → Actions → New repository secret** agrega:

| Secret | Obligatorio | Valor |
|---|---|---|
| `PROXY_URL` | No (sin él no hay IA) | `https://aurum-proxy.TU-SUBDOMINIO.workers.dev` |
| `ANDROID_KEYSTORE_BASE64` | Recomendado | ver paso 3 |
| `ANDROID_KEYSTORE_PASSWORD` | Recomendado | ver paso 3 |
| `ANDROID_KEY_ALIAS` | Recomendado | ver paso 3 |
| `ANDROID_KEY_PASSWORD` | Recomendado | ver paso 3 |

## 3. Firmar el APK (recomendado)

Sin keystore propio el APK se firma con una clave *debug* distinta en cada ejecución de CI, y Android **no deja actualizar** encima de la versión anterior (hay que desinstalar, y eso borra los datos). Con tu propia firma, cada nueva versión se instala encima conservando todo.

```bash
keytool -genkey -v -keystore aurum-release.jks -keyalg RSA -keysize 4096 \
  -validity 10000 -alias aurum

# macOS / Linux
base64 -i aurum-release.jks | tr -d '\n' > keystore.b64
# Windows (PowerShell)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("aurum-release.jks")) > keystore.b64
```

Copia el contenido de `keystore.b64` en `ANDROID_KEYSTORE_BASE64` y las contraseñas/alias en los otros tres secrets. **Guarda el `.jks` fuera del repositorio** (ya está en `.gitignore`); si lo pierdes, no podrás publicar actualizaciones compatibles.

## 4. Desplegar el proxy de IA

Necesitas una cuenta gratuita de [Cloudflare](https://dash.cloudflare.com/sign-up) y una clave de la [API de Anthropic](https://console.anthropic.com/).

```bash
cd proxy
npm install
npx wrangler login

npx wrangler secret put ANTHROPIC_API_KEY     # pega tu clave
npx wrangler secret put ACCESS_CODE           # inventa un código para tus usuarios

# Límite diario por usuario (recomendado):
npx wrangler kv namespace create RATE_KV      # copia el id en wrangler.toml y descomenta el bloque

npm test                                      # 8 tests del proxy
npx wrangler deploy
```

`wrangler deploy` te muestra la URL (`https://aurum-proxy.<tu-subdominio>.workers.dev`). Ponla en el secret `PROXY_URL` de GitHub. Comprueba con `curl https://…/health` → `{"ok":true}`.

- **Modelo**: se cambia en `wrangler.toml` (`MODEL`). Cada plan hace hasta 3 búsquedas web; revisa costos en la consola de Anthropic.
- **Código de acceso**: compártelo solo con tus usuarios; lo escriben en *Ajustes → IA → Código de acceso* y se guarda en el Keystore.
- **TLS 1.3**: `*.workers.dev` ya ofrece TLS 1.3. Si usas dominio propio, en Cloudflare ve a *SSL/TLS → Edge Certificates → Minimum TLS Version* y elige 1.2 o 1.3.
- **Pinning**: si pones el proxy detrás de otra CDN o CA, agrega su certificado raíz a `assets/certs/pinned_roots.pem` o la app rechazará la conexión (ese es justamente el objetivo).

## 5. Publicar y compartir el enlace de descarga

| Evento | Qué hace el workflow | Enlace directo para compartir |
|---|---|---|
| `git push` a `main` | Compila y reemplaza la pre-release **build-latest** | `https://github.com/TU-USUARIO/aurum-fit/releases/download/build-latest/aurum-fit.apk` |
| `git tag v1.0.0 && git push origin v1.0.0` | Crea la Release **v1.0.0** marcada como la más reciente | `https://github.com/TU-USUARIO/aurum-fit/releases/latest/download/aurum-fit.apk` |
| Pull request | Solo prueba y compila | — |

El enlace de `releases/latest` siempre apunta a la última versión oficial, así que puedes ponerlo en un QR o en tu bio y no cambia nunca. Cada release incluye también `aurum-fit.apk.sha256` para verificar la descarga.

Para ver el progreso: pestaña **Actions** del repo. La primera compilación tarda ~10–15 min (descarga Gradle y el SDK); las siguientes, ~5 min gracias a la caché.

## 6. Instalar en Android

1. Abre el enlace en el teléfono y descarga `aurum-fit.apk`.
2. Android pedirá permitir *instalar apps desconocidas* para tu navegador; acéptalo solo para esta instalación.
3. Al abrir la app: crea tu PIN → completa el perfil → listo. Para pasos de relojes y otras apps instala [Health Connect](https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata) (en Android 14+ ya viene integrado).

## iOS

El código es multiplataforma, pero distribuir en iPhone fuera de la App Store requiere una cuenta Apple Developer (99 USD/año). Los pasos para generar la carpeta `ios/`, los permisos de `Info.plist` y un job de TestFlight están en [`docs/IOS.md`](docs/IOS.md).

## Limitaciones conocidas

- **Primera compilación**: este proyecto se escribió sin acceso al SDK de Flutter, así que la primera ejecución real es la de GitHub Actions. Si falla algún paso, el log de *Actions* indica el archivo y la línea.
- **Timer en segundo plano**: el temporizador mantiene la pantalla encendida; si sales de la app, Android puede pausar los conteos.
- **Recordatorios y horario de verano**: las horas se programan en UTC con repetición diaria. En Guatemala (sin horario de verano) es exacto; en países con cambio de hora pueden correrse una hora hasta que abras la app.
- **Evidencia de la IA**: el plan cita las fuentes que encontró, pero no sustituye la valoración de un profesional de salud, sobre todo con lesiones o condiciones médicas.
