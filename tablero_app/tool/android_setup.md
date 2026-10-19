# Configuración de Android

Todo lo que hay que tocar en `android/` lo aplica un script, probado con las plantillas de
Flutter 3.47.7 (Gradle con Kotlin DSL):

```bash
cd tablero_app
flutter create --platforms=android --org com.tuempresa --project-name tablero_app .
python3 tool/bootstrap_android.py --package com.tuempresa.escaque \
    --admob-app-id ca-app-pub-XXXX~YYYY --play-games-project-id 1234567890
```

Aplica `minSdk` 24, desugaring, firma con `android/key.properties`, los flavors dev/qa/prod, permisos,
AdMob, canal de avisos, Analytics desactivado hasta el consentimiento, App Links por entorno y el ID
de Play Games. Es idempotente y guarda una copia `.orig` de cada archivo que cambia. Los pasos a mano
equivalentes están en [GUIA_CONFIGURACION.md](../../GUIA_CONFIGURACION.md), apartado 3.

## AdMob

1. **Mensajes de consentimiento**: crea el mensaje GDPR (y el de estados de EE. UU. si aplica) en
   AdMob → Privacidad y mensajes. Sin mensaje publicado, UMP no muestra formulario.
2. **IDs de bloques de anuncios**: van en `config/prod.json` (`ADMOB_BANNER`, `ADMOB_INTERSTITIAL`,
   `ADMOB_REWARDED`); dev y qa usan los de prueba de Google.
3. **Pruebas de consentimiento en el EEE**: en `AdsService.init`, añade temporalmente
   `ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea, testIdentifiers: ['ID_DE_TU_DISPOSITIVO'])`
   a `ConsentRequestParameters`.
