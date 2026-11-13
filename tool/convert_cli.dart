// Teste do conversor no PC: dart run tool/convert_cli.dart arquivo.pdf pasta_saida
import 'dart:io';

import 'package:pdf_kindle/converter/pdf_to_epub.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final input = args[0];
  final outDir = Directory(args.length > 1 ? args[1] : '.')..createSync(recursive: true);
  final name = input.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  final sw = Stopwatch()..start();
  final r = await PdfToEpubConverter(onProgress: (m, p) => stdout.writeln('[${(p * 100).round()}%] $m'))
      .convertFile(input, title: name);
  File('${outDir.path}/$name.epub').writeAsBytesSync(r.epub);
  File('${outDir.path}/$name.cover.jpg').writeAsBytesSync(r.coverJpeg);
  stdout.writeln('capa=página ${r.coverPage}, modoImagem=${r.imageMode}, '
      'epub=${(r.epub.length / 1024).round()} KB, ${sw.elapsedMilliseconds} ms');
  exit(0);
}
