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

  Future<void> sendEpub(File epub, String title) async {
    final safeName = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final message = Message()
      ..from = Address(settings.senderEmail, 'PDF para Kindle')
      ..recipients.add(settings.kindleEmail)
      ..subject = title
      ..text = 'Enviado pelo app PDF para Kindle.'
      ..attachments = [FileAttachment(epub, contentType: 'application/epub+zip', fileName: '$safeName.epub')];
    try {
      await send(message, _server, timeout: const Duration(minutes: 3));
    } on SmtpClientAuthenticationException {
      throw Exception('O e-mail recusou o login. Confira o e-mail remetente e a senha de app.');
    } on MailerException catch (e) {
      throw Exception('Falha ao enviar: ${e.message}');
    } on SocketException {
      throw Exception('Sem conexão com a internet.');
    }
  }
}
