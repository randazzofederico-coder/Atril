import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/home_shell.dart';
import 'data/app_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (same pattern as Metrónomo & Afinador)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const AtrilApp());
}

class AtrilApp extends StatelessWidget {
  const AtrilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: AppData.init(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              backgroundColor: const Color(0xFF121218),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error inicializando la app:\n\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true),
            home: const Scaffold(
              backgroundColor: Color(0xFF121218),
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return AnimatedBuilder(
          animation: Listenable.merge([
            AppData.settings.themeMode,
            AppData.settings.uiScale,
          ]),
          builder: (context, _) {
            final scale = AppData.settings.uiScale.value;
            return MaterialApp(
              title: 'Atril',
              debugShowCheckedModeBanner: false,
              themeMode: AppData.settings.themeMode.value,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
              ),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                );
              },
              home: const HomeShell(),
            );
          },
        );
      },
    );
  }
}
