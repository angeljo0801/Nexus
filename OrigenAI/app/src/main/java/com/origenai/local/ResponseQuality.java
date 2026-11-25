package com.origenai.local;

/** Normaliza salida neuronal, sin añadir respuestas prefabricadas. */
public final class ResponseQuality {
    private ResponseQuality() {}
    public static String clean(String raw) {
        if(raw==null)throw new IllegalArgumentException("La respuesta fue vacía");
        String text=raw.trim();
        // La API local de algunos GGUF Qwen3.5 devuelve un bloque de razonamiento.
        // Nunca se debe mostrar ese bloque como parte de la respuesta conversacional.
        for(int pass=0;pass<4;pass++){
            if(text.startsWith("<think>")){
                int close=text.indexOf("</think>",7);
                if(close<0)throw new IllegalArgumentException(
                    "El modelo agotó la generación durante el razonamiento; vuelve a intentar");
                text=text.substring(close+8).trim();
            }else if(text.startsWith("</think>")){
                text=text.substring(8).trim();
            }else{
                break;
            }
        }
        if(text.isEmpty())throw new IllegalArgumentException(
            "El modelo no produjo una respuesta final; inténtalo otra vez");
        return text;
    }
}
