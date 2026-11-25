package com.origenai.local;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
import android.net.Uri;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.AtomicFile;
import android.content.Intent;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private WebView web;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final ExecutorService pretrainedIo = Executors.newSingleThreadExecutor();
    private LocalBridge localBridge;
    private static final String KEY = "origen_sync_v1";
    private SharedPreferences prefs() { return getSharedPreferences("origen_sync", MODE_PRIVATE); }
    private javax.crypto.SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        if (!ks.containsAlias(KEY)) {
            KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            g.init(new KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            g.generateKey();
        }
        return (javax.crypto.SecretKey)ks.getKey(KEY,null);
    }
    private String encrypt(String s) throws Exception {
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE,key());
        return Base64.encodeToString(c.getIV(),Base64.NO_WRAP)+":"+Base64.encodeToString(c.doFinal(s.getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);
    }
    private String token() throws Exception {
        String v=prefs().getString("token","");
        if(v.isEmpty()) throw new IOException("Configura la conexión primero.");
        String[] p=v.split(":",2); Cipher c=Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(p[0],Base64.NO_WRAP)));
        return new String(c.doFinal(Base64.decode(p[1],Base64.NO_WRAP)),StandardCharsets.UTF_8);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); requestWindowFeature(1); web=new WebView(this);
        web.getSettings().setJavaScriptEnabled(true); web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false); web.getSettings().setAllowContentAccess(false);
        web.getSettings().setBlockNetworkLoads(true);
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {return !req.getUrl().toString().equals("file:///android_asset/index.html");}
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {return !url.equals("file:///android_asset/index.html");}
        });
        web.addJavascriptInterface(new SyncBridge(),"OrigenSync");
        web.addJavascriptInterface(new PretrainedBridge(),"OrigenPretrained");
        localBridge=new LocalBridge(this);
        web.addJavascriptInterface(localBridge,"OrigenLocal");
        web.addJavascriptInterface(new ModelStore(),"OrigenStore");
        setContentView(web); web.loadUrl("file:///android_asset/index.html");
    }
    private static final int MAX_MODEL_BYTES=96*1024*1024;
    private static final int EXPORT_MODEL=713, IMPORT_MODEL=714, EXPORT_PRETRAIN=715;
    private volatile String pretrainedExport="";
    private final Object checkpointLock=TrainingService.FILE_LOCK;
    private AtomicFile checkpoint(boolean backup){return new AtomicFile(new File(getFilesDir(),backup?"origen-before-expand.json":"origen-checkpoint.json"));}
    private String readModel(AtomicFile file) throws IOException {
        if(!file.getBaseFile().exists()&&!new File(file.getBaseFile().getPath()+".bak").exists())return "";
        byte[] bytes=file.readFully();if(bytes.length>MAX_MODEL_BYTES)throw new IOException("Model too large");
        return new String(bytes,StandardCharsets.UTF_8);
    }
    private void writeModel(AtomicFile file,String json) throws IOException {
        byte[] bytes=json.getBytes(StandardCharsets.UTF_8);if(bytes.length==0||bytes.length>MAX_MODEL_BYTES)throw new IOException("Model too large");
        FileOutputStream stream=null;try{stream=file.startWrite();stream.write(bytes);file.finishWrite(stream);}catch(IOException e){if(stream!=null)file.failWrite(stream);throw e;}
    }
    private class ModelStore {
        @JavascriptInterface public boolean nativeActive(){return TrainingService.isActive();}
        @JavascriptInterface public String nativeProgress(){return TrainingService.status();}
        @JavascriptInterface public boolean startNative(int count,double lr,boolean remote){return TrainingService.launch(MainActivity.this,count,lr,remote);}
        @JavascriptInterface public void pauseNative(){prefs().edit().putBoolean("auto_enabled",false).commit();TrainingService.requestPause();}
        @JavascriptInterface public boolean nativeSafeToResume(){return TrainingService.safeToResume(MainActivity.this);}
        @JavascriptInterface public boolean notificationEnabled(){return getSystemService(android.app.NotificationManager.class).areNotificationsEnabled();}

        @JavascriptInterface public void keepAwake(boolean enabled){runOnUiThread(()->{if(enabled)getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);else getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);});}
        @JavascriptInterface public String read(){synchronized(checkpointLock){try{return readModel(checkpoint(false));}catch(Exception e){return "!ERROR";}}}
        @JavascriptInterface public boolean write(String json){synchronized(checkpointLock){if(TrainingService.isActive())return false;try{writeModel(checkpoint(false),json);return true;}catch(Exception e){return false;}}}
        @JavascriptInterface public boolean archive(String json){synchronized(checkpointLock){if(TrainingService.isActive())return false;try{writeModel(checkpoint(true),json);return true;}catch(Exception e){return false;}}}
        @JavascriptInterface public String imported(){synchronized(checkpointLock){try{return readModel(new AtomicFile(new File(getFilesDir(),"origen-import.json")));}catch(Exception e){return "!ERROR";}}}
        @JavascriptInterface public String archived(){synchronized(checkpointLock){try{return readModel(checkpoint(true));}catch(Exception e){return "!ERROR";}}}
        @JavascriptInterface public void exportFile(){runOnUiThread(()->{Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.setType("application/json");i.addCategory(Intent.CATEGORY_OPENABLE);i.putExtra(Intent.EXTRA_TITLE,"OrigenAI-backup.json");try{startActivityForResult(i,EXPORT_MODEL);}catch(Exception e){modelNotice("No se pudo abrir el selector de archivos.");}});}
        @JavascriptInterface public void importFile(){runOnUiThread(()->{Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.setType("application/json");i.addCategory(Intent.CATEGORY_OPENABLE);try{startActivityForResult(i,IMPORT_MODEL);}catch(Exception e){modelNotice("No se pudo abrir el selector de archivos.");}});}
    }
    private void modelNotice(String text){runOnUiThread(()->{if(web!=null)web.evaluateJavascript("window.origenFileNotice("+JSONObject.quote(text)+")",null);});}
    @Override protected void onActivityResult(int request,int result,Intent intent){
        super.onActivityResult(request,result,intent);
        if(request!=EXPORT_MODEL&&request!=IMPORT_MODEL&&request!=EXPORT_PRETRAIN)return;
        if(result!=RESULT_OK||intent==null||intent.getData()==null){modelNotice("Operación cancelada.");return;}
        Uri uri=intent.getData();
        io.execute(()->{try{
            if(request==EXPORT_PRETRAIN){String value=pretrainedExport;pretrainedExport="";try(OutputStream out=getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException();out.write(value.getBytes(StandardCharsets.UTF_8));}pretrainedNotice("Ejemplos exportados para entrenamiento LoRA.");}
            else if(request==EXPORT_MODEL){synchronized(checkpointLock){String value=readModel(checkpoint(false));if(value.isEmpty())throw new IOException();try(OutputStream out=getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException();out.write(value.getBytes(StandardCharsets.UTF_8));}}modelNotice("Respaldo exportado.");}
            else{
                ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=getContentResolver().openInputStream(uri)){if(in==null)throw new IOException();byte[] buf=new byte[65536];int n;while((n=in.read(buf))!=-1){if(out.size()+n>MAX_MODEL_BYTES)throw new IOException();out.write(buf,0,n);}}
                String value=new String(out.toByteArray(),StandardCharsets.UTF_8);
                // Avoid injecting huge JSON into JS source. Save to a private staged file and notify JS.
                synchronized(checkpointLock){writeModel(new AtomicFile(new File(getFilesDir(),"origen-import.json")),value);}
                runOnUiThread(()->{if(web!=null)web.evaluateJavascript("window.origenImportReady()",null);});
            }
        }catch(Exception e){modelNotice("No se pudo procesar el archivo.");}});
    }
    void localNotice(String message){pretrainedNotice(message);}
    void localResult(String id,JSONObject result){pretrainedReply(id,result);}
    private void pretrainedNotice(String message){runOnUiThread(()->{if(web!=null)web.evaluateJavascript("window.origenPretrainedNotice&&window.origenPretrainedNotice("+JSONObject.quote(message)+")",null);});}
    private void pretrainedReply(String id,JSONObject response){runOnUiThread(()->{if(web!=null)web.evaluateJavascript("window.origenPretrainedReply("+JSONObject.quote(id)+","+JSONObject.quote(response.toString())+")",null);});}
    private static URL localEndpoint(String endpoint,String transport) throws Exception {
        if(endpoint==null||endpoint.length()>160||!transport.equals("ollama")&&!transport.equals("openai"))throw new IOException("Configuración inválida");
        java.net.URI uri=new java.net.URI(endpoint.trim());
        String host=uri.getHost();int port=uri.getPort();
        if(!"http".equals(uri.getScheme())||host==null||port<1||port>65535||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null||(uri.getRawPath()!=null&&!uri.getRawPath().isEmpty()&&!uri.getRawPath().equals("/")))throw new IOException("Introduce una dirección HTTP local y un puerto");
        String h=host.toLowerCase(java.util.Locale.ROOT);
        if(!h.equals("localhost")&&!h.equals("127.0.0.1")&&!h.equals("::1")&&!h.matches("(?:10\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}|192\\.168\\.[0-9]{1,3}\\.[0-9]{1,3}|172\\.(?:1[6-9]|2[0-9]|3[01])\\.[0-9]{1,3}\\.[0-9]{1,3})"))throw new IOException("Solo se permiten motores locales o de la red privada");
        java.net.InetAddress a=java.net.InetAddress.getByName(host);
        if(!a.isLoopbackAddress()&&!a.isSiteLocalAddress())throw new IOException("Dirección fuera de la red privada");
        String path=transport.equals("ollama")?"/api/chat":"/v1/chat/completions";
        return new URL("http",host,port,path);
    }
    private class PretrainedBridge {
        private final AtomicFile file=new AtomicFile(new File(getFilesDir(),"origen-pretrained.json"));
        @JavascriptInterface public String read(){synchronized(checkpointLock){try{return readModel(file);}catch(Exception e){return "!ERROR";}}}
        @JavascriptInterface public boolean write(String json){synchronized(checkpointLock){try{if(json==null||json.length()>1500000)return false;JSONObject obj=new JSONObject(json);if(obj.optInt("version")!=1)return false;writeModel(file,json);return true;}catch(Exception e){return false;}}}
        @JavascriptInterface public void exportExamples(String jsonl){if(jsonl==null||jsonl.length()>1200000)return;pretrainedExport=jsonl;runOnUiThread(()->{Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.setType("application/x-ndjson");i.addCategory(Intent.CATEGORY_OPENABLE);i.putExtra(Intent.EXTRA_TITLE,"OrigenAI-LoRA.jsonl");try{startActivityForResult(i,EXPORT_PRETRAIN);}catch(Exception e){pretrainedNotice("No se pudo abrir el selector de archivos.");}});}
        @JavascriptInterface public void request(String id,String endpoint,String transport,String model,String messages){
            if(id==null||id.length()>60)return;
            pretrainedIo.execute(()->{JSONObject result=new JSONObject();try{
                URL url=localEndpoint(endpoint,transport);
                if(model==null||model.length()>120||model.trim().isEmpty())throw new IOException("Modelo inválido");
                org.json.JSONArray input=new org.json.JSONArray(messages);
                if(input.length()<1||input.length()>24||messages.length()>18000)throw new IOException("Conversación demasiado larga");
                for(int i=0;i<input.length();i++){JSONObject row=input.getJSONObject(i);String role=row.getString("role"),content=row.getString("content");if(!role.equals("system")&&!role.equals("user")&&!role.equals("assistant")||content.length()>3500)throw new IOException("Mensaje inválido");}
                JSONObject body=new JSONObject().put("model",model).put("messages",input).put("stream",false);
                if(transport.equals("ollama"))body.put("options",new JSONObject().put("num_ctx",2048));else body.put("max_tokens",256);
                HttpURLConnection c=(HttpURLConnection)url.openConnection();try{
                    c.setInstanceFollowRedirects(false);c.setConnectTimeout(10000);c.setReadTimeout(120000);c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");
                    try(OutputStream o=c.getOutputStream()){o.write(body.toString().getBytes(StandardCharsets.UTF_8));}
                    int code=c.getResponseCode();if(code!=200)throw new IOException("Motor HTTP "+code+"; comprueba que el modelo esté cargado");
                    ByteArrayOutputStream output=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){if(output.size()+n>600000)throw new IOException("Respuesta demasiado larga");output.write(buf,0,n);}}
                    JSONObject raw=new JSONObject(new String(output.toByteArray(),StandardCharsets.UTF_8));
                    String answer=transport.equals("ollama")?raw.getJSONObject("message").optString("content",""):raw.getJSONArray("choices").getJSONObject(0).getJSONObject("message").optString("content","");
                    if(answer.trim().isEmpty())throw new IOException("El motor devolvió una respuesta vacía");
                    result.put("ok",true).put("answer",answer);
                }finally{c.disconnect();}
            }catch(Exception e){try{result=new JSONObject().put("ok",false).put("error",e.getMessage()==null?"Error del motor local":e.getMessage());}catch(Exception ignored){}}pretrainedReply(id,result);});
        }
    }
    private static class Response { int code; String body; Response(int c,String b){code=c;body=b;} }
    private Response http(String repo,String tok,String suffix,String method,String body) throws Exception {
        HttpURLConnection c=(HttpURLConnection)new URL("https://api.github.com/repos/"+repo+suffix).openConnection();
        try{
            c.setInstanceFollowRedirects(false); c.setConnectTimeout(12000);c.setReadTimeout(15000);c.setRequestMethod(method);
            c.setRequestProperty("Authorization","Bearer "+tok);c.setRequestProperty("Accept","application/vnd.github+json");
            c.setRequestProperty("X-GitHub-Api-Version","2022-11-28");c.setRequestProperty("User-Agent","OrigenAI-Android");
            if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");try(OutputStream out=c.getOutputStream()){out.write(body.getBytes(StandardCharsets.UTF_8));}}
            int code=c.getResponseCode(); InputStream in=code>=400?c.getErrorStream():c.getInputStream();
            ByteArrayOutputStream out=new ByteArrayOutputStream(); if(in!=null){try(InputStream stream=in){byte[] buf=new byte[8192];int n;while((n=stream.read(buf))!=-1){if(out.size()+n>1500000)throw new IOException("Respuesta demasiado grande");out.write(buf,0,n);}}}
            return new Response(code,new String(out.toByteArray(),StandardCharsets.UTF_8));
        }finally{c.disconnect();}
    }
    private JSONObject checkPrivate(String repo,String tok) throws Exception {
        if(!repo.matches("[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}"))throw new IOException("Repositorio inválido");
        Response r=http(repo,tok,"","GET",null); if(r.code!=200)throw new IOException("GitHub: HTTP "+r.code+" al verificar repositorio");
        JSONObject j=new JSONObject(r.body);if(!j.optBoolean("private",false)||!"private".equals(j.optString("visibility")))throw new IOException("Solo se permiten repositorios privados.");
        return j;
    }
    private void reply(String id,JSONObject value){runOnUiThread(()->{if(web!=null)web.evaluateJavascript("window.origenSyncReply("+JSONObject.quote(id)+","+JSONObject.quote(value.toString())+")",null);});}
    private class SyncBridge {
        @JavascriptInterface public String repository(){return prefs().getString("repo","");}
        @JavascriptInterface public boolean autoEnabled(){return !repository().isEmpty()&&prefs().getBoolean("auto_enabled",false);}
        @JavascriptInterface public boolean setAutoEnabled(boolean enabled){return prefs().edit().putBoolean("auto_enabled",enabled&&!repository().isEmpty()).commit();}
        @JavascriptInterface public void request(String id,String op,String a,String b){
            if(id==null||id.length()>100)return;
            io.execute(()->{JSONObject out=new JSONObject();try{
                if("clear".equals(op)){prefs().edit().clear().commit();out.put("ok",true);}
                else if("configure".equals(op)){
                    if(b==null||b.length()<20||b.length()>1024||b.matches(".*\\s.*"))throw new IOException("Token inválido");
                    checkPrivate(a,b);
                    SharedPreferences.Editor edit=prefs().edit().putString("repo",a).putString("token",encrypt(b));
                    if(!a.equals(repository()))edit.remove("auto_enabled");
                    if(!edit.commit())throw new IOException("No se pudo guardar conexión");
                    out.put("ok",true);
                }else{
                    String repo=repository(),tok=token();checkPrivate(repo,tok);
                    if("pull".equals(op)){
                        Response r=http(repo,tok,"/contents/origen-training.json","GET",null);
                        if(r.code==404){out.put("payload","");}else if(r.code==200){
                            JSONObject j=new JSONObject(r.body);byte[] bytes=Base64.decode(j.getString("content"),Base64.DEFAULT);
                            if(bytes.length>350000)throw new IOException("Lote demasiado grande");
                            out.put("payload",new String(bytes,StandardCharsets.UTF_8));
                        }else throw new IOException("GitHub: HTTP "+r.code+" al recibir lote");
                    }else if("pre_pull".equals(op)){
                        Response task=http(repo,tok,"/contents/origen-pretrained-requests.json","GET",null);
                        if(task.code==404){out.put("payload","");}
                        else if(task.code==200){
                            JSONObject file=new JSONObject(task.body);
                            byte[] bytes=Base64.decode(file.getString("content"),Base64.DEFAULT);
                            if(bytes.length>7000)throw new IOException("Solicitud de evaluación demasiado grande");
                            out.put("payload",new String(bytes,StandardCharsets.UTF_8));
                        }else throw new IOException("GitHub: HTTP "+task.code+" en solicitudes de evaluación");
                        Response prev=http(repo,tok,"/contents/origen-pretrained-status.json","GET",null);
                        if(prev.code==200){
                            JSONObject file=new JSONObject(prev.body);
                            byte[] bytes=Base64.decode(file.getString("content"),Base64.DEFAULT);
                            if(bytes.length>30000)throw new IOException("Estado de evaluación demasiado grande");
                            JSONObject previous=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
                            out.put("lastId",previous.optString("id",""));
                        }else if(prev.code!=404)throw new IOException("GitHub: HTTP "+prev.code+" en estado de evaluación");
                    }else if("pre_push".equals(op)){
                        if(a==null||a.length()>25000)throw new IOException("Evaluación fuera de tamaño permitido");
                        JSONObject status=new JSONObject(a);
                        String id=status.optString("id","");
                        String modelId=status.optString("model","");
                        String state=status.optString("state","");
                        if(status.optInt("version",-1)!=1 || !id.matches("[A-Za-z0-9._-]{1,90}") ||
                            !("qwen08".equals(modelId)||"qwen2".equals(modelId)) ||
                            !("completed".equals(state)||"error".equals(state)))
                            throw new IOException("Resultado remoto inválido");
                        Response current=http(repo,tok,"/contents/origen-pretrained-requests.json","GET",null);
                        if(current.code!=200)throw new IOException("Solicitud remota ya no disponible");
                        byte[] jobBytes=Base64.decode(new JSONObject(current.body).getString("content"),Base64.DEFAULT);
                        if(jobBytes.length>7000)throw new IOException("Solicitud remota demasiado grande");
                        JSONObject job=new JSONObject(new String(jobBytes,StandardCharsets.UTF_8));
                        if(!id.equals(job.optString("id"))||!modelId.equals(job.optString("model")))
                            throw new IOException("La solicitud cambió durante la evaluación");
                        org.json.JSONArray questions=job.optJSONArray("questions");
                        org.json.JSONArray results=status.optJSONArray("results");
                        if(questions==null||questions.length()<1||questions.length()>5||
                            results==null||results.length()>(questions.length()) ||
                            ("completed".equals(state)&&results.length()!=questions.length()))
                            throw new IOException("Resultados incompletos o incorrectos");
                        for(int i=0;i<results.length();i++){
                            JSONObject item=results.getJSONObject(i);
                            String question=item.optString("q",""), answer=item.optString("a","");
                            if(!question.equals(questions.getString(i))||answer.isEmpty()||answer.length()>4000)
                                throw new IOException("Los resultados no coinciden con las preguntas enviadas");
                        }
                        if("error".equals(state)&&status.optString("error","").length()>300)
                            throw new IOException("Error demasiado largo");
                        Response prev=http(repo,tok,"/contents/origen-pretrained-status.json","GET",null);
                        JSONObject body=new JSONObject()
                            .put("message","Origen AI: resultado de evaluación local preentrenada")
                            .put("content",Base64.encodeToString(a.getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP));
                        if(prev.code==200)body.put("sha",new JSONObject(prev.body).getString("sha"));
                        else if(prev.code!=404)throw new IOException("GitHub: HTTP "+prev.code+" al comprobar resultado");
                        Response pushed=http(repo,tok,"/contents/origen-pretrained-status.json","PUT",body.toString());
                        if(pushed.code!=200&&pushed.code!=201)
                            throw new IOException("GitHub: HTTP "+pushed.code+" al publicar resultados");
                    }else if("push".equals(op)){
                        if(a==null||a.length()>30000)throw new IOException("Estado demasiado grande");
                        new JSONObject(a);Response prev=http(repo,tok,"/contents/origen-status.json","GET",null);
                        JSONObject body=new JSONObject().put("message","Origen AI: actualizar estado").put("content",Base64.encodeToString(a.getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP));
                        if(prev.code==200)body.put("sha",new JSONObject(prev.body).getString("sha"));else if(prev.code!=404)throw new IOException("GitHub: HTTP "+prev.code);
                        Response r=http(repo,tok,"/contents/origen-status.json","PUT",body.toString());
                        if(r.code!=200&&r.code!=201)throw new IOException("GitHub: HTTP "+r.code+" al enviar estado");
                    }else throw new IOException("Operación no permitida");
                    out.put("ok",true);
                }
            }catch(Exception e){try{out=new JSONObject().put("ok",false).put("error",e instanceof IOException?e.getMessage():"Error de conexión o almacenamiento seguro");}catch(Exception ignored){}}
            reply(id,out);
            });
        }
    }
    @Override protected void onResume(){super.onResume();if(web!=null)web.evaluateJavascript("window.origenPollNative&&window.origenPollNative();window.origenResumeSync&&window.origenResumeSync()",null);}
    @Override protected void onDestroy(){io.shutdownNow();pretrainedIo.shutdownNow();if(localBridge!=null)localBridge.close();if(web!=null){web.removeJavascriptInterface("OrigenSync");web.removeJavascriptInterface("OrigenPretrained");web.removeJavascriptInterface("OrigenLocal");web.removeJavascriptInterface("OrigenStore");web.destroy();web=null;}super.onDestroy();}
}
