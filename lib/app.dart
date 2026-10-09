import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/const/app_theme.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class TapatApp extends StatelessWidget {
  const TapatApp({super.key, required this.state});
  final AppState state;
 
  @override
  Widget build(BuildContext context) => AppScope(
        notifier: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (_, _) => MaterialApp(
            title: 'Tapat AI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: state.themeMode,
            initialRoute: Routes.splash,
            onGenerateRoute: AppRouter.generate,
          ),
        ),
      );
}