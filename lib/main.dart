import 'package:flutter/material.dart';
import 'screens/home_shell.dart';
import 'data/app_data.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtrilApp());
}

class AtrilApp extends StatelessWidget {
  const AtrilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: AppData.init(),
      builder: (context, snapshot) {
        // Minimal bootstrap UI. If init fails, surface it clearly.
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error inicializando la app:\n\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true),
            home: const Scaffold(
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
