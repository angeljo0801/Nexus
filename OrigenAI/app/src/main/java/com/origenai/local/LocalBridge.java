package com.origenai.local;

import android.webkit.JavascriptInterface;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

public final class LocalBridge {
    private final MainActivity activity;
    private final LocalModelManager models;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private volatile boolean busy=false;

    LocalBridge(MainActivity host){
        activity=host;
        models=new LocalModelManager(host);
    }
    private String reply(boolean success,String value){
        JSONObject result=new JSONObject();
        try{
            result.put("ok",success);
            if(success)result.put("message",value);
            else result.put("error",value);
        }catch(Exception ignored){}
        return result.toString();
    }
    @JavascriptInterface public String status(String variant){
        if(!LocalModelManager.valid(variant))return reply(false,"Modelo no disponible");
        JSONObject result=models.status(variant);
        try{result.put("generating",busy);}catch(Exception ignored){}
        return result.toString();
    }
    @JavascriptInterface public String download(String variant,boolean allowMobile){
        try{return models.start(variant,allowMobile).toString();}
        catch(Exception error){return reply(false,error.getMessage());}
    }
    @JavascriptInterface public String cancel(String variant){
        try{models.cancel(variant);return reply(true,"Descarga cancelada");}
        catch(Exception error){return reply(false,error.getMessage());}
    }
    @JavascriptInterface public String delete(String variant){
        if(busy)return reply(false,"Detén la generación antes de borrar el modelo");
        try{models.delete(variant);return reply(true,"Modelo eliminado del almacenamiento del teléfono");}
        catch(Exception error){return reply(false,error.getMessage());}
    }
    @JavascriptInterface public void stop(){LocalLlama.stop();}
    @JavascriptInterface public void unload(){
        LocalLlama.stop();
        worker.execute(()->{
            LocalLlama.unload();
            activity.localNotice("Modelo descargado de RAM. El archivo GGUF sigue guardado.");
        });
    }
    @JavascriptInterface public void request(String id,String variant,String serialized){
        if(id==null||id.length()>60)return;
        worker.execute(()->{
            JSONObject output=new JSONObject();
            try{
                if(!LocalModelManager.valid(variant))throw new IOException("Modelo no válido");
                if(TrainingService.isActive())throw new IOException("Pausa el entrenamiento experimental antes de cargar el modelo preentrenado");
                if(busy)throw new IOException("El motor local está ocupado");
                busy=true;
                String file=models.verifiedPath(variant);
                LocalLlama.load(file);
                if(serialized==null||serialized.length()>16000)throw new IOException("Conversación demasiado larga");
                JSONArray data=new JSONArray(serialized);
                if(data.length()<1||data.length()>16)throw new IOException("Demasiados mensajes; limpia el historial");
                String[] roles=new String[data.length()],contents=new String[data.length()];
                for(int i=0;i<data.length();i++){
                    JSONObject message=data.getJSONObject(i);
                    roles[i]=message.getString("role");
                    contents[i]=message.getString("content");
                    if(contents[i].length()>3500)throw new IOException("Mensaje demasiado largo");
                }
                String answer=LocalLlama.generate(roles,contents);
                output.put("ok",true).put("answer",answer).put("source","on-device");
            }catch(Throwable error){
                try{output.put("ok",false).put("error",
                    error.getMessage()==null?"Error al ejecutar GGUF":error.getMessage());}
                catch(Exception ignored){}
            }finally{busy=false;}
            activity.localResult(id,output);
        });
    }
    void close(){
        LocalLlama.stop();
        worker.shutdownNow();
    }
}
