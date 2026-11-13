import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'epub_builder.dart';
import 'pdf_analyzer.dart';

typedef ProgressCallback = void Function(String message, double progress);

class ConversionResult {
  ConversionResult({
    required this.epub,
    required this.coverJpeg,
    required this.coverPage,
    required this.title,
    required this.pageCount,
    required this.imageMode,
  });
  final Uint8List epub;
  final Uint8List coverJpeg;
  final int coverPage; // 1-based
  final String title;
  final int pageCount;
  final bool imageMode; // true = páginas como imagem (PDF escaneado/quadrinhos)
}

/// Converte um PDF em EPUB com capa, pronto para o Kindle.
class PdfToEpubConverter {
  PdfToEpubConverter({this.onProgress, this.maxEpubBytes = 22 * 1024 * 1024});

  final ProgressCallback? onProgress;

  /// Limite de tamanho (e-mail do Gmail aceita ~25 MB contando a codificação).
  final int maxEpubBytes;

  void _p(String m, double v) => onProgress?.call(m, v);

  Future<ConversionResult> convertFile(String pdfPath, {required String title, int? forcedCoverPage}) async {
    final doc = await PdfDocument.openFile(pdfPath);
    try {
      return await _convert(doc, title: title, forcedCoverPage: forcedCoverPage);
    } finally {
      await doc.dispose();
    }
  }

  Future<ConversionResult> _convert(PdfDocument doc, {required String title, int? forcedCoverPage}) async {
    final pages = doc.pages;
    final n = pages.length;
    if (n == 0) throw Exception('O PDF não tem páginas.');

    // 1) Texto de todas as páginas
    final infos = <PageInfo>[];
    for (var i = 0; i < n; i++) {
      if (i % 5 == 0) _p('Lendo texto (página ${i + 1} de $n)', 0.05 + 0.35 * i / n);
      final pg = pages[i];
      infos.add(PageInfo(pg.pageNumber, pg.width, pg.height, await extractLines(pg)));
    }

    // 2) Detectar a capa entre as primeiras páginas
    _p('Procurando a capa…', 0.42);
    final candCount = math.min(4, n);
    for (var i = 0; i < candCount; i++) {
      await analyzeVisual(pages[i], infos[i]);
    }
    int coverIdx;
    if (forcedCoverPage != null && forcedCoverPage >= 1 && forcedCoverPage <= n) {
      coverIdx = forcedCoverPage - 1;
    } else {
      coverIdx = pickCover(infos.sublist(0, candCount));
    }
    final coverImg = await renderPage(pages[coverIdx], 1200, maxHeight: 1800);
    if (coverImg == null) throw Exception('Não consegui desenhar a capa.');
    final coverJpeg = Uint8List.fromList(img.encodeJpg(coverImg, quality: 88));

    final book = EpubBuilder(title: title, author: 'Desconhecido');
    book.cover = EpubImage('cover-image', 'cover.jpg', coverJpeg);

    // Páginas de conteúdo: tudo depois da capa (páginas antes dela normalmente são brancas)
    final contentStart = coverIdx + 1;
    final contentIdx = [for (var i = contentStart; i < n; i++) i];
    final totalChars = contentIdx.fold<int>(0, (s, i) => s + infos[i].charCount);
    final imageMode = contentIdx.isNotEmpty && totalChars / contentIdx.length < 150;

    final outline = await _flattenOutline(doc);

    if (imageMode) {
      await _buildImageMode(book, pages, contentIdx, outline);
    } else {
      await _buildTextMode(book, pages, infos, contentIdx, outline);
    }

    _p('Montando o arquivo do Kindle…', 0.95);
    var epub = book.build();
    if (epub.length > maxEpubBytes && imageMode) {
      // reduz qualidade e tenta de novo
      _p('Arquivo grande, comprimindo mais…', 0.95);
      final b2 = EpubBuilder(title: title, author: 'Desconhecido')..cover = book.cover;
      await _buildImageMode(b2, pages, contentIdx, outline, width: 900, quality: 55);
      epub = b2.build();
    }
    _p('Pronto!', 1);
    return ConversionResult(
      epub: epub,
      coverJpeg: coverJpeg,
      coverPage: coverIdx + 1,
      title: title,
      pageCount: n,
      imageMode: imageMode,
    );
  }

