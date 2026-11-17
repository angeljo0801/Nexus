package com.origenai.local;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
import android.net.Uri;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
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
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {return !req.getUrl().toString().equals("file:///android_asset/index.html");}
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {return !url.equals("file:///android_asset/index.html");}
        });
        web.addJavascriptInterface(new SyncBridge(),"OrigenSync");
        setContentView(web); web.loadUrl("file:///android_asset/index.html");
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
        @JavascriptInterface public void request(String id,String op,String a,String b){
            if(id==null||id.length()>100)return;
            io.execute(()->{JSONObject out=new JSONObject();try{
                if("clear".equals(op)){prefs().edit().clear().commit();out.put("ok",true);}
                else if("configure".equals(op)){
                    if(b==null||b.length()<20||b.length()>1024||b.matches(".*\\s.*"))throw new IOException("Token inválido");
                    checkPrivate(a,b);
                    if(!prefs().edit().putString("repo",a).putString("token",encrypt(b)).commit())throw new IOException("No se pudo guardar conexión");
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
    @Override protected void onDestroy(){io.shutdownNow();if(web!=null){web.removeJavascriptInterface("OrigenSync");web.destroy();web=null;}super.onDestroy();}
}
