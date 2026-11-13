import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_kindle/services/kindle_sender.dart';

void main() {
  test('nome do anexo sem acentos', () {
    expect(asciiFileName('Memórias Póstumas de Brás Cubas'), 'Memorias Postumas de Bras Cubas');
    expect(asciiFileName('Ação: Volume 2'), 'Acao - Volume 2');
    expect(asciiFileName('日本語'), 'livro');
  });
}
