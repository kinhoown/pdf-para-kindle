// Gera o e-mail exatamente como o app e entrega a um SMTP local (porta 2525) para inspeção.
// Uso: rodar um SMTP de captura em 127.0.0.1:2525 e então
//   flutter test test/mail_format_test.dart --dart-define=EPUB=caminho.epub
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:pdf_kindle/services/kindle_sender.dart';
import 'package:pdf_kindle/services/settings.dart';

void main() {
  test('envia para SMTP local', () async {
    final s = AppSettings(kindleEmail: 'alguem@kindle.com', senderEmail: 'remetente@gmail.com', appPassword: 'x');
    final msg = KindleSender(s).buildMessage(File(const String.fromEnvironment('EPUB')), 'Memórias Póstumas de Brás Cubas');
    await send(msg, SmtpServer('127.0.0.1', port: 2525, allowInsecure: true));
  }, skip: const String.fromEnvironment('EPUB').isEmpty);
}
