import 'package:flutter/material.dart';

import 'app.dart';
import 'database/app_database.dart';
import 'auth/auth_service.dart';
import 'auth/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final auth = AuthService(database);
  final hasAccounts = await auth.hasAccounts();
  runApp(
    OutreachApp(session: SessionController(auth), hasAccounts: hasAccounts),
  );
}
