using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace CodexPet {
 public sealed class ModelUsage : IDisposable {
  readonly object gate=new object();
  readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=int.MaxValue };
  readonly Dictionary<string, object> prices;
  Thread thread; volatile bool stopped; string requested="", result="{}";
  public ModelUsage(string pricePath) { prices=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(pricePath)); }
  public void Start() {thread=new Thread(Loop); thread.IsBackground=true; thread.Start();}
  public void Follow(string path) {lock(gate) requested=path;}
  public string Snapshot() {lock(gate) return result;}
  public void Dispose() {stopped=true; if(thread!=null) thread.Join(1500);}
  static Dictionary<string,object> D(object o) {return o as Dictionary<string,object> ?? new Dictionary<string,object>();}
  static object V(Dictionary<string,object> d,string k) {object v; return d.TryGetValue(k,out v)?v:null;}
  static long N(Dictionary<string,object> d,string k) {try {return Convert.ToInt64(V(d,k));} catch {return 0;}}
  static double F(Dictionary<string,object> d,string k) {try {return Convert.ToDouble(V(d,k));} catch {return 0;}}
  static string S(Dictionary<string,object> d,string k) {return Convert.ToString(V(d,k));}
  static IEnumerable<object> A(object value) {var a=value as System.Collections.IEnumerable;if(a==null||value is string)yield break;foreach(object x in a)yield return x;}
  public sealed class Usage {
   public string Model; public long Input,Cached,Writes,Output,Total; public double Cost; public bool Priced=true;
   public Dictionary<string,object> Export() {return new Dictionary<string,object>{{"Model",Model},{"Input",Input},{"Cached",Cached},{"Writes",Writes},{"Output",Output},{"Total",Total},{"Cost",Cost},{"Priced",Priced}};}
  }
  public sealed class Ledger {
   readonly ModelUsage owner;readonly string expectedId;
   readonly Dictionary<string,Usage> models=new Dictionary<string,Usage>();
   long[] previous=new long[5];
   string model="未识别模型",tier="standard"; long context,window; public int Errors;
   bool forked, inheritedTask; double createdSeconds, taskStartedSeconds,taskDurationMs;long taskOutput;string taskId="";bool taskRunning;
   public Ledger(ModelUsage o,string sessionId="") {owner=o;expectedId=sessionId;}
   static double Stamp(object value,string fallback) {
    double n;if(value!=null && double.TryParse(Convert.ToString(value),out n))return n>100000000000?n/1000:n;
    DateTimeOffset date;if(DateTimeOffset.TryParse(Convert.ToString(value),out date)||DateTimeOffset.TryParse(fallback,out date))return (date.ToUniversalTime()-new DateTimeOffset(1970,1,1,0,0,0,TimeSpan.Zero)).TotalSeconds;
    return 0;
   }
   public void Apply(string line) {
    var types=Regex.Matches(line.Substring(0,Math.Min(line.Length,512)),"\"type\"\\s*:\\s*\"([^\"]+)\"");
    if(types.Count==0)return;string rootType="",eventType="";
    foreach(Match match in types){string t=match.Groups[1].Value;if(rootType==""&&(t=="turn_context"||t=="event_msg"||t=="session_meta"))rootType=t;if(t=="token_count"||t=="task_started"||t=="task_complete"||t=="turn_aborted")eventType=t;}
    if(rootType==""||(rootType=="event_msg"&&eventType==""))return;
    Dictionary<string,object> record;
    try {record=owner.json.Deserialize<Dictionary<string,object>>(line);} catch {Errors++; return;}
    rootType=S(record,"type");
    var p=D(V(record,"payload"));
    string timestamp=S(record,"timestamp");
    if(rootType=="session_meta") {forked=S(p,"forked_from_id")!=""||(expectedId!=""&&S(p,"id")!=""&&S(p,"id")!=expectedId);createdSeconds=Math.Floor(Stamp(V(p,"timestamp"),timestamp));inheritedTask=forked;return;}
    if(S(record,"type")=="turn_context") {
     if(S(p,"model")!="") model=S(p,"model");
     tier=S(p,"service_tier"); if(tier=="") tier="standard";
     return;
    }
    string kind=S(p,"type");
    if(kind=="task_started") {
     double start=Stamp(V(p,"started_at"),timestamp);inheritedTask=forked&&start<createdSeconds;
     if(!inheritedTask){taskId=S(p,"turn_id");taskStartedSeconds=start;taskOutput=0;taskDurationMs=0;taskRunning=true;}
     return;
    }
    if(kind=="task_complete"||kind=="turn_aborted") {
     if(!inheritedTask&&(taskId==""||S(p,"turn_id")==taskId||S(p,"turn_id")=="")){taskRunning=false;taskDurationMs=F(p,"duration_ms");if(taskDurationMs<=0)taskDurationMs=Math.Max(0,(Stamp(V(p,"completed_at"),timestamp)-taskStartedSeconds)*1000);}
     return;
    }
    if(kind!="token_count") return;
    var info=D(V(p,"info")); if(info.Count==0) return;
    var totals=D(V(info,"total_token_usage")); if(totals.Count==0) return;
    var last=D(V(info,"last_token_usage"));
    context=N(last,"total_tokens"); window=N(info,"model_context_window");
    long[] now={N(totals,"input_tokens"),N(totals,"cached_input_tokens"),N(totals,"cache_write_input_tokens"),N(totals,"output_tokens"),N(totals,"total_tokens")};
    long[] delta=new long[5]; bool reset=now[4]<previous[4];
    for(int i=0;i<5;i++) delta[i]=Math.Max(0,now[i]-(reset?0:previous[i]));
    previous=now;
    if(inheritedTask)return; // Forked logs replay old tasks with rewritten outer timestamps.
    if(delta[4]==0) return; // Repeated cumulative snapshots must not be counted twice.
    if(taskRunning)taskOutput+=delta[3];
    Usage u; if(!models.TryGetValue(model,out u)) {u=new Usage {Model=model}; models[model]=u;}
    u.Input+=delta[0];u.Cached+=delta[1];u.Writes+=delta[2];u.Output+=delta[3];u.Total+=delta[4];
    object priceObj;
    if(!owner.prices.TryGetValue(model,out priceObj)) {u.Priced=false;return;}
    var rate=D(priceObj);
    if(tier!="standard" && tier!="default" && tier!="auto" && tier!="priority" && tier!="fast" && tier!="batch" && tier!="flex") {u.Priced=false; return;}
    double factor=(tier=="priority" || tier=="fast")?2:((tier=="batch" || tier=="flex")?.5:1);
    bool longContext=N(last,"input_tokens")>272000 && F(rate,"longInputFactor")>0;
    double inf=longContext?F(rate,"longInputFactor"):1, outf=longContext?1.5:1;
    long uncached=Math.Max(0,delta[0]-delta[1]-delta[2]);
    u.Cost+=factor*(inf*(uncached*F(rate,"input")+delta[1]*F(rate,"cached")+delta[2]*F(rate,"write"))+outf*delta[3]*F(rate,"output"))/1000000.0;
   }
   public string Export(string path,bool loading) {
    var rows=new List<Dictionary<string,object>>();long total=0;double cost=0;bool priced=true;
    foreach(var u in models.Values) {rows.Add(u.Export()); total+=u.Total; cost+=u.Cost; priced &= u.Priced;}
    double elapsed=taskRunning?Math.Max(0,Stamp(DateTimeOffset.UtcNow.ToString("o"),"")-taskStartedSeconds):taskDurationMs/1000;
    return owner.json.Serialize(new Dictionary<string,object>{{"Path",path},{"Model",model},{"Models",rows},{"Total",total},{"Cost",cost},{"Priced",priced},{"Context",context},{"Window",window},{"Loading",loading},{"Errors",Errors},{"TaskOutput",taskOutput},{"TaskSeconds",elapsed},{"TaskTps",taskStartedSeconds>0&&elapsed>0?(object)(taskOutput/elapsed):null},{"TaskRunning",taskRunning}});
   }
   public Dictionary<string,object> State() {
    var rows=new List<Dictionary<string,object>>();foreach(var u in models.Values)rows.Add(u.Export());
    return new Dictionary<string,object>{{"Models",rows},{"Previous",previous},{"Model",model},{"Tier",tier},{"Context",context},{"Window",window},{"Errors",Errors},{"Forked",forked},{"Inherited",inheritedTask},{"Created",createdSeconds}};
   }
   public void Restore(Dictionary<string,object> state) {
    foreach(var raw in A(V(state,"Models"))){var r=D(raw);var u=new Usage{Model=S(r,"Model"),Input=N(r,"Input"),Cached=N(r,"Cached"),Writes=N(r,"Writes"),Output=N(r,"Output"),Total=N(r,"Total"),Cost=F(r,"Cost"),Priced=Convert.ToBoolean(V(r,"Priced"))};models[u.Model]=u;}
    var prev=new List<object>(A(V(state,"Previous")));if(prev.Count==5)for(int i=0;i<5;i++)previous[i]=Convert.ToInt64(prev[i]);
    model=S(state,"Model");tier=S(state,"Tier");context=N(state,"Context");window=N(state,"Window");Errors=(int)N(state,"Errors");forked=Convert.ToBoolean(V(state,"Forked"));inheritedTask=Convert.ToBoolean(V(state,"Inherited"));createdSeconds=F(state,"Created");
   }
  }
  // Public synchronous adapter is used only by bounded fixture tests.
  public string ParseFixture(string path) {var l=new Ledger(this);foreach(var line in File.ReadLines(path)) l.Apply(line);return l.Export(path,false);}
  void Publish(Ledger ledger,string path,bool loading) {var snapshot=ledger.Export(path,loading);lock(gate)result=snapshot;}
  void Loop() {
   string active="";Ledger ledger=null;StreamReader reader=null;StringBuilder partial=new StringBuilder();long length=0;
   char[] buffer=new char[65536];
   try {
    while(!stopped) {
     string path;lock(gate)path=requested;
     if(path=="" || !File.Exists(path)) {Thread.Sleep(200);continue;}
     if(path!=active || new FileInfo(path).Length<length) {
      if(reader!=null)reader.Dispose();
      var id=Regex.Match(Path.GetFileNameWithoutExtension(path),"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",RegexOptions.IgnoreCase);
      active=path;ledger=new Ledger(this,id.Success?id.Value:"");partial.Clear();length=0;
      reader=new StreamReader(new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete),Encoding.UTF8,true,65536);
     }
     int count=reader.Read(buffer,0,buffer.Length);
     if(count>0) {
      partial.Append(buffer,0,count);
      string chunk=partial.ToString();int start=0,index;
      while((index=chunk.IndexOf('\n',start))>=0) {ledger.Apply(chunk.Substring(start,index-start));start=index+1;}
      partial.Clear();partial.Append(chunk,start,chunk.Length-start);
      length=reader.BaseStream.Position;
      Publish(ledger,active,!reader.EndOfStream);
     } else {Publish(ledger,active,false);Thread.Sleep(500);}
    }
   } catch(Exception ex) {lock(gate) result=json.Serialize(new Dictionary<string,object>{{"Path",active},{"Error",ex.Message}});}
   finally {if(reader!=null)reader.Dispose();}
  }
 }
}
