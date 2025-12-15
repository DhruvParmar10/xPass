import 'package:flutter/material.dart'
    hide ThemeMode, ThemeData, Scaffold, CircularProgressIndicator;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('theme_mode');

      if (mounted) {
        setState(() {
          if (savedTheme == 'dark') {
            _themeMode = ThemeMode.dark;
          } else if (savedTheme == 'light') {
            _themeMode = ThemeMode.light;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading theme preference: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleTheme() async {
    final newThemeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;

    setState(() {
      _themeMode = newThemeMode;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'theme_mode',
        newThemeMode == ThemeMode.dark ? 'dark' : 'light',
      );
      print(
        'Theme preference saved: ${newThemeMode == ThemeMode.dark ? 'dark' : 'light'}',
      );
    } catch (e) {
      print('Error saving theme preference: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while theme preference is being loaded
    if (_isLoading) {
      return ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorSchemes.defaultcolor(ThemeMode.light),
          radius: 0.5,
        ),
        home: const Scaffold(child: Center(child: CircularProgressIndicator())),
      );
    }

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
      home: HomeScreen(
        onThemeToggle: _toggleTheme,
        currentThemeMode: _themeMode,
      ),
    );
  }
}
