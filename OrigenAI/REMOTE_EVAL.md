# Origen AI 0.8 · Canal de evaluaciones bidireccional

Esta versión añade una conexión remota **solo para preguntas de evaluación del modelo preentrenado** utilizando el repositorio privado GitHub ya configurado para el modelo experimental: `angeljo0801/origenAI-Sync.` (incluido el punto final).

## Uso en Android

1. Instala la APK 0.8 **encima** de Origen AI, sin borrar datos, y exporta antes un respaldo del experimental.
2. Configura el repositorio y su token privado desde **Modelo experimental → Conexión**, como antes. El token queda cifrado en el almacén seguro Android.
3. En **Modelo preentrenado**, descarga y comprueba uno de los modelos GGUF.
4. En **Conexión con ChatGPT · Pruebas remotas**, activa voluntariamente **Permitir que Origen AI reciba y conteste automáticamente pruebas remotas**.
5. Con la aplicación visible, el teléfono consulta GitHub aproximadamente cada minuto; también puedes pulsar **Revisar nuevas pruebas**. Las preguntas se generan en el teléfono y los resultados vuelven a GitHub. No necesitas mantener abierto ChatGPT.
6. Para comprobar desde ChatGPT, lee `origen-pretrained-status.json` y compáralo con `origen-pretrained-requests.json`. Si las respuestas son nuevas, analízalas y prepara preguntas diferentes de evaluación para un próximo lote.

## Protocolo JSON

`origen-pretrained-requests.json`, redactado por ChatGPT:
```json
{
  "version": 1,
  "id": "pre-eval-001",
  "model": "qwen08",
  "questions": ["Explica una diferencia entre calor y temperatura."]
}
```

`origen-pretrained-status.json`, generado por el teléfono:
```json
{
  "version": 1,
  "id": "pre-eval-001",
  "model": "qwen08",
  "state": "completed",
  "updatedAt": "2026-11-25T12:00:00Z",
  "results": [
    {"q":"Explica una diferencia entre calor y temperatura.", "a":"..."}
  ]
}
```

Estados: `completed` o `error`. Se rechazan archivos que no respeten el esquema. Un único lote vigente, entre 1 y 5 preguntas de hasta 300 caracteres cada una. El modelo `qwen08` y `qwen2` debe estar instalado y validado por SHA-256. El estado remoto solo acepta respuestas asociadas a la solicitud actual. La app conserva el progreso de cada respuesta por separado y reintenta la publicación si hay interrupciones de red.

**Aislamiento y privacidad:** el canal no transmite ni examina chats privados, memoria, ejemplos del usuario, pesos, credenciales ni tokens. No modifica el modelo experimental ni sus archivos `origen-training.json` y `origen-status.json`. No permite comandos, ejecución remota, descarga de modelos ni entrenamiento neuronal mediante este canal: solo preguntas de texto.

**Límites actuales:** el modelo se ejecuta en Android, pero las preguntas dependen de internet para recibir y publicar. Las evaluaciones remotas se consultan con la aplicación visible; no hay un servicio de recepción continua en segundo plano. Si una evaluación es interrumpida se reanuda a partir de sus respuestas guardadas. El fine-tuning LoRA permanece independiente y sin automatizar.
