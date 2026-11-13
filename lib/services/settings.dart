import 'package:shared_preferences/shared_preferences.dart';

/// Configurações de envio, guardadas no armazenamento privado do app.
class AppSettings {
  AppSettings({
    this.kindleEmail = '',
    this.senderEmail = '',
    this.appPassword = '',
    this.smtpHost = 'smtp.gmail.com',
    this.smtpPort = 587,
  });

  String kindleEmail;
  String senderEmail;
  String appPassword;
  String smtpHost;
  int smtpPort;

  bool get isComplete =>
      kindleEmail.contains('@') && senderEmail.contains('@') && appPassword.isNotEmpty && smtpHost.isNotEmpty;

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      kindleEmail: p.getString('kindleEmail') ?? '',
      senderEmail: p.getString('senderEmail') ?? '',
      appPassword: p.getString('appPassword') ?? '',
      smtpHost: p.getString('smtpHost') ?? 'smtp.gmail.com',
      smtpPort: p.getInt('smtpPort') ?? 587,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('kindleEmail', kindleEmail.trim());
    await p.setString('senderEmail', senderEmail.trim());
    await p.setString('appPassword', appPassword.replaceAll(' ', ''));
    await p.setString('smtpHost', smtpHost.trim());
    await p.setInt('smtpPort', smtpPort);
  }
}