  /// Lista (página -> título) a partir do sumário do PDF, só níveis 0 e 1.
  Future<List<({int page, String title, int level})>> _flattenOutline(PdfDocument doc) async {
    final out = <({int page, String title, int level})>[];
    try {
      final nodes = await doc.loadOutline();
      void walk(List<PdfOutlineNode> ns, int level) {
        for (final nd in ns) {
          final t = nd.title.trim();
          if (nd.dest != null && t.isNotEmpty && level <= 1) {
            out.add((page: nd.dest!.pageNumber, title: t, level: level));
          }
          walk(nd.children, level + 1);
        }
      }

      walk(nodes, 0);
    } catch (_) {}
    out.sort((a, b) => a.page.compareTo(b.page));
    return out;
  }

  // ---------------------------------------------------------------- modo imagem
  Future<void> _buildImageMode(
    EpubBuilder book,
    List<PdfPage> pages,
    List<int> contentIdx,
    List<({int page, String title, int level})> outline, {
    int width = 1072,
    int quality = 70,
  }) async {
    final chunk = <String>[];
    var chunkStart = contentIdx.isEmpty ? 0 : contentIdx.first;
    final starts = {for (final o in outline.where((o) => o.level == 0)) o.page - 1: o.title};
    String? chunkTitle;

    void flush(int lastIdx) {
      if (chunk.isEmpty) return;
      book.chapters.add(EpubChapter(chunkTitle ?? 'Páginas ${chunkStart + 1}–${lastIdx + 1}', chunk.join('\n')));
      chunk.clear();
    }

    for (var k = 0; k < contentIdx.length; k++) {
      final i = contentIdx[k];
      if (k % 3 == 0) _p('Convertendo páginas em imagem (${k + 1} de ${contentIdx.length})', 0.45 + 0.5 * k / contentIdx.length);
      final startsChapter = starts.containsKey(i);
      if ((startsChapter || chunk.length >= 10) && chunk.isNotEmpty) {
        flush(i - 1);
        chunkStart = i;
        chunkTitle = null;
      }
      if (chunk.isEmpty) {
        chunkStart = i;
        chunkTitle = starts[i];
      }
      final im = await renderPage(pages[i], width, maxHeight: (width * 1.45).round());
      if (im == null) continue;
      final id = 'p${i + 1}';
      book.images.add(EpubImage(id, '$id.jpg', Uint8List.fromList(img.encodeJpg(im, quality: quality))));
      chunk.add('<div class="page"><img src="images/$id.jpg" alt="Página ${i + 1}"/></div>');
    }
    flush(contentIdx.isEmpty ? 0 : contentIdx.last);
  }

