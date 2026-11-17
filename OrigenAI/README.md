# Origen AI v0.1

Aplicación Android experimental, independiente de Nexus. ID: `com.origenai.local`. Funciona localmente sin permiso INTERNET. El modelo Transformer causal de una capa y una cabeza de atención tiene 83.584 parámetros, ventana de 64 tokens y tokenizador BPE de 640 tokens entrenado sobre un corpus original. Los pesos se inicializan aleatoriamente en cada instalación nueva. Se incluyen 88 ejemplos de entrenamiento, no respuestas programadas ni un modelo preentrenado.

## Primer entrenamiento
1. Instala la APK y abre Entrenar.
2. Elige 3.000 pasos y 0.003 de tasa de aprendizaje. Pulsa Entrenar. Puedes pausar, y los pesos se guardan localmente.
3. Prueba preguntas cortas, tanto las del corpus como frases distintas. Corrige respuestas en Enseñar y añade ejemplos propios. Continúa con más pasos; reduce la tasa a 0.001 para ajustes posteriores.
4. En Modelo, guarda o genera un respaldo. No borres los datos de la aplicación sin guardar antes el respaldo. Mantén el teléfono fresco.

## Limitaciones
No es comparable a ChatGPT: aprende ejemplos conocidos y todavía falla con frases nuevas. Solo procesa un mensaje cada vez, no recuerda conversaciones de varios turnos y no tiene reconocimiento ni síntesis de voz. No usa la NPU; entrenamiento por CPU/JavaScript, en primer plano. Almacenamiento local WebView sujeto a límites de cuota. El corpus inicial es pequeño. No se verificó la instalación en dispositivo Android o emulador. Se probó el motor en Node.js y la interfaz en Chromium con un almacenamiento simulado.

## Construcción
Instala JDK 17, Gradle 8.9 y Android SDK 35 y ejecuta `gradle :app:assembleDebug`. En el repositorio Nexus, el flujo independiente Build Origen AI genera una APK con firma persistente usando los secretos de firma ya configurados en Nexus. La primera APK experimental distribuida fuera de GitHub usa otro certificado; si la instalaste, exporta los pesos y datos antes de migrar. No cambies el certificado de las futuras versiones. Una APK con firma diferente no puede actualizar la aplicación ya instalada; usa el mismo certificado para conservar datos. Nunca publiques el almacén de claves.

## Prueba reproducible
`node tools/test_model.js`. Muestra una prueba de aprendizaje de un único diálogo y la restauración de pesos. La pérdida sobre entrenamiento no mide generalización.
