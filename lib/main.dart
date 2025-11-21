import 'package:flutter/material.dart' hide ThemeMode, ThemeData;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PasswordManagerApp());
}

class PasswordManagerApp extends StatefulWidget {
  const PasswordManagerApp({super.key});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'xPass',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorSchemes.defaultcolor(ThemeMode.light),
        radius: 0.5,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorSchemes.defaultcolor(ThemeMode.dark),
        radius: 0.5,
      ),
      debugShowCheckedModeBanner: false,
      home: HomeScreen(onThemeToggle: _toggleTheme, currentThemeMode: _themeMode),
    );
  }
}
