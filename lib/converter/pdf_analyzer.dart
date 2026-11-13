import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Uma linha de texto reconstruída a partir dos caracteres do PDF.
class TextLine {
  TextLine(this.text, this.left, this.top, this.right, this.bottom);
  String text;
  final double left, top, right, bottom; // coordenadas do PDF (y para cima)
  double get height => top - bottom;
  double get width => right - left;
}

/// Região de figura (imagem/desenho) detectada numa página, em frações da página (0..1, y para baixo).
class FigureRegion {
  FigureRegion(this.x0, this.y0, this.x1, this.y1);
  final double x0, y0, x1, y1;
}

class PageInfo {
  PageInfo(this.pageNumber, this.width, this.height, this.lines);
  final int pageNumber;
  final double width, height;
  final List<TextLine> lines;
  int get charCount => lines.fold(0, (s, l) => s + l.text.trim().length);

  // preenchidos pela análise visual
  double ink = 0; // fração de pixels não brancos
  double colorfulness = 0; // saturação média dos pixels com tinta
  double nonTextInk = 0; // fração de pixels com tinta fora das linhas de texto
  List<FigureRegion> figures = [];
}

/// Lê o texto de uma página e reconstrói as linhas.
Future<List<TextLine>> extractLines(PdfPage page) async {
  final raw = await page.loadText();
  if (raw == null) return [];
  final text = raw.fullText;
  final rects = raw.charRects;
  final lines = <TextLine>[];
  final sb = StringBuffer();
  double l = double.infinity, t = -double.infinity, r = -double.infinity, b = double.infinity;
  PdfRect? prev;

  void flush() {
    final s = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isNotEmpty && l.isFinite) lines.add(TextLine(s, l, t, r, b));
    sb.clear();
    l = double.infinity;
    t = -double.infinity;
    r = -double.infinity;
    b = double.infinity;
    prev = null;
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '\r') continue;
    if (ch == '\n') {
      flush();
      continue;
    }
    final rc = i < rects.length ? rects[i] : null;
    final valid = rc != null && rc.width >= 0 && rc.height > 0;
    if (valid && ch.trim().isNotEmpty) {
      // salto vertical grande sem quebra explícita => nova linha
      if (prev != null) {
        final p = prev!;
        final h = math.max(p.height, rc.height);
        final overlap = math.min(p.top, rc.top) - math.max(p.bottom, rc.bottom);
        if (overlap < -0.2 * h) flush();
      }
      l = math.min(l, rc.left);
      t = math.max(t, rc.top);
      r = math.max(r, rc.right);
      b = math.min(b, rc.bottom);
      prev = rc;
    }
    sb.write(ch);
  }
  flush();
  return lines;
}

/// Renderiza a página numa largura fixa e devolve uma imagem RGBA.
Future<img.Image?> renderPage(PdfPage page, int targetWidth, {int? maxHeight}) async {
  var scale = targetWidth / page.width;
  if (maxHeight != null && page.height * scale > maxHeight) scale = maxHeight / page.height;
  final w = math.max(1, (page.width * scale).round());
  final h = math.max(1, (page.height * scale).round());
  final pi = await page.render(width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xffffffff);
  if (pi == null) return null;
  try {
    return img.Image.fromBytes(
      width: pi.width,
      height: pi.height,
      bytes: Uint8List.fromList(pi.pixels).buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
  } finally {
    pi.dispose();
  }
}

/// Analisa visualmente a página: tinta, cor e regiões de figura fora do texto.
Future<void> analyzeVisual(PdfPage page, PageInfo info, {int width = 160}) async {
  final im = await renderPage(page, width);
  if (im == null) return;
  final w = im.width, h = im.height;
  final sx = w / page.width, sy = h / page.height;

  // máscara de texto (com pequena margem)
  final textMask = List<bool>.filled(w * h, false);
  for (final ln in info.lines) {
    final pad = ln.height * 0.25;
    final x0 = ((ln.left - pad) * sx).floor().clamp(0, w - 1);
    final x1 = ((ln.right + pad) * sx).ceil().clamp(0, w - 1);
    final y0 = ((page.height - ln.top - pad) * sy).floor().clamp(0, h - 1);
    final y1 = ((page.height - ln.bottom + pad) * sy).ceil().clamp(0, h - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        textMask[y * w + x] = true;
      }
    }
  }

  var ink = 0, nonText = 0;
  double satSum = 0;
  final rowCount = List<int>.filled(h, 0);
  final figMask = List<bool>.filled(w * h, false);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      if (mx < 235 || (mx - mn) > 25) {
        ink++;
        satSum += mx == 0 ? 0 : (mx - mn) / mx;
        if (!textMask[y * w + x]) {
          nonText++;
          figMask[y * w + x] = true;
          rowCount[y]++;
        }
      }
    }
  }
  final total = w * h;
  info.ink = ink / total;
  info.colorfulness = ink == 0 ? 0 : satSum / ink;
  info.nonTextInk = nonText / total;

  // Segmenta faixas verticais com bastante "tinta" fora do texto => figuras
  final figs = <FigureRegion>[];
  final minRow = math.max(2, (w * 0.04).round());
  var y = 0;
  while (y < h) {
    if (rowCount[y] < minRow) {
      y++;
      continue;
    }
    var yEnd = y;
    var gap = 0;
    while (yEnd + 1 < h && gap < 3) {
      yEnd++;
      if (rowCount[yEnd] < minRow) {
        gap++;
      } else {
        gap = 0;
      }
    }
    yEnd -= gap;
    final bandH = yEnd - y + 1;
    if (bandH >= h * 0.06) {
      var x0 = w, x1 = 0, cnt = 0;
      for (var yy = y; yy <= yEnd; yy++) {
        for (var x = 0; x < w; x++) {
          if (figMask[yy * w + x]) {
            cnt++;
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
          }
        }
      }
      final area = (x1 - x0 + 1) * bandH;
      // exige uma região razoavelmente preenchida (ignora linhas finas/decorações)
      if (x1 > x0 && (x1 - x0) >= w * 0.15 && cnt / area > 0.12) {
        figs.add(FigureRegion(
          math.max(0, x0 - 2) / w,
          math.max(0, y - 2) / h,
          math.min(w, x1 + 3) / w,
          math.min(h, yEnd + 3) / h,
        ));
      }
    }
    y = yEnd + 1;
  }
  info.figures = figs;
}

/// Escolhe qual das primeiras páginas é a capa.
/// Retorna o índice (0-based) dentro de [candidates].
int pickCover(List<PageInfo> candidates) {
  var best = 0;
  var bestScore = -double.infinity;
  for (var i = 0; i < candidates.length; i++) {
    final p = candidates[i];
    var score = 0.0;
    if (p.ink < 0.01) {
      score = -10; // página em branco
    } else {
      score += p.nonTextInk * 4; // imagem/ilustração ocupando a página
      score += p.colorfulness * 2; // capas costumam ser coloridas
      score += math.min(p.ink, 0.6);
      if (p.charCount > 900) score -= 1.5; // página de texto corrido não é capa
      if (p.charCount > 400) score -= 0.5;
      score -= i * 0.25; // a capa geralmente é a 1ª página
    }
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}
