package com.origenai.local;
public final class ResponseQualityTest {
    private static void eq(String actual,String expected){
        if(!actual.equals(expected))throw new AssertionError("Se esperaba: "+expected+"; llegó: "+actual);
    }
    private static void rejected(String data){
        try{ResponseQuality.clean(data);throw new AssertionError("Debía rechazar resultado incompleto");}
        catch(IllegalArgumentException expected){}
    }
    public static void main(String[] args){
        eq(ResponseQuality.clean("<think>pensamiento interno</think> Hola, ¿cómo estás?"),"Hola, ¿cómo estás?");
        eq(ResponseQuality.clean("<think>\n\n</think>\nLa respuesta correcta es sencilla."),"La respuesta correcta es sencilla.");
        eq(ResponseQuality.clean("</think>\nSí, claro."),"Sí, claro.");
        eq(ResponseQuality.clean(" Respuesta normal en español. "),"Respuesta normal en español.");
        eq(ResponseQuality.clean("<think>x</think><think>y</think>Respuesta"),"Respuesta");
        rejected("<think>texto sin cerrar");
        rejected("<think></think>");
        rejected("");
        System.out.println("ResponseQuality: 8 casos superados");
    }
}
