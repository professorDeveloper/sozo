// Audit-only characterization tests. Assertions describe the current defects.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';

final auditBoundary=GlobalKey();
class Settings implements HiveService {
  final bool spread; final String mode;
  Settings({this.spread=false,this.mode='horizontal'});
  @override bool get readerSpread => spread;
  @override String getReaderMode(String url) => mode;
  @override bool getReaderRtl(String url) => false;
  @override String getReaderBackground() => 'black';
  @override double getNovelFontSize() => 18;
  @override double getNovelLineHeight() => 1.62;
  @override String getNovelFontFamily() => '';
  @override bool getNovelJustify() => false;
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class Downloads implements DownloadRepository {
  @override final revision=ValueNotifier<int>(0);
  int enqueueCount=0;
  EnqueueOutcome outcome=EnqueueOutcome.started;
  DownloadRequest? lastRequest;
  @override Future<List<MangaPageEntity>> localMangaPages(String id) async => [];
  @override DownloadItem? byId(String id) => null;
  @override Future<EnqueueOutcome> enqueue(DownloadRequest request) async {
    enqueueCount++; lastRequest=request; return outcome;
  }
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class Content implements DetailRepository {
  final bool novel; final refs=<String>[];
  Content({this.novel=false});
  @override Future<Result<MangaPagesEntity>> getPages({required String ref,required String provider}) async {
    refs.add(ref);
    return Success(MangaPagesEntity(
      pages: novel ? [] : List.generate(9,(i)=>MangaPageEntity(index:i,imageUrl:'/tmp/sozo-reader-audit-page-$i.png')),
      headers: const {},
      html: novel ? List.generate(40,(i)=>'<p>Chapter $ref, paragraph $i. Reading should scroll within this chapter.</p>').join() : null,
    ));
  }
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class History implements HistoryService {
  final saved=<HistoryItem>[];
  @override Future<void> save(HistoryItem item) async {saved.add(item);}
  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
Future<void> open(WidgetTester t,{required Settings settings,required Content content,int resume=0}) async {
  getIt.registerSingleton<HiveService>(settings);
  getIt.registerSingleton<GetDownloadsUseCase>(GetDownloadsUseCase(Downloads()));
  getIt.registerSingleton<EnqueueDownloadUseCase>(EnqueueDownloadUseCase(getIt<GetDownloadsUseCase>().repository));
  getIt.registerSingleton<GetPagesUseCase>(GetPagesUseCase(content));
  getIt.registerSingleton<HistoryService>(History());
  t.view.physicalSize=const Size(1200,800); t.view.devicePixelRatio=1;
  await t.pumpWidget(RepaintBoundary(key:auditBoundary,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'AuditFont'),home:ReaderPage(args:ReaderArgs(title:'Audit',provider:'test',contentUrl:'test://title',resumePage:resume,chapters:const [EpisodeEntity(episode:1,label:'One',mediaRef:'one'),EpisodeEntity(episode:2,label:'Two',mediaRef:'two')])))));
  await t.pump(); await t.pump(const Duration(milliseconds:50));
}
Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox()); await t.pump();
  t.view.resetPhysicalSize(); t.view.resetDevicePixelRatio();
  await getIt.reset();
}
Future<void> screenshot(WidgetTester t,String name) async {
  for(var i=0;i<4;i++){
    await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds:100)); });
    await t.pump();
  }
  final boundary=auditBoundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img=await boundary.toImage(pixelRatio:1);
    final bytes=await img.toByteData(format:ui.ImageByteFormat.png);
    final file=File('docs/audits/2026-09-14/source-reader/screenshots/$name.png');
    await file.parent.create(recursive:true);
    await file.writeAsBytes(bytes!.buffer.asUint8List()); img.dispose();
  });
}
void main(){
  setUpAll(() async {
    final font=File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if(await font.exists()){
      final loader=FontLoader('AuditFont')..addFont(font.readAsBytes().then((v)=>ByteData.sublistView(v)));
      await loader.load();
    }
    final icons=FontLoader('MaterialIcons')..addFont(File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf').readAsBytes().then((v)=>ByteData.sublistView(v)));
    await icons.load();
    for(var i=0;i<9;i++){
      final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder);
      canvas.drawColor(const Color(0xff172d3d),BlendMode.src);
      final text=TextPainter(text:TextSpan(text:'AUDIT FIXTURE\n\nPAGE ${i+1} / 9\n\n${i==0 ? "COVER — SPREAD SLOT 0" : "CHAPTER PAGE"}',style:const TextStyle(fontFamily:'AuditFont',fontSize:38,color:Colors.white)),textDirection:TextDirection.ltr);
      text.layout(maxWidth:700); text.paint(canvas,const Offset(80,200));
      final image=await recorder.endRecording().toImage(800,700);
      final data=await image.toByteData(format:ui.ImageByteFormat.png);
      await File('/tmp/sozo-reader-audit-page-$i.png').writeAsBytes(data!.buffer.asUint8List()); image.dispose();
    }
  });
  testWidgets('chapter transition cancels unsaved position from previous chapter',(t) async {
    await open(t,settings:Settings(),content:Content());
    final history=getIt<HistoryService>() as History;
    await t.pump(const Duration(milliseconds:900));
    expect(history.saved.single.positionMs,0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(); await t.pump(const Duration(milliseconds:250));
    expect(find.text('2/9'),findsOneWidget);
    await t.tap(find.widgetWithIcon(IconButton,Icons.skip_next_rounded));
    await t.pump(); await t.pump(const Duration(milliseconds:900));
    expect(history.saved.where((v)=>v.episodeNumber==1).last.positionMs,0,
      reason:'BUG: chapter one position 1 was discarded at transition');
    expect(history.saved.last.episodeNumber,2);
    await close(t);
  });

  testWidgets('control: horizontal swipe reaches PageView despite tap overlay',(t) async {
    await open(t,settings:Settings(),content:Content());
    final view=t.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page,0);
    await t.drag(find.byType(PageView),const Offset(-700,0));
    await t.pump(const Duration(milliseconds:400));
    expect(view.controller!.page,greaterThan(0),reason:'Control: suspected gesture interception was disproved');
    await close(t);
  });
  testWidgets('reader reports download started when enqueue rejects for no space',(t) async {
    await open(t,settings:Settings(),content:Content());
    final downloads=getIt<GetDownloadsUseCase>().repository as Downloads;
    downloads.outcome=EnqueueOutcome.noSpace;
    await t.tap(find.widgetWithIcon(IconButton,Icons.download_outlined)); await t.pump();
    expect(downloads.enqueueCount,1);
    expect(find.text('manga.download_started'),findsOneWidget);
    await close(t);
  });

  testWidgets('spread ignores resume and right-arrow targets detached single-page controller',(t) async {
    await open(t,settings:Settings(spread:true),content:Content(),resume:5);
    final view=t.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page,0,reason:'BUG: resumed page 5 should map to spread slot 3');
    expect(find.text('6/9'),findsOneWidget,reason:'Counter claims restored page while cover remains visible');
    await screenshot(t,'spread-resume-counter');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); await t.pump();
    expect(t.takeException(),isA<AssertionError>(),reason:'BUG: PageController is not attached to a PageView');
    await close(t);
  });
  testWidgets('novel shows 1/0 and PageDown skips unread prose to next chapter',(t) async {
    final content=Content(novel:true);
    await open(t,settings:Settings(mode:'vertical'),content:content);
    expect(find.text('1/0'),findsOneWidget);
    expect(t.widget<Slider>(find.byType(Slider)).onChanged,isNull);
    await screenshot(t,'novel-zero-pages');
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown); await t.pump(); await t.pump();
    expect(content.refs,['one','two'],reason:'BUG: PageDown should scroll prose, not resolve chapter two');
    await close(t);
  });
  testWidgets('novel offers download button but tapping it never enqueues',(t) async {
    await open(t,settings:Settings(),content:Content(novel:true));
    final button=find.widgetWithIcon(IconButton,Icons.download_outlined);
    expect(t.widget<IconButton>(button).onPressed,isNotNull);
    await t.tap(button); await t.pump();
    expect((getIt<GetDownloadsUseCase>().repository as Downloads).enqueueCount,0);
    await close(t);
  });
}
