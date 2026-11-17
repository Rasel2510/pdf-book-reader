import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/db.dart';
import 'core/preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_Bootstrap(preferences: SharedPreferences.getInstance()));
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.preferences});

  final Future<SharedPreferences> preferences;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppDb.instance.then<void>((_) {}, onError: (Object _) {}));
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedPreferences>(
    future: widget.preferences,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return MaterialApp(
          theme: AppTheme.current,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to start Paperleaf Reader:\n${snapshot.error}',
                ),
              ),
            ),
          ),
        );
      }

      final prefs = snapshot.data;
      if (prefs == null) return const _SplashScreen();

      return ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const App(),
      );
    },
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.current,
    home: Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/book_icon.png',
              width: 168,
              height: 168,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            Text(
              'Paperleaf Reader',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
