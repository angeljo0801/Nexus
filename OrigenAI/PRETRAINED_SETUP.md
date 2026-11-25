# Origen AI 0.6 · Dos modelos, dos almacenes

**Modelo experimental:** sigue siendo el Transformer neuronal creado desde cero. Sus pesos, optimizador, datos y sincronización GitHub se conservan. Abre **Modelo experimental** para entrenarlo, evaluarlo y continuar los lotes.

**Modelo preentrenado:** selecciona **Modelo preentrenado**. Este chat necesita un motor de inferencia compatible que ejecute Qwen u otro modelo abierto en tu teléfono o en una computadora de tu red privada. **El motor GGUF no está todavía incluido en la APK**. Los chats y ejemplos preentrenados se guardan aparte en `origen-pretrained.json`; no mezclan pesos ni corpora.

## Primera prueba con Ollama en una PC

1. Instala Ollama desde https://ollama.com/download y ejecuta `ollama pull qwen3.5:0.8b`. La variante 2B se obtiene con `ollama pull qwen3.5:2b`. Son modelos grandes, no incluidos en la APK.
2. Comprueba en la PC que Ollama funciona, por ejemplo con `ollama run qwen3.5:0.8b`. Ollama ya puede ejecutarse como servicio; no intentes levantar otro proceso si el puerto 11434 está ocupado.
3. Si Origen AI se ejecuta en **el mismo Android que aloja el motor**, usa `http://127.0.0.1:11434`. Si el motor está en una **PC de la red Wi-Fi privada**, la PC debe escuchar en una interfaz accesible. Configura `OLLAMA_HOST=0.0.0.0:11434`, reinicia Ollama y **limita el firewall a tu red y equipos de confianza**. Ollama no exige autenticación por defecto; no abras ese puerto a Internet.
4. En Origen AI → **Modelo preentrenado**, elige **Ollama**, introduce `http://192.168.X.Y:11434` (IP local de la PC) y `qwen3.5:0.8b`. Pulsa **Comprobar motor**, luego conversa.
5. Si usas **llama.cpp server** (también puede ejecutarse en Termux cuando sea compatible), elige **llama.cpp**, introduce la URL local (normalmente `http://127.0.0.1:8080`) y el identificador con el que el servidor ha cargado el modelo. El servidor implementa `/v1/chat/completions`.

La app solo permite motores HTTP en `localhost` y rangos IPv4 de red privada. No acepta servidores HTTP públicos. Un servidor de la PC funcionará en la misma red, no equivale a inferencia integrada en el APK; para uso totalmente autónomo sin un servidor separado hará falta integrar un runtime móvil GGUF.

## Preparar mejoras neuronales propias

1. Conversa en la sección preentrenada.
2. Revisa y **edita** la respuesta ideal del último intercambio.
3. Pulsa **Guardar ejemplo**. No entrena instantáneamente ni sustituye respuestas por scripts.
4. Pulsa **Exportar JSONL** para guardar `OrigenAI-LoRA.jsonl`. El archivo contiene `messages: [{role:user, content:...},{role:assistant,content:...}]`.
5. Sincroniza ese archivo manualmente con un entorno GPU bajo tu control (PC o Colab); el motor preentrenado NO envía conversaciones ni ejemplos al repositorio de sincronización experimental.
6. Comprueba calidad, duplicados y una división retenida para evaluación con:
   ```bash
   python tools/prepare_lora_dataset.py OrigenAI-LoRA.jsonl --output-dir entrenamiento-origen
   ```
   El script produce `train.jsonl` y `validation.jsonl`. No se debe incluir la validación en el entrenamiento.
7. Para entrenar Qwen3.5 con LoRA y exportar adaptadores/GGUF, usa las instrucciones **actualizadas** de Unsloth: https://unsloth.ai/docs/models/qwen3.5/fine-tune. La documentación recomienda bf16 LoRA para esta familia; evita QLoRA de 4 bits para Qwen3.5 hasta validar calidad. Unsloth Studio admite interfaz gráfica. Entrenar necesita una GPU adecuada y comprobar resultados antes de sustituir un modelo en producción.

## Entrenamiento automático experimental

La autorización se conserva después de pausas por batería baja, temperatura o límite de sesión. Cuando la app está **visible**, vuelve a consultar el lote pendiente cada minuto, y cuando el estado térmico/batería sea seguro puede reanudar el servicio nativo sin que tengas que reactivar la casilla. Una pausa manual desactiva la autorización. El servicio de entrenamiento ya iniciado puede seguir en segundo plano según las restricciones de Android, pero **recibir el lote siguiente necesita abrir la app**; no hay planificador independiente permanente en segundo plano todavía.

**Seguridad y recuperación:** instala una actualización firmada encima de la anterior sin desinstalar, y exporta primero un respaldo del modelo experimental. La sección preentrenada tiene almacenamiento separado y nunca edita `origen-training.json`. Ningún trabajo LoRA se ejecuta silenciosamente en el teléfono.