  // ---------------------------------------------------------------- modo texto
  Future<void> _buildTextMode(
    EpubBuilder book,
    List<PdfPage> pages,
    List<PageInfo> infos,
    List<int> contentIdx,
    List<({int page, String title, int level})> outline,
  ) async {
    // Tamanho de fonte do corpo = mediana ponderada da altura das linhas
    final heights = <double>[];
    for (final i in contentIdx) {
      for (final l in infos[i].lines) {
        final reps = math.max(1, l.text.length ~/ 20);
        for (var r = 0; r < reps; r++) {
          heights.add(l.height);
        }
      }
    }
    heights.sort();
    final bodyH = heights.isEmpty ? 10.0 : heights[heights.length ~/ 2];

    final repeated = _findRunningHeaders(infos, contentIdx);

    final outlineByPage = <int, List<({int page, String title, int level})>>{};
    for (final o in outline) {
      outlineByPage.putIfAbsent(o.page - 1, () => []).add(o);
    }
    final useOutline = outline.where((o) => o.level == 0).length >= 2;

    var html = StringBuffer();
    var chapterTitle = 'Início';
    var chapterChars = 0;
    final para = StringBuffer();
    TextLine? prevLine;
    var firstInSection = true;
    var figCount = 0;

    void endPara() {
      final t = para.toString().trim();
      if (t.isNotEmpty) {
        html.writeln(firstInSection ? '<p class="first">${xmlEscape(t)}</p>' : '<p>${xmlEscape(t)}</p>');
        chapterChars += t.length;
        firstInSection = false;
      }
      para.clear();
    }

    void endChapter() {
      endPara();
      final body = html.toString().trim();
      if (body.isNotEmpty) {
        book.chapters.add(EpubChapter(chapterTitle, body));
      }
      html = StringBuffer();
      chapterChars = 0;
    }

    void newChapter(String title) {
      endChapter();
      chapterTitle = title;
      firstInSection = true;
    }

    for (var k = 0; k < contentIdx.length; k++) {
      final i = contentIdx[k];
      final info = infos[i];
      final page = pages[i];
      if (k % 4 == 0) _p('Organizando o texto (página ${i + 1} de ${pages.length})', 0.45 + 0.5 * k / contentIdx.length);

      // Capítulos pelo sumário do PDF
      if (useOutline && outlineByPage.containsKey(i)) {
        final top = outlineByPage[i]!.where((o) => o.level == 0).toList();
        if (top.isNotEmpty) {
          newChapter(top.first.title);
          prevLine = null;
        }
      }

      // Figuras (análise visual de todas as páginas de conteúdo)
      if (info.ink == 0) {
        await analyzeVisual(page, info);
      }

      // Remove cabeçalhos/rodapés e números de página
      final lines = info.lines.where((l) {
        final yTop = (info.height - l.top) / info.height;
        final yBot = (info.height - l.bottom) / info.height;
        final edge = yBot < 0.09 || yTop > 0.91;
        if (!edge) return true;
        final norm = _norm(l.text);
        if (RegExp(r'^[#\s\-–—|.ivxlcdm]*$', caseSensitive: false).hasMatch(norm) && l.text.length < 12) return false;
        return !repeated.contains(norm);
      }).toList();

      // Junta linhas e figuras pela posição vertical
      final items = <({double y, TextLine? line, FigureRegion? fig})>[
        for (final l in lines) (y: (info.height - l.top) / info.height, line: l, fig: null),
        for (final f in info.figures) (y: f.y0, line: null, fig: f),
      ];
      // mantém a ordem do texto do PDF, inserindo figuras antes da primeira linha abaixo delas
      final ordered = <({double y, TextLine? line, FigureRegion? fig})>[];
      final figs = items.where((e) => e.fig != null).toList()..sort((a, b) => a.y.compareTo(b.y));
      var fi = 0;
      for (final e in items.where((e) => e.line != null)) {
        while (fi < figs.length && figs[fi].y < e.y) {
          ordered.add(figs[fi++]);
        }
        ordered.add(e);
      }
      while (fi < figs.length) {
        ordered.add(figs[fi++]);
      }

      // margens típicas da página
      final lefts = lines.map((l) => l.left).toList()..sort();
      final rights = lines.map((l) => l.right).toList()..sort();
      final leftM = lefts.isEmpty ? 0.0 : lefts[(lefts.length * 0.1).floor()];
      final rightM = rights.isEmpty ? info.width : rights[(rights.length * 0.9).floor().clamp(0, rights.length - 1)];
      final colW = math.max(1.0, rightM - leftM);

      img.Image? hiRes;

      for (final e in ordered) {
        if (e.fig != null) {
          final f = e.fig!;
          hiRes ??= await renderPage(page, 1000);
          if (hiRes == null) continue;
          final x = (f.x0 * hiRes.width).round(), y = (f.y0 * hiRes.height).round();
          final w = ((f.x1 - f.x0) * hiRes.width).round(), h = ((f.y1 - f.y0) * hiRes.height).round();
          if (w < 40 || h < 40) continue;
          endPara();
          final crop = img.copyCrop(hiRes, x: x, y: y, width: w, height: h);
          final id = 'fig${++figCount}';
          book.images.add(EpubImage(id, '$id.jpg', Uint8List.fromList(img.encodeJpg(crop, quality: 80))));
          html.writeln('<div class="fig"><img src="images/$id.jpg" alt=""/></div>');
          firstInSection = true;
          prevLine = null;
          continue;
        }

        final l = e.line!;
        final ratio = l.height / bodyH;
        final isHeading = ratio >= 1.3 && l.text.length < 120;
        if (isHeading) {
          endPara();
          final tag = ratio >= 1.8 ? 'h1' : 'h2';
          // título grande inicia capítulo quando não há sumário no PDF
          if (!useOutline && tag == 'h1' && chapterChars > 2000) {
            newChapter(l.text);
          } else if (!useOutline && tag == 'h1' && chapterTitle == 'Início') {
            chapterTitle = l.text;
          } else if (!useOutline && chapterChars > 60000) {
            newChapter(l.text);
          }
          html.writeln('<$tag>${xmlEscape(l.text)}</$tag>');
          firstInSection = true;
          prevLine = null;
          continue;
        }

        var breakPara = false;
        if (prevLine == null) {
          breakPara = para.isEmpty ? true : _endsSentence(para.toString());
        } else {
          final p = prevLine;
          final gap = p.bottom - l.top;
          if (p.width == 0) breakPara = true;
          if (gap > bodyH * 0.9) breakPara = true; // espaço vertical extra
          if (gap < -bodyH * 2) breakPara = _endsSentence(p.text); // nova coluna
          if ((l.height - p.height).abs() > bodyH * 0.3) breakPara = true; // mudou a fonte
          final shortPrev = p.right < rightM - colW * 0.12;
          if (shortPrev && _endsSentence(p.text)) breakPara = true;
          final indent = l.left - leftM;
          if (indent > info.width * 0.02 && indent < colW * 0.2 && _endsSentence(p.text)) breakPara = true;
          if (RegExp(r'^([•▪◦●■\-–—*]|\d{1,3}[.)]\s)').hasMatch(l.text)) breakPara = true;
        }
        if (breakPara) endPara();
        _appendLine(para, l.text);
        prevLine = l;
      }
      // a página acabou: o próximo parágrafo continua se a frase não terminou
      prevLine = null;
      // evita capítulos gigantes (arquivos muito grandes ficam lentos no Kindle)
      if (chapterChars > 120000 && _endsSentence(para.toString())) {
        newChapter('$chapterTitle (cont.)');
      }
    }
    endChapter();
    if (book.chapters.isEmpty) {
      book.chapters.add(EpubChapter(book.title, '<p>(sem texto)</p>'));
    }
  }

