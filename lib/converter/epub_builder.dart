import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // remove caracteres de controle inválidos em XML
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]'), '');

class EpubImage {
  EpubImage(this.id, this.fileName, this.bytes);
  final String id;
  final String fileName; // relativo a OEBPS/images/
  final Uint8List bytes;
}

class EpubChapter {
  EpubChapter(this.title, this.bodyHtml);
  final String title;
  final String bodyHtml;
}

/// Monta um EPUB 3 (com NCX para compatibilidade) que o Send to Kindle aceita.
class EpubBuilder {
  EpubBuilder({required this.title, required this.author, this.language = 'pt-BR'});

  final String title;
  final String author;
  final String language;
  EpubImage? cover;
  final chapters = <EpubChapter>[];
  final images = <EpubImage>[];

  static const _css = '''
body { margin: 0 3%; font-family: serif; line-height: 1.4; }
p { margin: 0; text-indent: 1.4em; text-align: justify; }
p.first, h1 + p, h2 + p, h3 + p, div.fig + p { text-indent: 0; }
h1 { font-size: 1.6em; text-align: center; margin: 1.5em 0 1em; page-break-before: always; }
h2 { font-size: 1.3em; margin: 1.2em 0 0.6em; }
h3 { font-size: 1.1em; margin: 1em 0 0.4em; }
div.fig { text-align: center; margin: 0.8em 0; text-indent: 0; }
div.fig img { max-width: 100%; }
div.page { text-align: center; page-break-after: always; margin: 0; }
div.page img { max-width: 100%; max-height: 100%; }
''';

  Uint8List build() {
    final uid = 'urn:uuid:${_uuid()}';
    final archive = Archive();

    // mimetype precisa ser o primeiro e sem compressão
    final mime = ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'));
    mime.compression = CompressionType.none;
    archive.add(mime);

    archive.add(ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''));

    archive.add(ArchiveFile.string('OEBPS/style.css', _css));

    final manifest = StringBuffer();
    final spine = StringBuffer();
    final navItems = StringBuffer();
    final ncxItems = StringBuffer();

    manifest.writeln('<item id="css" href="style.css" media-type="text/css"/>');
    manifest.writeln('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>');
    manifest.writeln('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');

    var coverMeta = '';
    if (cover != null) {
      final c = cover!;
      archive.add(_stored('OEBPS/images/${c.fileName}', c.bytes));
      manifest.writeln('<item id="cover-image" href="images/${c.fileName}" media-type="image/jpeg" properties="cover-image"/>');
      manifest.writeln('<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>');
      spine.writeln('<itemref idref="cover" linear="yes"/>');
      coverMeta = '<meta name="cover" content="cover-image"/>';
      archive.add(ArchiveFile.string('OEBPS/cover.xhtml', _xhtml('Capa', '''
<div style="text-align:center;margin:0;padding:0;">
<img src="images/${c.fileName}" alt="Capa" style="max-width:100%;max-height:100%;"/>
</div>''')));
    }

    for (final im in images) {
      archive.add(_stored('OEBPS/images/${im.fileName}', im.bytes));
      manifest.writeln('<item id="${im.id}" href="images/${im.fileName}" media-type="image/jpeg"/>');
    }

    var playOrder = 1;
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final name = 'chap${(i + 1).toString().padLeft(4, '0')}.xhtml';
      archive.add(ArchiveFile.string('OEBPS/$name', _xhtml(ch.title, ch.bodyHtml)));
      manifest.writeln('<item id="c$i" href="$name" media-type="application/xhtml+xml"/>');
      spine.writeln('<itemref idref="c$i"/>');
      final t = xmlEscape(ch.title);
      navItems.writeln('<li><a href="$name">$t</a></li>');
      ncxItems.writeln('<navPoint id="np$i" playOrder="${playOrder++}"><navLabel><text>$t</text></navLabel><content src="$name"/></navPoint>');
    }

    final now = DateTime.now().toUtc().toIso8601String().split('.').first;
    archive.add(ArchiveFile.string('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="$language">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">$uid</dc:identifier>
    <dc:title>${xmlEscape(title)}</dc:title>
    <dc:creator>${xmlEscape(author)}</dc:creator>
    <dc:language>$language</dc:language>
    <meta property="dcterms:modified">${now}Z</meta>
    $coverMeta
  </metadata>
  <manifest>
$manifest  </manifest>
  <spine toc="ncx">
$spine  </spine>
</package>'''));

    archive.add(ArchiveFile.string('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language">
<head><title>Sumário</title></head>
<body>
<nav epub:type="toc" id="toc"><h1>Sumário</h1><ol>
$navItems</ol></nav>
</body>
</html>'''));

    archive.add(ArchiveFile.string('OEBPS/toc.ncx', '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="$uid"/></head>
  <docTitle><text>${xmlEscape(title)}</text></docTitle>
  <navMap>
$ncxItems  </navMap>
</ncx>'''));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  ArchiveFile _stored(String name, Uint8List bytes) {
    final f = ArchiveFile.bytes(name, bytes);
    f.compression = CompressionType.none; // JPEG já é comprimido
    return f;
  }

  String _xhtml(String t, String body) => '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$language">
<head><title>${xmlEscape(t)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
$body
</body>
</html>''';

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
