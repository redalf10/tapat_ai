import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_glass.dart';
import 'package:tapat_ai/const/app_theme.dart';
import 'package:tapat_ai/data/entities/mock_data.dart';

/// Roboto and the Material icon font ship with the Flutter SDK. Loading them
/// makes the previews show real glyphs instead of the test placeholder font.
String? _findFontDir() {
  final candidates = [
    if (Platform.environment['FLUTTER_ROOT'] != null)
      '${Platform.environment['FLUTTER_ROOT']}'
          r'\bin\cache\artifacts\material_fonts',
    r'C:\Users\Windows\AppData\Local\Programs\flutter'
        r'\bin\cache\artifacts\material_fonts',
    r'/usr/local/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final dir in candidates) {
    if (Directory(dir).existsSync()) return dir;
  }
  return null;
}

Future<void> _loadFont(String dir, String family, String file) async {
  final bytes = await File('$dir\\$file').readAsBytes();
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  await (FontLoader(family)..addFont(Future.value(data))).load();
}

Future<void> _loadFonts(String dir) async {
  for (final family in ['Roboto', 'FlutterTest', 'Ahem']) {
    await _loadFont(dir, family, 'roboto-regular.ttf');
    await _loadFont(dir, family, 'roboto-medium.ttf');
    await _loadFont(dir, family, 'roboto-bold.ttf');
  }
  await _loadFont(dir, 'MaterialIcons', 'materialicons-regular.otf');
}

ThemeData _themed(Brightness brightness) {
  final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
  );
}

Widget _host(Brightness brightness, Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _themed(brightness),
      builder: (context, c) => GlassBackground(child: c!),
      home: child,
    );

Widget _homePreview(BuildContext context) {
  final topics = MockData.topics();
  final hint = Theme.of(context).colorScheme.onSurfaceVariant;
  Widget actionCard(String title, String sub, IconData icon, Color a, Color b) =>
      Expanded(
        child: SizedBox(
          height: 150,
          child: GlassSurface(
            radius: 20,
            blur: Glass.blur,
            fill: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a.withValues(alpha: .34), b.withValues(alpha: .20)],
            ),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GlassSurface(
                  radius: 12,
                  blur: Glass.blurSoft,
                  shadow: false,
                  padding: const EdgeInsets.all(8),
                  fill: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [a.withValues(alpha: .92), b.withValues(alpha: .85)],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(color: hint, fontSize: 11)),
              ]),
            ),
          ),
        ),
      );

  return Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Hello!',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              Text('Your local AI is ready',
                  style: TextStyle(
                      color: Theme.of(context).hintColor, fontSize: 12)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          GlassSurface(
            radius: 18,
            blur: Glass.blurSoft,
            shadow: false,
            padding: const EdgeInsets.all(9),
            child: const Icon(Icons.person, size: 18, color: AppColors.blue),
          ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          actionCard('Scan NFC', 'Open a knowledge base by tapping an NFC tag.',
              Icons.sensors, const Color(0xFF2563EB), const Color(0xFF3B82F6)),
          const SizedBox(width: 12),
          actionCard('Upload Document', 'Add new documents to your knowledge base.',
              Icons.upload_file, const Color(0xFF7C3AED), const Color(0xFF9F67FF)),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(
              child: Text('Recent Knowledge Bases',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: () {}, child: const Text('See All')),
        ]),
        for (final t in topics.take(3)) TopicTile(t, onTap: () {}),
      ]),
    ),
    bottomNavigationBar: GlassNavigationBar(
      selectedIndex: 0,
      onSelected: (_) {},
      destinations: const [
        GlassNavDestination(
            icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        GlassNavDestination(
            icon: Icons.menu_book_outlined,
            selectedIcon: Icons.menu_book,
            label: 'Knowledge'),
        GlassNavDestination(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'Chat'),
        GlassNavDestination(icon: Icons.nfc, selectedIcon: Icons.nfc, label: 'NFC'),
        GlassNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings'),
      ],
    ),
  );
}

Widget _knowledgePreview(BuildContext context) {
  final topics = MockData.topics();
  return Scaffold(
    backgroundColor: Colors.transparent,
    appBar: GlassAppBar(appBar: AppBar(title: const Text('Knowledge Bases'))),
    body: Column(children: [
      const SizedBox(height: 4),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: GlassTextField(
            hintText: 'Search knowledge bases...',
            prefixIcon: Icon(Icons.search, size: 20)),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final c in ['All', 'Education', 'Work', 'Personal'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GlassChip(
                    label: c, selected: c == 'All', onTap: () {}),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final t in topics) TopicTile(t, onTap: () {}),
            ]),
      ),
    ]),
    floatingActionButton: GlassFab(icon: Icons.add, onPressed: () {}),
  );
}

/// Writes the rendered frame to a PNG next to the test.
Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final fontDir = _findFontDir();
  if (fontDir == null) {
    test('preview fonts unavailable', () {}, skip: 'Flutter SDK fonts not found');
    return;
  }

  setUpAll(() => _loadFonts(fontDir));

  Future<void> preview(
    WidgetTester tester, {
    required Brightness brightness,
    required Widget Function(BuildContext) build,
    required String name,
  }) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key, child: _host(brightness, Builder(builder: build))));
    await tester.pumpAndSettle();
    await tester.runAsync(() =>
        _capture(tester, key, 'test/goldens/$name.png'));
  }

  testWidgets('home preview (light)', (tester) async {
    await preview(tester,
        brightness: Brightness.light,
        build: _homePreview,
        name: 'preview_home_light');
  });

  testWidgets('home preview (dark)', (tester) async {
    await preview(tester,
        brightness: Brightness.dark,
        build: _homePreview,
        name: 'preview_home_dark');
  });

  testWidgets('knowledge preview (light)', (tester) async {
    await preview(tester,
        brightness: Brightness.light,
        build: _knowledgePreview,
        name: 'preview_knowledge_light');
  });
}
