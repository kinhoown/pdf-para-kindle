# PDF para Kindle

App Android que transforma um PDF em livro do Kindle (EPUB), coloca a capa e envia para o seu Kindle.

## Baixar
**[⬇ Baixar o APK (Android)](https://github.com/kinhoown/pdf-para-kindle/releases/latest/download/PDF-para-Kindle.apk)**

## Instalar
1. Abra o link acima no celular e toque no arquivo baixado.
2. Permita "instalar apps desconhecidos" quando o Android pedir.

## Configurar (uma vez só)
1. **E-mail do Kindle**: amazon.com.br → Conta → Conteúdo e dispositivos → Preferências →
   Configurações de documentos pessoais. Copie o endereço `@kindle.com`.
2. Na mesma página, em **Lista de e-mails aprovados**, adicione o seu Gmail.
3. **Senha de app do Google**: https://myaccount.google.com/apppasswords
   (precisa da verificação em 2 etapas ligada). Use essa senha de 16 letras no app, não a senha normal.

## Usar
- Toque em **Escolher PDF**, ou
- Em qualquer app (Arquivos, WhatsApp, Drive…) toque em **Compartilhar → PDF para Kindle**.

O app detecta a capa, gera o livro e envia sozinho. Em alguns minutos ele aparece no Kindle com a capa.
Se a capa escolhida estiver errada, toque em **Capa errada? Escolher outra e reenviar**.

Depois do envio, o app pergunta se você quer **apagar o PDF do celular**. Se o PDF veio compartilhado por outro app,
o Android pede um toque a mais: escolher o PDF de novo para confirmar.

## Como funciona
- `lib/converter/pdf_analyzer.dart` – lê o texto e analisa as primeiras páginas para achar a capa
  (página com ilustração/cor e pouco texto; ignora páginas em branco).
- `lib/converter/pdf_to_epub.dart` – monta parágrafos, títulos e capítulos, remove cabeçalhos e números
  de página e recorta figuras. PDFs escaneados ou quadrinhos viram páginas em imagem.
- `lib/converter/epub_builder.dart` – gera o EPUB com a capa marcada para o Kindle.
- `lib/services/kindle_sender.dart` – envia por e-mail (SMTP do Gmail).

## Desenvolvimento
```
flutter build apk --release --split-per-abi
dart run tool/convert_cli.dart arquivo.pdf saida   # testa a conversão no PC
```
