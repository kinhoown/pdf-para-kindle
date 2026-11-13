import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'converter/pdf_analyzer.dart';
import 'converter/pdf_to_epub.dart';
import 'screens/settings_screen.dart';
import 'services/kindle_sender.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  runApp(const PdfKindleApp());
}

class PdfKindleApp extends StatelessWidget {
  const PdfKindleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF1F6F5C);
    return MaterialApp(
      title: 'PDF para Kindle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

enum Stage { idle, working, done, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSettings? _settings;
  Stage _stage = Stage.idle;
  String _message = '';
  double _progress = 0;
  Uint8List? _cover;
  String? _title;
  String? _pdfPath;
  int? _coverPage;
  static const _share = MethodChannel('pdf_kindle/share');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await AppSettings.load();
    setState(() => _settings = s);
    if (!s.isComplete) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await _openSettings(firstRun: true);
    }
    // PDF compartilhado/aberto a partir de outro app (WhatsApp, Drive, Arquivosâ€¦)
    _share.setMethodCallHandler((call) async {
      if (call.method == 'pdfShared') _onShared(call.arguments);
    });
    _onShared(await _share.invokeMethod('getInitialPdf'));
  }

  void _onShared(dynamic info) {
    if (info is! Map) return;
    final path = info['path'] as String?;
    if (path == null) return;
    _start(path, _nameFromPath(info['name'] as String? ?? path));
  }

  String _nameFromPath(String path) {
    var name = path.split(RegExp(r'[\\/]')).last;
    name = Uri.decodeComponent(name).replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[_]+'), ' ').trim();
    return name.isEmpty ? 'Documento' : name;
  }

  Future<void> _openSettings({bool firstRun = false}) async {
    final s = _settings ?? AppSettings();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(settings: s, firstRun: firstRun),
    ));
    setState(() => _settings = s);
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (f == null) return;
    String path;
    if (f.path != null) {
      path = f.path!;
    } else {
      final tmp = await getTemporaryDirectory();
      final out = File('${tmp.path}/entrada.pdf');
      final sink = out.openWrite();
      await sink.addStream(f.readAsByteStream());
      await sink.close();
      path = out.path;
    }
    await _start(path, _nameFromPath(f.name));
  }

  Future<void> _start(String path, String title, {int? forcedCoverPage}) async {
    if (_stage == Stage.working) return;
    final s = _settings;
    if (s == null || !s.isComplete) {
      await _openSettings(firstRun: true);
      if (!(_settings?.isComplete ?? false)) return;
    }
    setState(() {
      _stage = Stage.working;
      _progress = 0;
      _message = 'Abrindo o PDFâ€¦';
      _title = title;
      _pdfPath = path;
      if (forcedCoverPage == null) _cover = null;
    });
    try {
      final conv = PdfToEpubConverter(onProgress: (m, p) {
        if (mounted) {
          setState(() {
            _message = m;
            _progress = p * 0.85;
          });
        }
      });
      final r = await conv.convertFile(path, title: title, forcedCoverPage: forcedCoverPage);
      setState(() {
        _cover = r.coverJpeg;
        _coverPage = r.coverPage;
        _message = 'Enviando para o Kindleâ€¦';
        _progress = 0.9;
      });
      final tmp = await getTemporaryDirectory();
      final epub = File('${tmp.path}/livro.epub');
      await epub.writeAsBytes(r.epub);
      await KindleSender(_settings!).sendEpub(epub, title);
      setState(() {
        _stage = Stage.done;
        _progress = 1;
        _message = r.imageMode
            ? 'Enviado! (PDF escaneado: as pÃ¡ginas foram como imagem.)'
            : 'Enviado! Chega no Kindle em alguns minutos.';
      });
    } catch (e) {
      setState(() {
        _stage = Stage.error;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _changeCover() async {
    final path = _pdfPath;
    if (path == null) return;
    final page = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CoverPickerSheet(pdfPath: path, current: _coverPage ?? 1),
    );
    if (page != null && page != _coverPage) {
      await _start(path, _title ?? 'Documento', forcedCoverPage: page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF para Kindle'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings, tooltip: 'Configurar envio')],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _cover != null
                        ? ClipRRect(
                            key: ValueKey(_cover.hashCode),
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(_cover!, fit: BoxFit.contain),
                          )
                        : Icon(Icons.menu_book_rounded, size: 120, color: cs.primary.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_title != null) Text(_title!, style: t.titleMedium, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              if (_stage == Stage.working) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(_message, textAlign: TextAlign.center),
              ],
              if (_stage == Stage.done)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle, color: cs.primary),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_message)),
                ]),
              if (_stage == Stage.error)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.error, color: cs.error),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_message, style: TextStyle(color: cs.error))),
                ]),
              if (_stage == Stage.idle)
                Text('Escolha um PDF ou compartilhe um PDF com este app.\n'
                    'A capa Ã© detectada e o livro vai direto para o seu Kindle.',
                    textAlign: TextAlign.center, style: t.bodyMedium),
              const SizedBox(height: 16),
              if (_stage == Stage.done || _stage == Stage.error)
                TextButton.icon(
                  onPressed: _stage == Stage.done ? _changeCover : () => _start(_pdfPath!, _title!),
                  icon: Icon(_stage == Stage.done ? Icons.image_search : Icons.refresh),
                  label: Text(_stage == Stage.done ? 'Capa errada? Escolher outra e reenviar' : 'Tentar de novo'),
                ),
              FilledButton.icon(
                onPressed: _stage == Stage.working ? null : _pick,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Escolher PDF')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniaturas das primeiras pÃ¡ginas para escolher a capa manualmente.
class CoverPickerSheet extends StatefulWidget {
  const CoverPickerSheet({super.key, required this.pdfPath, required this.current});
  final String pdfPath;
  final int current;

  @override
  State<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends State<CoverPickerSheet> {
  final _thumbs = <Uint8List>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await PdfDocument.openFile(widget.pdfPath);
    try {
      final n = doc.pages.length < 8 ? doc.pages.length : 8;
      for (var i = 0; i < n; i++) {
        final im = await renderPage(doc.pages[i], 240);
        if (im == null || !mounted) continue;
        setState(() => _thumbs.add(Uint8List.fromList(img.encodeJpg(im, quality: 80))));
      }
    } finally {
      await doc.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Qual pÃ¡gina Ã© a capa?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 420,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: _thumbs.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => Navigator.pop(context, i + 1),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i + 1 == widget.current ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(_thumbs[i], fit: BoxFit.contain),
                    Positioned(right: 4, bottom: 4, child: CircleAvatar(radius: 11, child: Text('${i + 1}', style: const TextStyle(fontSize: 11)))),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
