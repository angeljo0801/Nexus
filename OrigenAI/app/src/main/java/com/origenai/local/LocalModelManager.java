package com.origenai.local;

import android.app.DownloadManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Environment;
import org.json.JSONObject;
import java.io.*;
import java.security.MessageDigest;
import java.util.Locale;

final class LocalModelManager {
    private final Context context;
    private final SharedPreferences prefs;
    private final DownloadManager downloads;
    private final File dir;
    static final String SMALL="qwen08",LARGE="qwen2";
    private static final String SMALL_FILE="Qwen3.5-0.8B-Q4_0.gguf",LARGE_FILE="Qwen3.5-2B-Q4_0.gguf";
    private static final String SMALL_SHA="57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf";
    private static final String LARGE_SHA="cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1";
    LocalModelManager(Context c){
        context=c.getApplicationContext();
        prefs=context.getSharedPreferences("origen_gguf_downloads",Context.MODE_PRIVATE);
        downloads=(DownloadManager)context.getSystemService(Context.DOWNLOAD_SERVICE);
        File root=context.getExternalFilesDir(null);
        dir=root==null?null:new File(root,"origen-models");
        if(dir!=null)dir.mkdirs();
    }
    static boolean valid(String id){return SMALL.equals(id)||LARGE.equals(id);}
    private static String name(String id){return SMALL.equals(id)?SMALL_FILE:LARGE_FILE;}
    private static String sha(String id){return SMALL.equals(id)?SMALL_SHA:LARGE_SHA;}
    private static String url(String id){return SMALL.equals(id)?
        "https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/resolve/main/"+SMALL_FILE:
        "https://huggingface.co/ente-ai/Qwen3.5-2B-GGUF/resolve/main/"+LARGE_FILE;}
    File file(String id){
        if(!valid(id)||dir==null)throw new IllegalArgumentException("Modelo no válido o almacenamiento no disponible");
        return new File(dir,name(id));
    }
    private static boolean shape(File f){
        if(!f.isFile()||f.length()<300000000L)return false;
        try(FileInputStream in=new FileInputStream(f)){byte[] magic=new byte[4];return in.read(magic)==4 && magic[0]=='G'&&magic[1]=='G'&&magic[2]=='U'&&magic[3]=='F';}catch(IOException e){return false;}
    }
    JSONObject status(String id){
        JSONObject status=new JSONObject();
        try {
            File file=file(id);
            status.put("installed",shape(file));
            status.put("bytes",file.isFile()?file.length():0);
            status.put("expected",SMALL.equals(id)?"563 MB":"1,21 GB");
            status.put("name",name(id));
            status.put("loaded",LocalLlama.isLoaded()&&file.getAbsolutePath().equals(LocalLlama.loadedPath()));
            status.put("engine",LocalLlama.available());
            if(!LocalLlama.available())status.put("engineError",LocalLlama.error());
            long idDownload=prefs.getLong("download_"+id,-1);
            if(idDownload>=0){
                DownloadManager.Query q=new DownloadManager.Query().setFilterById(idDownload);
                try(Cursor cursor=downloads.query(q)){
                    if(cursor!=null&&cursor.moveToFirst()){
                        int state=cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                        status.put("downloading",state==DownloadManager.STATUS_PENDING||state==DownloadManager.STATUS_RUNNING||state==DownloadManager.STATUS_PAUSED);
                        status.put("downloaded",cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)));
                        status.put("total",cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)));
                        status.put("downloadFailed",state==DownloadManager.STATUS_FAILED);
                    }
                }
            }
            return status;
        }catch(Exception e){try{status.put("error",e.getMessage());}catch(Exception ignored){}return status;}
    }
    synchronized JSONObject start(String id,boolean mobile)throws Exception{
        File f=file(id);
        if(shape(f))throw new IOException("El GGUF ya está descargado");
        long running=prefs.getLong("download_"+id,-1);
        if(running>=0){
            JSONObject s=status(id);
            if(s.optBoolean("downloading"))throw new IOException("La descarga está en curso");
            downloads.remove(running);
        }
        if(!dir.isDirectory())throw new IOException("Sin almacenamiento para GGUF");
        if(f.exists()&&!f.delete())throw new IOException("No se pudo limpiar una descarga incompleta");
        DownloadManager.Request req=new DownloadManager.Request(Uri.parse(url(id)));
        req.setTitle("Origen AI · "+name(id));
        req.setDescription("Modelo neuronal GGUF para usar sin conexión");
        req.setMimeType("application/octet-stream");
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        req.setAllowedOverMetered(mobile);
        req.setAllowedOverRoaming(false);
        req.setDestinationInExternalFilesDir(context,null,"origen-models/"+name(id));
        long token=downloads.enqueue(req);
        prefs.edit().putLong("download_"+id,token).remove("verified_"+id).apply();
        return new JSONObject().put("ok",true).put("message",mobile?"Descarga iniciada":"Descarga iniciada: solo Wi-Fi");
    }
    synchronized void cancel(String id)throws Exception{
        file(id);
        long token=prefs.getLong("download_"+id,-1);
        if(token>=0)downloads.remove(token);
        prefs.edit().remove("download_"+id).apply();
        File f=file(id);if(f.exists()&&!f.delete())throw new IOException("No se pudo borrar el archivo parcial");
    }
    synchronized void delete(String id)throws Exception{
        File f=file(id);
        if(LocalLlama.isLoaded()&&f.getAbsolutePath().equals(LocalLlama.loadedPath()))throw new IOException("Descarga el modelo de memoria antes de borrarlo");
        cancel(id);prefs.edit().remove("verified_"+id).apply();
    }
    String verifiedPath(String id)throws Exception{
        File f=file(id);
        if(!shape(f))throw new IOException("El GGUF no está completo; descarga el modelo desde la aplicación");
        String marker=f.length()+":"+f.lastModified();
        if(marker.equals(prefs.getString("verified_"+id,"")))return f.getAbsolutePath();
        MessageDigest digest=MessageDigest.getInstance("SHA-256");
        try(InputStream in=new BufferedInputStream(new FileInputStream(f),1024*1024)){
            byte[] buf=new byte[1024*1024];int n;
            while((n=in.read(buf))!=-1){digest.update(buf,0,n);if(Thread.currentThread().isInterrupted())throw new IOException("Verificación interrumpida");}
        }
        StringBuilder sb=new StringBuilder();
        for(byte b:digest.digest())sb.append(String.format(Locale.US,"%02x",b&0xff));
        if(!sha(id).equals(sb.toString())){
            prefs.edit().remove("verified_"+id).apply();
            throw new IOException("La descarga GGUF no coincide con el SHA-256 oficial. Bórrala y descárgala otra vez");
        }
        prefs.edit().putString("verified_"+id,marker).apply();
        return f.getAbsolutePath();
    }
}
