"""Execute production Kotlin repo managers with in-memory Android/HTTP/host doubles.
No APK deployment, Android data, remote requests, or production file mutations.
"""
from pathlib import Path
import glob,os,subprocess,tempfile
root=Path(__file__).resolve().parents[5]
native=root/'android/app/src/main/kotlin/com/soplay/sozo'
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(group,name,version):
 return next(p for p in (cache/group/name/version).glob('*/*.jar') if not p.name.endswith(('-sources.jar','-javadoc.jar')))
stdlib=jar('org.jetbrains.kotlin','kotlin-stdlib','2.2.20')
compiler=[jar('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.2.20'),stdlib,jar('org.jetbrains.kotlin','kotlin-script-runtime','2.2.20'),jar('org.jetbrains.kotlin','kotlin-reflect','1.6.10'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.0'),jar('org.jetbrains','annotations','13.0')]
json=jar('org.json','json','20251224')
java=Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java')
with tempfile.TemporaryDirectory(prefix='sozo-native-regression-') as tmp:
 d=Path(tmp)
 files={
 'Context.kt':'''package android.content
open class Context { companion object { const val MODE_PRIVATE=0 }; private val stores=HashMap<String,SharedPreferences>(); fun getSharedPreferences(n:String,m:Int)=stores.getOrPut(n){SharedPreferences()} }
class SharedPreferences { private val data=HashMap<String,String>(); fun getString(k:String,d:String?)=data[k]?:d; fun edit()=Editor(); inner class Editor { fun putString(k:String,v:String):Editor {data[k]=v;return this}; fun apply(){} } }
''',
 'Log.kt':'''package android.util
object Log { fun e(t:String,m:String)=0; fun i(t:String,m:String)=0 }
''',
 'Index.kt':'''package com.soplay.sozo.extensions
import org.json.JSONArray
object ExtensionIndex { var data=JSONArray(); var fail=false; fun fetch(u:String):JSONArray { if(fail)throw IllegalStateException("offline");return data }; fun parseFile(u:String)=fetch(u) }
''',
 }
 for family,cls in [('manga','Manga'),('aniyomi','Aniyomi')]:
  files[cls+'Host.kt']=f'''package com.soplay.sozo.{family}
import org.json.JSONObject
class {cls}Host {{ var refreshMissingApk: ((String)->Unit)?=null; val rows=HashMap<String,JSONObject>(); fun registerMeta(e:JSONObject,n:String){{rows[e.getString("id")]=e}}; fun removeSources(ids:List<String>){{ids.forEach{{rows.remove(it)}}}}; fun dropCachedApk(url:String){{}} }}
'''
 files['Main.kt']='''import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import com.soplay.sozo.extensions.ExtensionIndex
import com.soplay.sozo.manga.*
import com.soplay.sozo.aniyomi.*
fun fixture(url:String,vararg ids:String)=JSONArray().put(JSONObject().put("pkg","fixture.extension").put("name","Fixture").put("apkUrl",url).put("sources",JSONArray(ids.map{JSONObject().put("id",it).put("name","FixtureSource").put("lang","en")})))
fun main(){
 for(anime in listOf(false,true)) {
  val context=Context();val mh=MangaHost();val ah=AniyomiHost();val mm=MangaRepoManager(context,mh);val am=AniyomiRepoManager(context,ah)
  val repo="https://fixture/index.pb"
  fun add(){if(anime)am.addRepo(repo)else mm.addRepo(repo)}
  fun update(){if(anime)am.checkUpdates()else mm.checkUpdates()}
  ExtensionIndex.fail=false;ExtensionIndex.data=fixture("https://fixture/old.apk","original");add()
  val prefs=context.getSharedPreferences(if(anime)"aniyomi" else "manga",0);val before=prefs.getString("meta",null)
  ExtensionIndex.fail=true;check(runCatching{add()}.isFailure);check(prefs.getString("meta",null)==before)
  ExtensionIndex.fail=false;ExtensionIndex.data=JSONArray();check(runCatching{add()}.isFailure);check(prefs.getString("meta",null)==before)
  ExtensionIndex.data=fixture("https://fixture/new.apk","original","new-language");update()
  val loadedM=MangaHost();val loadedA=AniyomiHost();if(anime)AniyomiRepoManager(context,loadedA).ensureLoaded()else MangaRepoManager(context,loadedM).ensureLoaded()
  val rows=if(anime)loadedA.rows else loadedM.rows
  check(rows.containsKey("new-language"));check(rows["original"]!!.getString("apkUrl")=="https://fixture/new.apk")
  ExtensionIndex.data=fixture("https://fixture/relocated.apk","original","new-language")
  if(anime)ah.refreshMissingApk!!("original")else mh.refreshMissingApk!!("original")
  val refreshed=if(anime)ah.rows else mh.rows;check(refreshed["original"]!!.getString("apkUrl")=="https://fixture/relocated.apk")
  println("PASS ${if(anime)"Aniyomi" else "Manga"}: failed/empty reinstallation preserves metadata; added source ID survives restart; expired APK URL refresh updates owning repo")
 }
}
'''
 for name,body in files.items():(d/name).write_text(body)
 cp=os.pathsep.join(map(str,compiler));runtime=os.pathsep.join(map(str,[stdlib,json,compiler[-1]]))
 production=[native/f/(c+'RepoManager.kt') for f,c in [('manga','Manga'),('aniyomi','Aniyomi')]]
 if os.environ.get('NATIVE_BASELINE') == '1':
  for original in production:
   (d/original.name).write_bytes(subprocess.check_output(['git','-C',str(root),'show','HEAD:'+str(original.relative_to(root))]))
  production=[]
 src=[str(p) for p in d.glob('*.kt')]+list(map(str,production))
 cmd=[str(java),'-cp',cp,'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',runtime,'-d',str(d/'tests.jar'),*src]
 subprocess.run(cmd,check=True)
 subprocess.run([str(java),'-cp',runtime+os.pathsep+str(d/'tests.jar'),'MainKt'],check=True)
