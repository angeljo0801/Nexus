#include <jni.h>
#include "llama.h"
#include <atomic>
#include <mutex>
#include <string>
#include <vector>
#include <algorithm>

namespace {
std::mutex lock; std::atomic<bool> stop{false};
llama_model *model=nullptr; llama_context *ctx=nullptr; std::string filename;
bool initialized=false;
std::string str(JNIEnv *e,jstring j){if(!j)return {};const char*p=e->GetStringUTFChars(j,nullptr);if(!p)return {};std::string s(p);e->ReleaseStringUTFChars(j,p);return s;}
void err(JNIEnv *e,const char*s){jclass c=e->FindClass("java/lang/IllegalStateException");if(c)e->ThrowNew(c,s);}
void unload(){if(ctx){llama_free(ctx);ctx=nullptr;}if(model){llama_model_free(model);model=nullptr;}filename.clear();}
void fill(llama_batch_ext*b,const llama_token*t,int n,int pos){llama_batch_ext_clear(b);for(int i=0;i<n;++i){int idx=llama_batch_ext_add_token(b,0,t[i]);llama_pos p=pos+i;llama_batch_ext_set_pos(b,idx,&p);}llama_batch_ext_set_output_logits(b,n-1,true);}
}
extern "C" JNIEXPORT jstring JNICALL Java_com_origenai_local_LocalLlama_nativeLoad(JNIEnv*e,jclass,jstring path,jint nctx){
 std::lock_guard<std::mutex>g(lock);std::string file=str(e,path);
 if(file.empty()||nctx<512||nctx>4096){err(e,"Ruta o contexto inválido");return nullptr;}
 if(model&&filename==file)return e->NewStringUTF("Modelo listo");
 stop.store(true);unload();
 if(!initialized){llama_backend_init();initialized=true;}
 auto mp=llama_model_default_params();mp.n_gpu_layers=0;
 model=llama_model_load_from_file(file.c_str(),mp);
 if(!model){err(e,"No se pudo abrir el GGUF; revisa memoria y descarga");return nullptr;}
 auto cp=llama_context_default_params();cp.n_ctx=nctx;cp.n_batch=512;cp.n_ubatch=128;cp.n_threads=4;cp.n_threads_batch=4;
 ctx=llama_init_from_model(model,cp);if(!ctx){unload();err(e,"Memoria insuficiente para inicializar GGUF");return nullptr;}
 filename=file;stop.store(false);return e->NewStringUTF("Motor GGUF cargado en Android");
}
extern "C" JNIEXPORT jstring JNICALL Java_com_origenai_local_LocalLlama_nativeGenerate(JNIEnv*e,jclass,jobjectArray roles,jobjectArray contents,jint maxout){
 std::lock_guard<std::mutex>g(lock);
 if(!model||!ctx){err(e,"Primero carga un modelo local");return nullptr;}
 if(!roles||!contents||maxout<1||maxout>512){err(e,"Mensajes inválidos");return nullptr;}
 int count=e->GetArrayLength(roles);
 if(count<1||count>16||e->GetArrayLength(contents)!=count){err(e,"Conversación demasiado larga");return nullptr;}
 std::vector<std::string> r,c; r.reserve(count);c.reserve(count);
 for(int i=0;i<count;++i){auto a=(jstring)e->GetObjectArrayElement(roles,i);auto b=(jstring)e->GetObjectArrayElement(contents,i);r.push_back(str(e,a));c.push_back(str(e,b));e->DeleteLocalRef(a);e->DeleteLocalRef(b);if((r.back()!="user"&&r.back()!="assistant"&&r.back()!="system")||c.back().size()>3500){err(e,"Mensaje inválido");return nullptr;}}
 std::vector<llama_chat_message> messages;
 for(int i=0;i<count;++i)messages.push_back({r[i].c_str(),c[i].c_str()});
 const char*templ=llama_model_chat_template(model,nullptr);
 if(!templ){err(e,"El GGUF no incluye plantilla de chat");return nullptr;}
 int need=llama_chat_apply_template(templ,messages.data(),count,true,nullptr,0);
 if(need<=0||need>25000){err(e,"Plantilla de conversación inválida");return nullptr;}
 std::vector<char> formatted(need+1,0);
 int bytes=llama_chat_apply_template(templ,messages.data(),count,true,formatted.data(),formatted.size());
 if(bytes<=0){err(e,"No se pudo formatear el diálogo");return nullptr;}
 auto*vocab=llama_model_get_vocab(model);
 int total=-llama_tokenize(vocab,formatted.data(),bytes,nullptr,0,true,true);
 if(total<=0||total+maxout+1>(int)llama_n_ctx(ctx)){err(e,"Se agotó el contexto; limpia el chat");return nullptr;}
 std::vector<llama_token>tokens(total);
 int ntok=llama_tokenize(vocab,formatted.data(),bytes,tokens.data(),tokens.size(),true,true);
 if(ntok<=0){err(e,"Error de tokenización");return nullptr;}
 llama_memory_clear(llama_get_memory(ctx),true);
 stop.store(false);
 auto*sampler=llama_sampler_chain_init(llama_sampler_chain_default_params());
 llama_sampler_chain_add(sampler,llama_sampler_init_top_k(24));
 llama_sampler_chain_add(sampler,llama_sampler_init_top_p(0.85f,1));
 llama_sampler_chain_add(sampler,llama_sampler_init_temp(0.45f));
 llama_sampler_chain_add(sampler,llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
 auto*batch=llama_batch_ext_init(ctx);std::string result;bool failure=false;int pos=0;
 for(int i=0;i<ntok&&!stop.load();){int n=std::min(256,ntok-i);fill(batch,tokens.data()+i,n,pos);if(llama_process(ctx,LLAMA_PROCESS_TYPE_DECODE,batch)!=0){failure=true;break;}i+=n;pos+=n;}
 if(!failure){for(int i=0;i<maxout&&!stop.load();++i){llama_token t=llama_sampler_sample(sampler,ctx,-1);if(llama_vocab_is_eog(vocab,t))break;std::vector<char>piece(256);int n=llama_token_to_piece(vocab,t,piece.data(),piece.size(),0,true);if(n<0){piece.resize(-n+1);n=llama_token_to_piece(vocab,t,piece.data(),piece.size(),0,true);}if(n>0)result.append(piece.data(),n);fill(batch,&t,1,pos++);if(llama_process(ctx,LLAMA_PROCESS_TYPE_DECODE,batch)!=0){failure=true;break;}}}
 llama_batch_ext_free(batch);llama_sampler_free(sampler);
 if(failure){err(e,"Falló la inferencia neuronal");return nullptr;}
 if(stop.load()){err(e,"Generación detenida");return nullptr;}
 if(result.empty()){err(e,"El modelo no produjo texto");return nullptr;}
 // Construct Java UTF-8 String without JNI modified-UTF-8 corruption.
 jbyteArray data=e->NewByteArray(result.size());e->SetByteArrayRegion(data,0,result.size(),(const jbyte*)result.data());
 jclass stdc=e->FindClass("java/nio/charset/StandardCharsets");jfieldID utf=e->GetStaticFieldID(stdc,"UTF_8","Ljava/nio/charset/Charset;");
 jobject charset=e->GetStaticObjectField(stdc,utf);jclass stringClass=e->FindClass("java/lang/String");
 jmethodID ctor=e->GetMethodID(stringClass,"<init>","([BLjava/nio/charset/Charset;)V");
 return (jstring)e->NewObject(stringClass,ctor,data,charset);
}
extern "C" JNIEXPORT void JNICALL Java_com_origenai_local_LocalLlama_nativeStop(JNIEnv*,jclass){stop.store(true);}
extern "C" JNIEXPORT void JNICALL Java_com_origenai_local_LocalLlama_nativeUnload(JNIEnv*,jclass){stop.store(true);std::lock_guard<std::mutex>g(lock);unload();}
