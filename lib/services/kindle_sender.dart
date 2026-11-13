import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'settings.dart';

/// Envia o EPUB para o endereço "Enviar para Kindle" por e-mail (SMTP).
class KindleSender {
  KindleSender(this.settings);
  final AppSettings settings;

  SmtpServer get _server => SmtpServer(
        settings.smtpHost,
        port: settings.smtpPort,
        ssl: settings.smtpPort == 465,
        username: settings.senderEmail,
        password: settings.appPassword.replaceAll(' ', ''),
      );

  Future<void> sendEpub(File epub, String title, {SmtpServer? server}) async {
    final message = buildMessage(epub, title);
    try {
      await send(message, server ?? _server, timeout: const Duration(minutes: 3));
    } on SmtpClientAuthenticationException {
      throw Exception('O e-mail recusou o login. Confira o e-mail remetente e a senha de app.');
    } on MailerException catch (e) {
      throw Exception('Falha ao enviar: ${e.message}');
    } on SocketException {
      throw Exception('Sem conexão com a internet.');
    }
  }

  Message buildMessage(File epub, String title) {
    // Nome do anexo só com letras sem acento: se o nome vier codificado (=?utf-8?...?=)
    // o servidor da Amazon pode não reconhecer o ".epub" e descartar o arquivo.
    // O título com acentos continua dentro do livro (é o que aparece no Kindle).
    final safeName = asciiFileName(title);
    return Message()
      ..from = Address(settings.senderEmail, 'PDF para Kindle')
      ..recipients.add(settings.kindleEmail)
      ..subject = title
      ..text = 'Enviado pelo app PDF para Kindle.'
      ..attachments = [FileAttachment(epub, contentType: 'application/epub+zip', fileName: '$safeName.epub')];
  }
}

/// "Memórias Póstumas: Brás Cubas" -> "Memorias Postumas - Bras Cubas"
String asciiFileName(String title) {
  const from = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÇçÑñÝýÿ';
  const to = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNnYyy';
  final sb = StringBuffer();
  for (final ch in title.runes.map(String.fromCharCode)) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  var s = sb
      .toString()
      .replaceAll(RegExp(r'[:/\|]'), ' - ')
      .replaceAll(RegExp(r'[^A-Za-z0-9 ._()\-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > 80) s = s.substring(0, 80).trim();
  return s.isEmpty ? 'livro' : s;
}
