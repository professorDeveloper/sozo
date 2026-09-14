#!/usr/bin/env python3
"""Exercise actual production retry/dispose methods with delayed codec release."""
from pathlib import Path
import subprocess, tempfile, sys, re
root = Path(__file__).resolve().parents[5]
path = 'lib/features/detail/presentation/pages/player_page.media.dart'
source = subprocess.check_output(['git','show',f'HEAD:{path}'],cwd=root,text=True) if '--baseline' in sys.argv else (root/path).read_text()
def method(name):
 start=re.search(r'  Future<[^>]+> '+re.escape(name)+r'\(',source).start()
 # body begins after the signature; these methods have no named params.
 begin=source.index('{',start); depth=1; end=begin+1
 while depth:
  depth += (source[end]=='{')-(source[end]=='}'); end+=1
 return source[start:end]
code="""import 'dart:async';
class Args { bool isSerial=false; }
class Widget { final args=Args(); }
enum _LoadingStage {loading}
class FramePreviewService { static Future<void> close() async {} }
class Controller { final done=Completer<void>(); void removeListener(Object x){} Future<void> pause() async {} Future<void> dispose()=>done.future; }
class Harness {
 final widget=Widget(); bool mounted=true; int _mediaGeneration=0; Timer? _hideTimer; Controller? _controller;
 bool _wasPlaying=false,_wasBuffering=false,_wasInitialized=false,_initializing=false,_isCodecError=false;
 Object? _lastError,_errorMessage; _LoadingStage? _stage; String? _videoUrl='video'; final _headers=<String,String>{}; String? _mediaType; int _episodeIndex=0;
 final starts=<String>[]; void _onMajorChange(){} void setState(void Function() f)=>f();
 Future<void> _loadEpisode(int i) async {}
 Future<void> _initializeWith({required String url,required Map<String,String> headers,required String? type,int? intentGeneration})async { if(intentGeneration!=null && intentGeneration!=_mediaGeneration)return; starts.add(url); _wasPlaying=true; }
"""+method('_retry')+'\n'+method('_disposeController')+"""
}
Future<void> main() async {
 final h=Harness(); final slow=Controller(); h._controller=slow;
 final first=h._retry(); await Future<void>.delayed(Duration.zero);
 h._videoUrl='newer'; final second=h._retry();
 await Future<void>.delayed(Duration.zero);
 slow.done.complete(); await Future.wait([first,second]);
 if(h.starts.length!=1 || h.starts.single!='newer') throw StateError('stale retry started playback: ${h.starts}');
 if(!h._wasPlaying) throw StateError('late dispose reset current playback');
 print('PASS: newer retry alone starts; late codec teardown preserves current state');
}
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'race.dart';p.write_text(code)
 result=subprocess.run(['/Users/azamov/dev/flutter/bin/dart',str(p)],text=True)
 sys.exit(result.returncode)
