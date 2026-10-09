import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/const/app_theme.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class TapatApp extends StatefulWidget {
  const TapatApp({super.key, required this.state});
  final AppState state;

  @override
  State<TapatApp> createState() => _TapatAppState();
}

class _TapatAppState extends State<TapatApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _routes = _TopRouteObserver();
  StreamSubscription<ChatNotice>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = widget.state.chatNotices.listen(_showNotice);
  }

  @override
  void didUpdateWidget(TapatApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _notices?.cancel();
      _notices = widget.state.chatNotices.listen(_showNotice);
    }
  }

  void _showNotice(ChatNotice notice) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.state.topics.any((topic) => topic.id == notice.topicId)) return;
      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      messenger.showMaterialBanner(MaterialBanner(
        leading: Icon(notice.error == null ? Icons.notifications_active_outlined : Icons.error_outline),
        content: Text(notice.error == null
            ? 'Your answer for ${notice.topicName} is ready.'
            : 'Could not answer in ${notice.topicName}: ${notice.error}'),
        actions: [
          TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Dismiss')),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              if (!widget.state.topics.any((topic) => topic.id == notice.topicId)) return;
              final route = _routes.currentRoute;
              if (route?.settings.name == Routes.chat && route?.settings.arguments == notice.topicId) return;
              _navigatorKey.currentState?.pushNamed(Routes.chat, arguments: notice.topicId);
            },
            child: Text(notice.error == null ? 'View answer' : 'Open chat'),
          ),
        ],
      ));
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
        notifier: widget.state,
        child: ListenableBuilder(
          listenable: widget.state,
          builder: (_, _) => MaterialApp(
            title: 'Tapat AI',
            navigatorKey: _navigatorKey,
            scaffoldMessengerKey: _messengerKey,
            navigatorObservers: [_routes],
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: widget.state.themeMode,
            initialRoute: Routes.splash,
            onGenerateRoute: AppRouter.generate,
          ),
        ),
      );
}

class _TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? currentRoute;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    currentRoute = topRoute;
  }
}
