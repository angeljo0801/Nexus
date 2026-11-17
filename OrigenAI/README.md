# Origen AI v0.2

Aplicación Android experimental, independiente de Nexus. ID: `com.origenai.local`. El motor funciona localmente; el permiso INTERNET se utiliza solo para la conexión privada opcional. El modelo Transformer causal de una capa y una cabeza de atención tiene 83.584 parámetros, ventana de 64 tokens y tokenizador BPE de 640 tokens entrenado sobre un corpus original. Los pesos se inicializan aleatoriamente en cada instalación nueva. Se incluyen 88 ejemplos de entrenamiento, no respuestas programadas ni un modelo preentrenado.

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

## Sincronización bidireccional (v0.2)
El motor sigue siendo local. Crea un repositorio PRIVADO, inicializado con README, por ejemplo OrigenAI-Sync. Genera un fine-grained PAT de GitHub con acceso exclusivamente a ese repositorio y permiso Contents Read and write. No compartas el token ni lo incluyas en el código. Conecta desde la pestaña Conexión: el token se cifra en Android Keystore. ChatGPT puede escribir y leer ese repositorio si está autorizado en su conector. Nunca uses el repositorio público Nexus para datos de aprendizaje privados.

Archivo entrante `origen-training.json` en rama predeterminada:
```json
{"version":1,"id":"lote-001","examples":[{"kind":"dialog","q":"¿Qué tal?","a":"Muy bien, ¿y tú?"},{"kind":"text","text":"Un texto de práctica."}],"steps":1000,"lr":0.003,"tests":["¿Cómo te va?"]}
```
IDs únicos, hasta 500 ejemplos por lote, 0 a 10000 pasos, tasas 0.003/0.001/0.0003, hasta 5 preguntas. No sobrescribir un lote antes de recibir confirmación en `origen-status.json`. Un dispositivo por canal. El teléfono descarga y muestra el lote; el usuario puede aplicarlo o autorizar ejecución automática mientras la app esté visible. El permiso automático se reinicia cada vez que se abre la app. El estado devuelve métricas y respuestas de evaluación solicitadas, no pesos ni conversaciones privadas. El entrenamiento se pausa al ocultar la app. No es entrenamiento remoto en servidor ni conexión permanente en segundo plano.

## v0.3: crecimiento neuronal gradual
Modelo original: 83.584 parámetros (d48, contexto64). Ampliaciones opcionales d128/contexto96 (307.840) y d256/contexto128 (885.376). Conserva las funciones del modelo previo en secuencias de hasta su contexto anterior mediante expansión de matrices, con ajuste de escala Q/K. Se conservan corpus, contador global, historial de lotes y pesos previos; Adam empieza con momentos nuevos y contador independiente. No se cambia el tokenizador ni se usa modelo preentrenado. Las capas nuevas son dimensiones adicionales de la misma capa, no capas Transformer adicionales.
La ampliación es manual e imposible con un lote local activo. Se guarda un respaldo privado del estado anterior; se permite deshacer solo antes de continuar el entrenamiento. La app usa archivos privados Android AtomicFile, migra el checkpoint legado de WebView al guardar, y puede exportar/importar JSON con el selector de archivos. El modelo grande puede ser considerablemente más lento. No borres ni desinstales la aplicación para actualizar. Exporta un respaldo primero. No hay estimación fiable de tiempo de entrenamiento hasta medir el teléfono. Las pruebas verifican conservación de logits, restauración y actualización de las dimensiones nuevas; no garantizan lenguaje natural. Las evaluaciones remotas usan muestreo greedy (temperatura cero), para comparaciones más repetibles.
