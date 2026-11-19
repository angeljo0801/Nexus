package com.origenai.local;

import android.app.*;
import android.content.*;
import android.os.*;
import android.util.AtomicFile;
import android.security.keystore.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

public final class TrainingService extends Service {
    static final Object FILE_LOCK=new Object();
    private static final String CHANNEL="origen_training", ACTION_PAUSE="com.origenai.local.PAUSE_TRAINING";
    private static final int NOTICE=701;
    private static volatile boolean active=false, pause=false;
    private static volatile String state="{\"active\":false}";
    private static long generation=0;
    private PowerManager.WakeLock wake;
    private Thread worker;
    private volatile boolean destroyed=false,finished=false;
    private NotificationManager notifications;
    static synchronized boolean launch(Context context,int count,double lr,boolean remote){
        if(active||count<0||(!remote&&count==0)||count>10000||!(lr==.003||lr==.001||lr==.0003))return false;
        active=true;pause=false;generation++;
        state="{\"active\":true,\"generation\":"+generation+",\"phase\":\"Preparando modelo\",\"done\":0,\"total\":"+count+"}";
        Intent i=new Intent(context,TrainingService.class).putExtra("count",count).putExtra("lr",lr).putExtra("remote",remote);
        try{context.startForegroundService(i);return true;}catch(RuntimeException e){active=false;state="{\"active\":false,\"error\":\"Android no permitió iniciar el servicio\"}";return false;}
    }
    static boolean isActive(){return active;}
    static String status(){return state;}
    static void requestPause(){pause=true;}
    static AtomicFile checkpoint(Context c){return new AtomicFile(new File(c.getFilesDir(),"origen-checkpoint.json"));}
    static String read(Context c)throws IOException{synchronized(FILE_LOCK){return new String(checkpoint(c).readFully(),StandardCharsets.UTF_8);}}
    static void write(Context c,String data)throws IOException{synchronized(FILE_LOCK){byte[] b=data.getBytes(StandardCharsets.UTF_8);if(b.length>96*1024*1024)throw new IOException("Respaldo demasiado grande");AtomicFile f=checkpoint(c);FileOutputStream s=null;try{s=f.startWrite();s.write(b);f.finishWrite(s);}catch(IOException e){if(s!=null)f.failWrite(s);throw e;}}}
    @Override public IBinder onBind(Intent i){return null;}
    @Override public void onCreate(){super.onCreate();notifications=getSystemService(NotificationManager.class);NotificationChannel c=new NotificationChannel(CHANNEL,"Entrenamiento de Origen AI",NotificationManager.IMPORTANCE_LOW);c.setDescription("Progreso del aprendizaje neuronal local");notifications.createNotificationChannel(c);}
    private Notification notice(String message,int done,int total){
        Intent open=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,TrainingService.class).setAction(ACTION_PAUSE),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Origen AI · Entrenamiento").setContentText(message).setStyle(new Notification.BigTextStyle().bigText(message)).setContentIntent(pi).setOngoing(true).setOnlyAlertOnce(true).setProgress(Math.max(1,total),Math.min(done,total),done==0).addAction(new Notification.Action.Builder(null,"Pausar y guardar",stop).build()).build();
    }
    @Override public int onStartCommand(Intent i,int flags,int id){
        if(i!=null&&ACTION_PAUSE.equals(i.getAction())){getSharedPreferences("origen_sync",MODE_PRIVATE).edit().putBoolean("auto_enabled",false).commit();requestPause();if(worker==null)stopSelf();return START_NOT_STICKY;}
        if(i==null||!active){stopSelf();return START_NOT_STICKY;}
        if(worker!=null)return START_NOT_STICKY;
        int total=i.getIntExtra("count",0);double lr=i.getDoubleExtra("lr",.0003);boolean remote=i.getBooleanExtra("remote",false);
        try{startForeground(NOTICE,notice("Preparando pesos…",0,total));}catch(RuntimeException e){state="{\"active\":false,\"error\":\"Android rechazó la notificación de entrenamiento\"}";finished=true;stopSelf();return START_NOT_STICKY;}
        PowerManager pm=getSystemService(PowerManager.class);wake=pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"OrigenAI:Training");wake.setReferenceCounted(false);wake.acquire(4*60*60*1000L+60000);
        worker=new Thread(()->runTraining(total,lr,remote),"origen-native-training");worker.start();return START_NOT_STICKY;
    }
    @Override public void onDestroy(){destroyed=true;requestPause();if(worker==null||finished){active=false;if(wake!=null&&wake.isHeld())wake.release();}super.onDestroy();}
    private static int[][] extras(JSONObject o)throws JSONException{JSONArray a=o.optJSONArray("extra");if(a==null)return new int[0][];int[][] r=new int[a.length()][2];for(int i=0;i<r.length;i++){JSONArray p=a.getJSONArray(i);r[i][0]=p.getInt(0);r[i][1]=p.getInt(1);}return r;}
    private NativeModel load(JSONObject o)throws Exception{
        String format=o.getString("format");boolean deep=format.equals("origen-deep-bpe-2");
        if(!deep&&!format.equals("origen-transformer-bpe-1"))throw new IOException("Formato de pesos desconocido");
        NativeModel model=new NativeModel(o.getInt("d"),o.getInt("ctx"),extras(o),deep);
        for(String key:model.p.keySet()){NativeModel.unpack(o.getJSONObject("p").getString(key),model.p.get(key));NativeModel.unpack(o.getJSONObject("m").getString(key),model.m.get(key));NativeModel.unpack(o.getJSONObject("v").getString(key),model.v.get(key));}
        model.step=o.getLong("step");model.optStep=o.optLong("optStep",model.step);model.loss=o.isNull("loss")?null:o.getDouble("loss");return model;
    }
    private void saveModel(JSONObject root,NativeModel model)throws Exception{
        JSONObject o=root.getJSONObject("model");o.put("step",model.step).put("optStep",model.optStep).put("loss",model.loss==null?JSONObject.NULL:model.loss);
        for(String key:model.p.keySet()){o.getJSONObject("p").put(key,NativeModel.pack(model.p.get(key)));o.getJSONObject("m").put(key,NativeModel.pack(model.m.get(key)));o.getJSONObject("v").put(key,NativeModel.pack(model.v.get(key)));}
        write(this,root.toString());
    }
    private void publish(NativeModel m,int done,int total,long start,String phase,boolean working,String error){
        long elapsed=Math.max(0,SystemClock.elapsedRealtime()-start);double speed=done==0?0:done/Math.max(.001,elapsed/1000.0);
        try{JSONObject o=new JSONObject().put("active",working).put("generation",generation).put("phase",phase).put("done",done).put("total",total).put("elapsed",elapsed/1000).put("speed",speed).put("eta",speed>0?Math.ceil((total-done)/speed):JSONObject.NULL);
            if(m!=null)o.put("step",m.step).put("optimizerSteps",m.optStep).put("loss",m.loss==null?JSONObject.NULL:m.loss);
            if(error!=null)o.put("error",error);state=o.toString();
        }catch(JSONException ignored){}
        if(working){String msg=phase+" · "+done+"/"+total+(speed>0?String.format(Locale.US," · %.2f pasos/s",speed):"");notifications.notify(NOTICE,notice(msg,done,total));}
    }
    private boolean safetyStop(long start){
        if(SystemClock.elapsedRealtime()-start>=4*60*60*1000L)return true;
        PowerManager pm=getSystemService(PowerManager.class);
        if(Build.VERSION.SDK_INT>=29&&pm.getCurrentThermalStatus()>=PowerManager.THERMAL_STATUS_SEVERE)return true;
        Intent b=registerReceiver(null,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if(b!=null){int level=b.getIntExtra(BatteryManager.EXTRA_LEVEL,-1),scale=b.getIntExtra(BatteryManager.EXTRA_SCALE,100),plug=b.getIntExtra(BatteryManager.EXTRA_PLUGGED,0);if(level>=0&&scale>0&&level*100/scale<=10&&plug==0)return true;}
        return false;
    }
    private static final String[][] REFERENCE={
      {"Me acaban de confirmar que conseguí una beca.","¡Felicidades! ¿Cuándo comienzas?"},
      {"No pude terminar lo que había planeado.","¿Qué te faltó por hacer?"},
      {"¿Para qué se utiliza un paraguas?","Para protegerse de la lluvia."},
      {"No estoy seguro de haber entendido tu explicación.","Dime qué parte quieres que aclare."},
      {"Tengo una duda sobre cómo organizar mi semana.","Podemos empezar por tus tareas más importantes."},
      {"¿Qué significa la palabra temprano?","Significa antes de lo habitual o al comienzo del día."},
      {"Me voy a reunir con mis amigos esta noche.","¡Que lo pases bien!"},
      {"Hoy quiero dedicar un rato a aprender algo.","¿Qué tema te gustaría aprender?"},
      {"Gracias por ayudarme a comprenderlo.","De nada, me alegra haberte ayudado."},
      {"¿Qué dirías si desconocieras la respuesta?","Diría que no lo sé."},
      {"","Al volver del mercado, guardé las verduras en la nevera."},
      {"","El cielo estaba despejado y decidimos caminar hasta la plaza."}
    };
    private static String key(JSONObject item){return item.optString("kind").equals("dialog")?item.optString("q").trim().toLowerCase(Locale.ROOT):item.optString("text").trim();}
    private JSONObject reference(NativeModel model,Set<String> seen)throws Exception{double sum=0,tokens=0;int n=0;for(String[] row:REFERENCE){if(pause)break;boolean d=!row[0].isEmpty();String key=d?row[0].trim().toLowerCase(Locale.ROOT):row[1].trim();if(seen.contains(key))continue;double[] z=model.referenceLoss(model.example(row[0],row[1],d,new Random(0)));sum+=z[0];tokens+=z[1];n++;}return new JSONObject().put("loss",tokens>0?sum/tokens:JSONObject.NULL).put("examples",n).put("vocab",model.vocab).put("architecture",model.layers);}
    private void runTraining(int requested,double lr,boolean remote){
        NativeModel m=null;JSONObject root=null,job=null;int done=0,total=requested;long start=SystemClock.elapsedRealtime(),lastSave=start,lastReport=start,lastUi=0;String error=null,phase="Pausado";boolean loaded=false;
        try{
            root=new JSONObject(read(this));m=load(root.getJSONObject("model"));loaded=true;job=root.optJSONObject("syncJob");if(remote&&(job==null||job.optString("id").isEmpty()))throw new IOException("Lote remoto no guardado");if(!remote&&job!=null)throw new IOException("Existe un lote remoto pendiente");
            if(remote){long remaining=Math.max(0,job.getLong("target")-m.step);if(remaining>10000)throw new IOException("Objetivo remoto inválido");total=(int)remaining;lr=job.getDouble("lr");}
            JSONArray data=root.getJSONArray("data");ArrayList<JSONObject> pool=new ArrayList<>();Set<String> seen=new HashSet<>(),reserved=new HashSet<>();
            for(String[] row:REFERENCE)reserved.add(row[0].isEmpty()?row[1].trim():row[0].trim().toLowerCase(Locale.ROOT));
            for(int i=0;i<data.length();i++){JSONObject item=data.getJSONObject(i);String k=key(item);seen.add(k);if(!reserved.contains(k))pool.add(item);}
            if(pool.isEmpty())throw new IOException("Corpus vacío");
            publish(m,done,total,start,"Entrenando",true,null);
            if(remote)try{push(root,m,job,"training",null,null,null);}catch(Exception ignored){}
            Random random=new Random();
            while(done<total&&!pause){
                if(safetyStop(start)){phase="Pausado por temperatura, batería o límite de sesión";break;}
                JSONObject item=pool.get(random.nextInt(pool.size()));boolean dialog=item.optString("kind").equals("dialog");
                NativeModel.Example ex=m.example(item.optString("q"),item.optString(dialog?"a":"text"),dialog,random);
                m.train(ex.ids,ex.targets,lr);done++;
                long now=SystemClock.elapsedRealtime();
                // State after every completed step; notification rate limited to about once a second.
                if(now-lastUi>=1000||done==1||done==total){publish(m,done,total,start,"Entrenando",true,null);lastUi=now;}
                else{try{JSONObject o=new JSONObject(state).put("done",done).put("step",m.step).put("optimizerSteps",m.optStep).put("loss",m.loss);state=o.toString();}catch(Exception ignored){}}
                if(done%25==0||now-lastSave>=30000){saveModel(root,m);lastSave=now;}
                if(remote&&(done==1||now-lastReport>=120000)){saveModel(root,m);lastSave=now;try{push(root,m,job,"training",null,null,null);}catch(Exception ignored){}lastReport=now;}
            }
            saveModel(root,m);
            if(remote&&!pause&&done==total){
                publish(m,done,total,start,"Evaluando respuestas",true,null);
                JSONArray results=new JSONArray(),tests=job.optJSONArray("tests");
                if(tests!=null)for(int i=0;i<tests.length()&&!pause;i++){String q=tests.getString(i);results.put(new JSONObject().put("q",q).put("a",m.reply(q,40)));}
                if(!pause){JSONObject eval=reference(m,seen);if(!pause){push(root,m,job,"completed",results,eval,null);root.put("lastNativeCompletion",new JSONObject().put("id",job.getString("id")).put("results",results).put("evaluation",eval));root.put("syncJob",JSONObject.NULL);saveModel(root,m);phase="Completado";}}
            }else if(!remote&&done==total&&!pause)phase="Completado";
            if(remote&&!phase.equals("Completado"))try{push(root,m,job,"paused",null,null,null);}catch(Exception e){error="No se pudo sincronizar la pausa: "+e.getMessage();}
        }catch(Throwable e){error=e.getMessage()==null?e.getClass().getSimpleName():e.getMessage();phase="Error de entrenamiento";if(loaded&&m!=null&&root!=null){try{saveModel(root,m);}catch(Exception ignored){}if(remote&&job!=null)try{push(root,m,job,"paused",null,null,error);}catch(Exception ignored){}}}
        finally{
            if(remote&&!phase.equals("Completado"))getSharedPreferences("origen_sync",MODE_PRIVATE).edit().putBoolean("auto_enabled",false).commit();
            publish(m,done,total,start,phase,false,error);finished=true;
            if(wake!=null&&wake.isHeld())wake.release();if(destroyed){active=false;}else{stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();}
        }
    }
    private String token()throws Exception{String val=getSharedPreferences("origen_sync",MODE_PRIVATE).getString("token","");if(val.isEmpty())throw new IOException("Conexión no configurada");KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);String[] p=val.split(":",2);Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,(javax.crypto.SecretKey)ks.getKey("origen_sync_v1",null),new GCMParameterSpec(128,android.util.Base64.decode(p[0],android.util.Base64.NO_WRAP)));return new String(c.doFinal(android.util.Base64.decode(p[1],android.util.Base64.NO_WRAP)),StandardCharsets.UTF_8);}
    private static final class Response{int code;String text;Response(int c,String t){code=c;text=t;}}
    private Response http(String repo,String token,String path,String method,String body)throws Exception{HttpURLConnection c=(HttpURLConnection)new URL("https://api.github.com/repos/"+repo+path).openConnection();try{c.setInstanceFollowRedirects(false);c.setConnectTimeout(12000);c.setReadTimeout(15000);c.setRequestMethod(method);c.setRequestProperty("Authorization","Bearer "+token);c.setRequestProperty("Accept","application/vnd.github+json");c.setRequestProperty("User-Agent","OrigenAI-Android");c.setRequestProperty("X-GitHub-Api-Version","2022-11-28");if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");try(OutputStream o=c.getOutputStream()){o.write(body.getBytes(StandardCharsets.UTF_8));}}int code=c.getResponseCode();ByteArrayOutputStream out=new ByteArrayOutputStream();InputStream in=code>=400?c.getErrorStream():c.getInputStream();if(in!=null)try(InputStream s=in){byte[] b=new byte[8192];int n;while((n=s.read(b))!=-1){if(out.size()+n>1500000)throw new IOException("Respuesta grande");out.write(b,0,n);}}return new Response(code,new String(out.toByteArray(),StandardCharsets.UTF_8));}finally{c.disconnect();}}
    private void push(JSONObject root,NativeModel m,JSONObject job,String status,JSONArray results,JSONObject evaluation,String error)throws Exception{
        String repo=job.getString("repo");if(!repo.matches("[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}")||!repo.equals(getSharedPreferences("origen_sync",MODE_PRIVATE).getString("repo","")))throw new IOException("Repositorio incorrecto");
        String tok=token();Response check=http(repo,tok,"","GET",null);if(check.code!=200||!new JSONObject(check.text).optBoolean("private"))throw new IOException("Repositorio privado no disponible");
        JSONArray ids=root.getJSONArray("syncApplied"),last=new JSONArray();for(int i=Math.max(0,ids.length()-100);i<ids.length();i++)last.put(ids.get(i));
        JSONObject s=new JSONObject().put("version",1).put("updatedAt",java.time.Instant.now().toString()).put("state",status).put("modelSteps",m.step).put("loss",m.loss==null?JSONObject.NULL:m.loss).put("exampleCount",root.getJSONArray("data").length()).put("parameters",m.count()).put("context",m.ctx).put("width",m.d).put("layers",m.layers).put("heads",m.heads).put("vocab",m.vocab).put("optimizerSteps",m.optStep).put("jobId",job.getString("id")).put("appliedIds",last).put("targetSteps",job.getLong("target"));
        if(results!=null)s.put("results",results);if(evaluation!=null)s.put("evaluation",evaluation);if(error!=null)s.put("error",error.substring(0,Math.min(300,error.length())));
        Response prev=http(repo,tok,"/contents/origen-status.json","GET",null);JSONObject body=new JSONObject().put("message","Origen AI: progreso de entrenamiento nativo").put("content",java.util.Base64.getEncoder().encodeToString(s.toString(2).getBytes(StandardCharsets.UTF_8)));if(prev.code==200)body.put("sha",new JSONObject(prev.text).getString("sha"));else if(prev.code!=404)throw new IOException("GitHub HTTP "+prev.code);
        Response result=http(repo,tok,"/contents/origen-status.json","PUT",body.toString());if(result.code!=200&&result.code!=201)throw new IOException("GitHub HTTP "+result.code);
    }
}
