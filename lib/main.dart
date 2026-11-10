import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'services/reminders.dart';
import 'services/speech.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  Tts.rate = state.ttsRate;
  runApp(PolyglotteApp(state: state));
  // Reprogramme le rappel au démarrage (sans bloquer l'affichage).
  if (state.reminderOn) {
    Reminders.schedule(
        enabled: true, hour: state.reminderHour, minute: state.reminderMinute);
  }
}

class PolyglotteApp extends StatelessWidget {
  final AppState state;
  const PolyglotteApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFD84315);
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Polyglotte',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
