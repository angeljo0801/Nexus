package com.origenai.local;
import java.util.*;
public final class NativeModelTest {
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    public static void main(String[] args){
        NativeModel m=new NativeModel(48,64,new int[0][],true);
        Random r=new Random(42);
        for(Map.Entry<String,float[]> entry:m.p.entrySet()){
            float[] a=entry.getValue();for(int i=0;i<a.length;i++)a[i]=entry.getKey().endsWith("g1")||entry.getKey().endsWith("g2")?1f:(float)(r.nextGaussian()*.015);
        }
        int[] encoded=m.encode("¡Hola, español!");ArrayList<Integer> list=new ArrayList<>();for(int x:encoded)list.add(x);
        check(m.decode(list).equals("¡Hola, español!"),"BPE round trip");
        NativeModel.Example e=m.example("Hola","Hola, ¿cómo estás?",true,r);
        double[] initial=m.referenceLoss(e);float[] before=m.p.get("L1_O").clone();
        for(int i=0;i<12;i++)m.train(e.ids,e.targets,.001);
        double[] end=m.referenceLoss(e);
        check(m.step==12&&m.optStep==12,"Adam step");
        check(end[0]/end[1]<initial[0]/initial[1],"loss must improve");
        check(!Arrays.equals(before,m.p.get("L1_O")),"deep weights must train");
        float[] restored=new float[m.p.get("W").length];NativeModel.unpack(NativeModel.pack(m.p.get("W")),restored);
        check(Arrays.equals(restored,m.p.get("W")),"checkpoint float format");
        check(new NativeModel(256,128,new int[0][],false).count()==885376,"legacy architecture");
        check(new NativeModel(256,128,new int[0][],true).count()==1934976,"deep architecture");
        System.out.println("Native model OK: loss "+initial[0]/initial[1]+" -> "+end[0]/end[1]+", steps "+m.step);
    }
}
