import 'package:flutter/material.dart';

import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.firstRun = false});
  final AppSettings settings;
  final bool firstRun;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _kindle = TextEditingController(text: widget.settings.kindleEmail);
  late final _sender = TextEditingController(text: widget.settings.senderEmail);
  late final _pass = TextEditingController(text: widget.settings.appPassword);
  late final _host = TextEditingController(text: widget.settings.smtpHost);
  late final _port = TextEditingController(text: widget.settings.smtpPort.toString());
  bool _showPass = false;
  bool _advanced = false;

  Future<void> _save() async {
    final s = widget.settings
      ..kindleEmail = _kindle.text
      ..senderEmail = _sender.text
      ..appPassword = _pass.text
      ..smtpHost = _host.text.isEmpty ? 'smtp.gmail.com' : _host.text
      ..smtpPort = int.tryParse(_port.text) ?? 587;
    if (!s.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os três campos.')));
      return;
    }
    await s.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar envio')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.firstRun)
            Text('Só precisa fazer isso uma vez.', style: t.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _kindle,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail do seu Kindle',
              hintText: 'seunome_xyz@kindle.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sender,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Seu Gmail (remetente)',
              hintText: 'voce@gmail.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pass,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: 'Senha de app do Google (16 letras)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _advanced = !_advanced),
            child: Text(_advanced ? 'Ocultar servidor de e-mail' : 'Não uso Gmail (servidor de e-mail)'),
          ),
          if (_advanced) ...[
            TextField(controller: _host, decoration: const InputDecoration(labelText: 'Servidor SMTP', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Porta (587 ou 465)', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Salvar')),
          const SizedBox(height: 28),
          Text('Como preencher', style: t.titleMedium),
          const SizedBox(height: 8),
          const _Step(n: 1, text: 'E-mail do Kindle: na Amazon, vá em Conta > Conteúdo e dispositivos > Preferências > '
              'Configurações de documentos pessoais. Lá aparece o endereço @kindle.com.'),
          const _Step(n: 2, text: 'Na mesma página, em "Lista de e-mails aprovados", adicione o seu Gmail. '
              'Sem isso a Amazon descarta o arquivo.'),
          const _Step(n: 3, text: 'Senha de app: em myaccount.google.com/apppasswords crie uma senha '
              '(precisa ter verificação em 2 etapas ligada). Cole aqui os 16 caracteres. '
              'Não é a senha normal do Gmail.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 11, child: Text('$n', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}
