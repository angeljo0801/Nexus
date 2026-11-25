package com.origenai.local;

public final class LocalLlama {
    private static boolean available;
    private static String error="";
    private static volatile boolean loaded=false;
    private static String loadedPath="";
    static {
        try { System.loadLibrary("origenllama"); available=true; }
        catch (Throwable e) { error="No se pudo iniciar la biblioteca nativa ARM64: "+e.getClass().getSimpleName(); }
    }
    private LocalLlama(){}
    private static native String nativeLoad(String path,int nCtx);
    private static native String nativeGenerate(String[] roles,String[] contents,int maxTokens);
    private static native void nativeStop();
    private static native void nativeUnload();
    public static boolean available(){return available;}
    public static String error(){return error;}
    public static boolean isLoaded(){return loaded;}
    public static synchronized String load(String path){
        if(!available)throw new IllegalStateException(error);
        if(loaded&&loadedPath.equals(path))return "Modelo ya cargado";
        String result=nativeLoad(path,3072);
        loaded=true;loadedPath=path;
        return result;
    }
    public static synchronized String generate(String[] roles,String[] contents){
        if(!loaded)throw new IllegalStateException("Modelo sin cargar");
        return ResponseQuality.clean(nativeGenerate(roles,contents,320));
    }
    public static void stop(){if(available)nativeStop();}
    public static synchronized void unload(){
        if(available)nativeUnload();
        loaded=false;loadedPath="";
    }
    public static String loadedPath(){return loadedPath;}
}
