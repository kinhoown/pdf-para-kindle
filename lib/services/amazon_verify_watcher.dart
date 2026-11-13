import 'dart:async';

import 'package:enough_mail/enough_mail.dart';

import 'settings.dart';

/// E-mail da Amazon pedindo para confirmar o envio, com o link do botão de confirmação.
class AmazonVerification {
  AmazonVerification({required this.url, required this.subject});
  final String? url; // null = achou o e-mail, mas não reconheceu o link
  final String subject;
}

/// Depois do envio, olha a caixa de entrada (IMAP, com a mesma senha de app)
/// até chegar o e-mail "verifique sua solicitação" da Amazon.
/// Só lê: não apaga nem marca nada como lido.
class AmazonVerifyWatcher {
  AmazonVerifyWatcher(this.settings);
  final AppSettings settings;

  String get imapHost {
    final h = settings.smtpHost.toLowerCase();
    if (h.contains('gmail')) return 'imap.gmail.com';
    if (h.contains('outlook') || h.contains('office365') || h.contains('hotmail')) return 'outlook.office365.com';
    if (h.startsWith('smtp.')) return 'imap.${h.substring(5)}';
    return h;
  }

  /// Verifica a cada [every] até achar o e-mail, até [timeout] ou até [isCancelled] retornar true.
  Future<AmazonVerification?> waitFor({
    required DateTime sentAt,
    Duration timeout = const Duration(minutes: 8),
    Duration every = const Duration(seconds: 15),
    bool Function()? isCancelled,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (isCancelled?.call() ?? false) return null;
      try {
        final found = await checkOnce(sentAt);
        if (found != null) return found;
      } catch (_) {
        // sem internet / IMAP desligado: tenta de novo na próxima volta
      }
      await Future<void>.delayed(every);
    }
    return null;
  }

  Future<AmazonVerification?> checkOnce(DateTime sentAt) async {
    final client = ImapClient();
    try {
      await client.connectToServer(imapHost, 993, isSecure: true);
      await client.login(settings.senderEmail, settings.appPassword.replaceAll(' ', ''));
      final boxes = await client.listMailboxes(recursive: true);
      final targets = boxes.where((b) => b.isInbox || b.isJunk).toList();
      AmazonVerification? best;
      DateTime? bestDate;
      for (final box in targets) {
        await client.selectMailbox(box);
        final since = sentAt.subtract(const Duration(days: 1));
        final res = await client.searchMessages(searchCriteria: 'FROM "amazon" SINCE ${_imapDate(since)}');
        final seq = res.matchingSequence;
        if (seq == null || seq.isEmpty) continue;
        final ids = seq.toList();
        final last = ids.length > 8 ? ids.sublist(ids.length - 8) : ids;
        final fetched = await client.fetchMessages(MessageSequence.fromIds(last), 'BODY.PEEK[]');
        for (final m in fetched.messages) {
          final date = m.decodeDate();
          // só e-mails que chegaram depois do envio (com folga para relógios diferentes)
          if (date == null || date.isBefore(sentAt.subtract(const Duration(minutes: 2)))) continue;
          final subject = m.decodeSubject() ?? '';
          final html = m.decodeTextHtmlPart() ?? '';
          final plain = m.decodeTextPlainPart() ?? '';
          if (!looksLikeVerification(subject, '$html\n$plain')) continue;
          if (bestDate == null || date.isAfter(bestDate)) {
            bestDate = date;
            best = AmazonVerification(url: extractVerificationLink(html, plain), subject: subject);
          }
        }
      }
      return best;
    } finally {
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  static String _imapDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day}-${m[d.month - 1]}-${d.year}';
  }
}

final _verifyWords = RegExp(r'verif|confirm|aprov|approv', caseSensitive: false);
final _kindleWords = RegExp(r'kindle', caseSensitive: false);

/// O e-mail é o pedido de confirmação do "Enviar para Kindle"?
bool looksLikeVerification(String subject, String body) {
  final all = '$subject\n$body';
  return _kindleWords.hasMatch(all) && _verifyWords.hasMatch(all);
}

/// Acha o link do botão de confirmação dentro do e-mail da Amazon.
String? extractVerificationLink(String html, [String plain = '']) {
  final candidates = <({String url, int score})>[];
  final anchor = RegExp(r'''<a\b[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false, dotAll: true);
  for (final m in anchor.allMatches(html)) {
    final url = _unescape(m.group(1)!.trim());
    final text = _unescape(m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' ')).trim();
    final s = _score(url, text);
    if (s > 0) candidates.add((url: url, score: s));
  }
  for (final m in RegExp(r'https://[^\s<>"\]]+').allMatches(plain)) {
    final url = m.group(0)!;
    final s = _score(url, '');
    if (s > 0) candidates.add((url: url, score: s));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.url;
}

int _score(String url, String text) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https' || !u.host.toLowerCase().contains('amazon')) return 0;
  final lu = url.toLowerCase();
  final lt = text.toLowerCase();
  // links de rodapé nunca são o botão
  if (RegExp(r'unsubscribe|privacy|privacidade|notification|preferenc|help|ajuda|condit|logo|cancel').hasMatch('$lu $lt')) {
    return 0;
  }
  var s = 0;
  if (_verifyWords.hasMatch(lu)) s += 4;
  if (_verifyWords.hasMatch(lt)) s += 4;
  if (lu.contains('kindle') || lu.contains('stk') || lu.contains('sendtokindle')) s += 1;
  return s >= 4 ? s : 0;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ');
