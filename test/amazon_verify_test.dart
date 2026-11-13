import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_kindle/services/amazon_verify_watcher.dart';

// E-mails de exemplo no formato típico da Amazon (botão + links de rodapé).
const _htmlEn = '''
<html><body>
<a href="https://www.amazon.com/ref=logo"><img alt="amazon"/></a>
<p>Action required: Verify your Send to Kindle request for "Memorias.epub".</p>
<table><tr><td><a href="https://www.amazon.com/sendtokindle/verify?token=ABC&amp;locale=en_US" style="background:#ffd814">Verify Request</a></td></tr></table>
<p><a href="https://www.amazon.com/gp/help/customer/display.html">Help</a>
<a href="https://www.amazon.com/privacy">Privacy Notice</a>
<a href="https://www.amazon.com/gp/unsubscribe?x=1">Unsubscribe</a></p>
</body></html>''';

const _htmlPt = '''
<html><body>
<p>Verifique sua solicitação de Enviar para Kindle.</p>
<a href="https://www.amazon.com.br/gp/f.html?C=XYZ&amp;R=1&amp;T=C&amp;U=https%3A%2F%2Fwww.amazon.com.br%2Fsendtokindle%2Fapprove">
  <span><b>Verificar solicitação</b></span></a>
<a href="https://www.amazon.com.br/gp/help/customer/display.html">Ajuda</a>
</body></html>''';

void main() {
  test('acha o botão de verificação (inglês)', () {
    expect(extractVerificationLink(_htmlEn), 'https://www.amazon.com/sendtokindle/verify?token=ABC&locale=en_US');
  });

  test('acha o botão de verificação (português, link de rastreio)', () {
    expect(extractVerificationLink(_htmlPt), startsWith('https://www.amazon.com.br/gp/f.html?C=XYZ&R=1'));
  });

  test('ignora links que não são da Amazon ou são de rodapé', () {
    const html = '<a href="https://evil.example.com/verify">Verify</a><a href="https://www.amazon.com/privacy">Verify privacy</a>';
    expect(extractVerificationLink(html), isNull);
  });

  test('link só no texto simples', () {
    expect(extractVerificationLink('', 'Clique: https://www.amazon.com/sendtokindle/verify?t=1 para confirmar'),
        'https://www.amazon.com/sendtokindle/verify?t=1');
  });

  test('reconhece o e-mail de confirmação e não outros da Amazon', () {
    expect(looksLikeVerification('Verify your Send to Kindle request', ''), isTrue);
    expect(looksLikeVerification('Verifique sua solicitação', 'Enviar para Kindle'), isTrue);
    expect(looksLikeVerification('Seu pedido foi enviado', 'Rastreie seu pacote'), isFalse);
  });

  test('funciona com um e-mail completo (MIME, quoted-printable)', () {
    const raw = 'From: "Amazon Kindle" <do-not-reply@amazon.com>\r\n'
        'Subject: =?UTF-8?Q?Verifique_sua_solicita=C3=A7=C3=A3o_de_Enviar_para_Kindle?=\r\n'
        'Date: Fri, 13 Nov 2026 12:30:00 +0000\r\n'
        'MIME-Version: 1.0\r\n'
        'Content-Type: text/html; charset=UTF-8\r\n'
        'Content-Transfer-Encoding: quoted-printable\r\n'
        '\r\n'
        '<p>Confirme o envio para o Kindle.</p><a href=3D"https://www.amazon.com.br/sendtokindle/ve=\r\n'
        'rify?token=3DQ1">Verificar solicita=C3=A7=C3=A3o</a>\r\n';
    final m = MimeMessage.parseFromText(raw);
    final html = m.decodeTextHtmlPart()!;
    expect(looksLikeVerification(m.decodeSubject()!, html), isTrue);
    expect(extractVerificationLink(html), 'https://www.amazon.com.br/sendtokindle/verify?token=Q1');
  });
}
