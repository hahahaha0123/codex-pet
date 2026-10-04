using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
namespace CodexPet {
 public static class SessionCatalog {
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] name,out IntPtr db,int flags,IntPtr vfs);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db,byte[] sql,int len,out IntPtr stmt,IntPtr tail);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt,int col);
  [DllImport("winsqlite3",CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt,int col);
  static byte[] Z(string s) {return Encoding.UTF8.GetBytes(s+"\0");}
  static string Text(IntPtr stmt,int col) {int len=sqlite3_column_bytes(stmt,col);byte[] b=new byte[len];if(len>0)Marshal.Copy(sqlite3_column_text(stmt,col),b,0,len);return Encoding.UTF8.GetString(b);}
  static string PathName(string p) {return p.StartsWith(@"\\?\")?p.Substring(4):p;}
  static Dictionary<string,object> D(object value) {return value as Dictionary<string,object> ?? new Dictionary<string,object>();}
  static object V(Dictionary<string,object> d,string key) {object v;return d.TryGetValue(key,out v)?v:null;}
  static string S(Dictionary<string,object> d,string key) {return Convert.ToString(V(d,key));}
  static IEnumerable<object> A(object value) {var a=value as System.Collections.IEnumerable;if(a==null||value is string)yield break;foreach(object x in a)yield return x;}
  static Dictionary<string,object> ProjectState(string home) {
   try {return new JavaScriptSerializer {MaxJsonLength=int.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(home,".codex-global-state.json")));} catch {return new Dictionary<string,object>();}
  }
  public static string ProjectName(string home,string threadId,string cwd) {return ResolveProject(ProjectState(home),threadId,cwd)[0];}
  static string[] ResolveProject(Dictionary<string,object> state,string id,string cwd) {
   var projects=D(V(state,"local-projects"));var assignment=D(V(D(V(state,"thread-project-assignments")),id));
   string projectId=S(assignment,"projectId");var chosen=D(V(projects,projectId));string matchedRoot="";
   if(chosen.Count==0) {
    int longest=-1;
    foreach(var candidate in projects.Values) {
     var p=D(candidate);var roots=A(V(p,"rootPaths"));
     foreach(var raw in roots) {string root=PathName(Convert.ToString(raw)).TrimEnd('\\');string path=PathName(cwd).TrimEnd('\\');
      if((path.Equals(root,StringComparison.OrdinalIgnoreCase)||path.StartsWith(root+"\\",StringComparison.OrdinalIgnoreCase))&&root.Length>longest){chosen=p;matchedRoot=root;longest=root.Length;}
     }
    }
   }
   if(matchedRoot==""){foreach(var root in A(V(chosen,"rootPaths"))){matchedRoot=PathName(Convert.ToString(root));break;}}
   string name=S(chosen,"name");if(name=="")name=Path.GetFileName(PathName(cwd).TrimEnd('\\'));
   return new string[]{name,matchedRoot};
  }
  public static string Read(string home) {return ReadRows(home,false);}
  public static string ReadAll(string home) {return ReadRows(home,true);}
  static string ReadRows(string home,bool all) {
   var rows=new List<Dictionary<string,object>>();IntPtr db=IntPtr.Zero,stmt=IntPtr.Zero;
   var state=all?new Dictionary<string,object>():ProjectState(home);
   string[] paths=Directory.GetFiles(home,"state_*.sqlite");Array.Sort(paths);if(paths.Length==0)return "[]";
   try {
    if(sqlite3_open_v2(Z(paths[paths.Length-1]),out db,1,IntPtr.Zero)!=0)throw new IOException("Cannot open Codex catalog read-only");
    string sql="SELECT id,title,cwd,rollout_path,model FROM threads "+(all?"":"WHERE archived=0 ")+"ORDER BY updated_at DESC"+(all?"":" LIMIT 40");
    if(sqlite3_prepare_v2(db,Z(sql),-1,out stmt,IntPtr.Zero)!=0)throw new IOException("Cannot read Codex catalog");
    while(sqlite3_step(stmt)==100) {
     string path=PathName(Text(stmt,3));if(!all&&!File.Exists(path))continue;
     string id=Text(stmt,0),cwd=PathName(Text(stmt,2));var project=ResolveProject(state,id,cwd);
     rows.Add(new Dictionary<string,object>{{"Id",id},{"Title",Text(stmt,1)},{"Cwd",cwd},{"FullName",path},{"BaseName",Path.GetFileNameWithoutExtension(path)},{"Model",Text(stmt,4)},{"ProjectName",project[0]},{"ProjectRoot",project[1]}});
    }
    return new JavaScriptSerializer {MaxJsonLength=int.MaxValue}.Serialize(rows);
   } finally {if(stmt!=IntPtr.Zero)sqlite3_finalize(stmt);if(db!=IntPtr.Zero)sqlite3_close(db);}
  }
 }
}
