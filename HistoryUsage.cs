using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
namespace CodexPet {
 public sealed class HistoryUsage : IDisposable {
  readonly object gate=new object();readonly JavaScriptSerializer json=new JavaScriptSerializer{MaxJsonLength=int.MaxValue};
  readonly string home,cache,priceHash;readonly ModelUsage owner;readonly Dictionary<string,Cursor> cursors=new Dictionary<string,Cursor>(StringComparer.OrdinalIgnoreCase);
  Thread thread;volatile bool stopped;string result="{}";int scanned,sources;bool loading=true;
  sealed class Cursor {public string Id,Path,Error="";public long Offset,Length,WriteTicks;public ModelUsage.Ledger Ledger;}
  public HistoryUsage(string codexHome,string pricePath,string cachePath) {home=System.IO.Path.GetFullPath(codexHome);cache=cachePath;owner=new ModelUsage(pricePath);using(var hash=SHA256.Create())priceHash=Convert.ToBase64String(hash.ComputeHash(File.ReadAllBytes(pricePath)));Load();Publish();}
  static Dictionary<string,object> D(object o){return o as Dictionary<string,object>??new Dictionary<string,object>();}
  static object V(Dictionary<string,object> d,string k){object v;return d.TryGetValue(k,out v)?v:null;}
  static long N(Dictionary<string,object> d,string k){try{return Convert.ToInt64(V(d,k));}catch{return 0;}}
  static string S(Dictionary<string,object> d,string k){return Convert.ToString(V(d,k));}
  static IEnumerable<object> A(object value){var a=value as System.Collections.IEnumerable;if(a==null||value is string)yield break;foreach(object x in a)yield return x;}
  public void Start(){thread=new Thread(Loop);thread.IsBackground=true;thread.Priority=ThreadPriority.BelowNormal;thread.Start();}
  public string Snapshot(){lock(gate)return result;}
  public void Dispose(){stopped=true;if(thread!=null)thread.Join(2000);owner.Dispose();}
  void Load(){
   if(!File.Exists(cache))return;
   try {var saved=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(cache));if(N(saved,"Version")!=4||S(saved,"Home")!=home||S(saved,"Prices")!=priceHash)return;
    foreach(var raw in A(V(saved,"Files"))){var d=D(raw);string id=S(d,"Id");var c=new Cursor{Id=id,Path=S(d,"Path"),Offset=N(d,"Offset"),Length=N(d,"Length"),WriteTicks=N(d,"WriteTicks"),Ledger=new ModelUsage.Ledger(owner,id)};c.Ledger.Restore(D(V(d,"Ledger")));cursors[c.Id]=c;}
   }catch{cursors.Clear();}
  }
  void Save(){
   var rows=new List<Dictionary<string,object>>();foreach(var c in cursors.Values)rows.Add(new Dictionary<string,object>{{"Id",c.Id},{"Path",c.Path},{"Offset",c.Offset},{"Length",c.Length},{"WriteTicks",c.WriteTicks},{"Ledger",c.Ledger.State()}});
   var value=new Dictionary<string,object>{{"Version",4},{"Home",home},{"Prices",priceHash},{"Files",rows}};
   Directory.CreateDirectory(System.IO.Path.GetDirectoryName(cache));string temp=cache+".tmp";File.WriteAllText(temp,json.Serialize(value),Encoding.UTF8);
   if(File.Exists(cache))File.Replace(temp,cache,null);else File.Move(temp,cache);
  }
  List<Cursor> Discover(){
   var paths=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   try {var rows=json.Deserialize<object[]>(SessionCatalog.ReadAll(home));foreach(var raw in rows){var d=D(raw);paths[S(d,"Id")]=S(d,"FullName");}}catch{}
   foreach(string folder in new string[]{"sessions","archived_sessions"}) {
    string root=System.IO.Path.Combine(home,folder);if(!Directory.Exists(root))continue;
    foreach(string path in Directory.EnumerateFiles(root,"*.jsonl",SearchOption.AllDirectories)) {
     var id=Regex.Match(System.IO.Path.GetFileNameWithoutExtension(path),"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",RegexOptions.IgnoreCase);
     string key=id.Success?id.Value:path;string known;if(!paths.TryGetValue(key,out known)||!File.Exists(known))paths[key]=path;
    }
   }
   foreach(var pair in paths){Cursor c;if(!cursors.TryGetValue(pair.Key,out c)){c=new Cursor{Id=pair.Key,Ledger=new ModelUsage.Ledger(owner,pair.Key)};cursors[pair.Key]=c;}c.Path=pair.Value;}
   return cursors.Values.OrderByDescending(c=>{try{return File.GetLastWriteTimeUtc(c.Path);}catch{return DateTime.MinValue;}}).ToList();
  }
  bool Scan(Cursor c){
   try {
    var info=new FileInfo(c.Path);if(!info.Exists){c.Error="missing";return false;}
    if(info.Length==c.Length&&info.LastWriteTimeUtc.Ticks==c.WriteTicks){c.Error="";return false;}
    if(info.Length<c.Offset || (info.Length==c.Length&&c.WriteTicks!=0&&info.LastWriteTimeUtc.Ticks!=c.WriteTicks)) {c.Offset=0;c.Ledger=new ModelUsage.Ledger(owner,c.Id);}
    long committed=c.Offset;byte[] buffer=new byte[65536];
    using(var stream=new FileStream(c.Path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var line=new MemoryStream()){
     stream.Position=c.Offset;int count;
     while(!stopped&&(count=stream.Read(buffer,0,buffer.Length))>0){
      long startOffset=stream.Position-count;int start=0,end;
      while((end=Array.IndexOf(buffer,(byte)10,start,count-start))>=0){
       line.Write(buffer,start,end-start);c.Ledger.Apply(Encoding.UTF8.GetString(line.GetBuffer(),0,(int)line.Length).TrimEnd('\r'));line.SetLength(0);committed=startOffset+end+1;start=end+1;
      }
      line.Write(buffer,start,count-start);
     }
    }
    c.Offset=committed;c.Length=stopped?0:info.Length;c.WriteTicks=stopped?0:info.LastWriteTimeUtc.Ticks;c.Error="";return true;
   }catch(Exception e){c.Error=e.GetType().Name;return false;}
  }
  void Publish(){
   var models=new Dictionary<string,Dictionary<string,object>>();int missing=0,errors=0;
   foreach(var cursor in cursors.Values){if(cursor.Error=="missing")missing++;else if(cursor.Error!="")errors++;errors+=cursor.Ledger.Errors;
    var state=cursor.Ledger.State();var rows=V(state,"Models") as IEnumerable<Dictionary<string,object>>;if(rows==null)continue;
    foreach(var r in rows){string model=S(r,"Model");Dictionary<string,object> total;
     if(!models.TryGetValue(model,out total)){total=new Dictionary<string,object>{{"Model",model},{"Input",0L},{"Cached",0L},{"Writes",0L},{"Output",0L},{"Total",0L},{"Cost",0.0},{"Priced",true}};models[model]=total;}
     foreach(string key in new string[]{"Input","Cached","Writes","Output","Total"})total[key]=N(total,key)+N(r,key);
     total["Cost"]=Convert.ToDouble(total["Cost"])+Convert.ToDouble(r["Cost"]);total["Priced"]=Convert.ToBoolean(total["Priced"])&&Convert.ToBoolean(r["Priced"]);
    }
   }
   var output=new Dictionary<string,object>{{"Models",models.Values.ToArray()},{"Total",models.Values.Sum(x=>N(x,"Total"))},{"Cost",models.Values.Sum(x=>Convert.ToDouble(x["Cost"]))},{"Priced",models.Values.All(x=>Convert.ToBoolean(x["Priced"]))},{"Loading",loading},{"Scanned",scanned},{"Sources",Math.Max(sources,cursors.Count)},{"Missing",missing},{"Errors",errors},{"Scope","local-history"}};
   lock(gate)result=json.Serialize(output);
  }
  public void ScanOnce(){var list=Discover();sources=list.Count;scanned=0;foreach(var c in list){Scan(c);scanned++;}loading=false;Publish();Save();}
  void Loop(){
   try {while(!stopped){var list=Discover();sources=list.Count;scanned=0;loading=true;Publish();DateTime checkpoint=DateTime.UtcNow;bool dirty=false;
    foreach(var c in list){if(stopped)break;dirty=Scan(c)||dirty;scanned++;if(scanned%25==0||(DateTime.UtcNow-checkpoint).TotalSeconds>3){Publish();if(dirty){Save();dirty=false;}checkpoint=DateTime.UtcNow;}}
    loading=scanned<sources;Publish();if(dirty)Save();for(int i=0;i<30&&!stopped;i++)Thread.Sleep(1000);
   }}catch(Exception e){lock(gate)result=json.Serialize(new Dictionary<string,object>{{"Error",e.Message},{"Scope","local-history"}});}
  }
 }
}
