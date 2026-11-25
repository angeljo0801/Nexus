# Origen AI 0.7 · IA local sin computadora

En **Modelo preentrenado → Motor de inferencia → En este teléfono · GGUF integrado** puedes descargar Qwen3.5-0.8B (Q4_0, 563 MB) y conversar directamente con la red neuronal en Android sin conexión a internet tras descargarla. Hay una opción Qwen3.5-2B (Q4_0, 1,21 GB) que requiere más RAM. El funcionamiento se realiza sobre CPU ARM64 mediante una compilación propia de llama.cpp; no necesita Termux ni Ollama para el modo Teléfono.

1. Actualiza la APK **sin desinstalar** y antes exporta un respaldo del modelo experimental.
2. Selecciona **Modelo preentrenado → En este teléfono · GGUF integrado** y Qwen3.5-0.8B.
3. Pulsa **Descargar GGUF**. Por defecto la descarga solo funciona por Wi-Fi; puedes habilitar datos móviles. Android muestra el progreso y puede continuar la descarga fuera de Origen AI. Se recomienda tener al menos 1,5 GB disponibles.
4. Espera a que aparezca **Descargado**. Pulsa **Comprobar motor** o envía un mensaje. La primera vez se verifica el SHA-256 del archivo y se carga en RAM; puede tardar varios segundos.
5. Una vez cargado, las respuestas usan CPU y pesos locales: **puedes activar el modo avión**. No se envían conversaciones al proveedor del GGUF.
6. Pulsa **Liberar RAM** cuando no vayas a usar el modelo. El archivo descargado se conserva para la próxima sesión.

**Requisitos y limitaciones:** instalación ARM64; espacio libre para el archivo y RAM adicional para contexto y generación. Solo procesa texto, no imágenes. El rendimiento real en Samsung S24 Ultra no está todavía medido. El motor se ejecuta dentro de la app; durante su uso puede calentarse el teléfono. El archivo de modelo se guarda en el directorio externo privado de la app y se pierde si la desinstalas. Los pesos experimentales permanecen aparte; no ejecutes simultáneamente ambos motores. Esta versión no modifica ni entrena automáticamente los pesos preentrenados. Para LoRA siguen disponibles los ejemplos revisados/exportados.

**Fuentes e integridad:** Qwen3.5-0.8B Q4_0 de ggml-org (Apache-2.0, SHA256 `57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf`); Qwen3.5-2B Q4_0 de ente-ai/Unsloth (SHA256 `cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1`). Descargas realizadas únicamente desde Hugging Face HTTPS. llama.cpp código fuente MIT compilado con NDK ARM64, commit `244640b7f26e2a7301b27a24edc4f7feaf97d52f`. Respeta las licencias y atribuciones originales.

### Compatibilidad con modo servidor

El modo Ollama y la API llama.cpp de la versión 0.6 continúan disponibles para conectarse opcionalmente a una computadora local; **no son necesarios** para utilizar el modo En este teléfono.

### Actualización del proyecto experimental

Los lotes GitHub y el modelo experimental permanecen intactos y separados. La autorización para el entrenamiento remoto debe conservarse durante pausas por seguridad; al volver a abrir la aplicación, esta puede reanudar la sesión pendiente si la temperatura y la batería son adecuadas. Si Qwen ya está cargado en RAM, pulsa Liberar RAM antes de entrenar el experimental.