  static bool _endsSentence(String s) {
    final t = s.trimRight();
    if (t.isEmpty) return true;
    return RegExp(r'''[.!?:;…"”»)\]]$''').hasMatch(t);
  }

  static void _appendLine(StringBuffer para, String text) {
    if (para.isEmpty) {
      para.write(text);
      return;
    }
    final cur = para.toString();
    // hifenização: "pala-" + "vra" => "palavra"
    if (RegExp(r'[A-Za-zÀ-ÿ]-$').hasMatch(cur) && RegExp(r'^[a-zà-ÿ]').hasMatch(text)) {
      para
        ..clear()
        ..write(cur.substring(0, cur.length - 1))
        ..write(text);
    } else {
      para.write(' ');
      para.write(text);
    }
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Textos que se repetem no topo/rodapé de muitas páginas (cabeçalho corrente).
  Set<String> _findRunningHeaders(List<PageInfo> infos, List<int> idx) {
    if (idx.length < 4) return {};
    final counts = <String, int>{};
    for (final i in idx) {
      final info = infos[i];
      final seen = <String>{};
      for (final l in info.lines) {
        final yTop = (info.height - l.top) / info.height;
        final yBot = (info.height - l.bottom) / info.height;
        if (yBot < 0.09 || yTop > 0.91) seen.add(_norm(l.text));
      }
      for (final s in seen) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }
    final minCount = math.max(3, (idx.length * 0.2).round());
    return {for (final e in counts.entries) if (e.value >= minCount) e.key};
  }
}
