import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_glass.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/presentation/settings/settings_screen.dart';
import 'package:tapat_ai/provider/actions.dart';
import 'package:tapat_ai/provider/app_provider.dart';
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellState();
}

class _ShellState extends State<ShellScreen> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final nfcEnabled = AppState.of(context).nfcEnabled;
    final destinations = <GlassNavDestination>[
      const GlassNavDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
      const GlassNavDestination(icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book, label: 'Knowledge'),
      const GlassNavDestination(icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble, label: 'Chat'),
      if (nfcEnabled) const GlassNavDestination(icon: Icons.nfc, selectedIcon: Icons.nfc, label: 'NFC'),
      const GlassNavDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
    ];
    final selectedIndex = _i.clamp(0, destinations.length - 1);
    return Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(index: selectedIndex, children: [
          HomeTab(onSeeAll: () => setState(() => _i = 1)),
          const KnowledgeBasesScreen(embedded: true),
          const ChatPickerTab(),
          if (nfcEnabled) const NfcHubTab(),
          const SettingsScreen(),
        ]),
        bottomNavigationBar: GlassNavigationBar(
          selectedIndex: selectedIndex,
          onSelected: (v) => setState(() => _i = v),
          destinations: destinations,
        ),
      );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(this.title, this.sub, this.icon, this.colors, this.onTap);
  final String title, sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: SizedBox(
        height: 150,
        child: GlassSurface(
          radius: 20,
          blur: Glass.blur,
          fill: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.first.withValues(alpha: dark ? .30 : .34),
              colors.last.withValues(alpha: dark ? .18 : .20),
            ],
          ),
          onTap: onTap,
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
                  colors: [
                    colors.first.withValues(alpha: .92),
                    colors.last.withValues(alpha: .85),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const Spacer(),
              Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;
  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final recent = s.topics.take(3).toList();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Hello!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              Text('Your local AI is ready', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.pushNamed(context, Routes.knowledge)),
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
          if (s.nfcEnabled) ...[
            _ActionCard('Scan NFC', 'Open a knowledge base by tapping an NFC tag.', Icons.sensors,
                const [Color(0xFF2563EB), Color(0xFF3B82F6)], () => Navigator.pushNamed(context, Routes.nfcScan)),
            const SizedBox(width: 12),
          ],
          _ActionCard('Add Document', 'Upload or create documents in your knowledge base.', Icons.note_add_outlined,
              const [Color(0xFF7C3AED), Color(0xFF9F67FF)], () => pickTopicAndUpload(context)),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(child: Text('Recent Knowledge Bases', style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: onSeeAll, child: const Text('See All')),
        ]),
        if (recent.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No knowledge bases yet.'))),
        for (final t in recent)
          TopicTile(t, onTap: () => Navigator.pushNamed(context, Routes.detail, arguments: t.id)),
      ]),
    );
  }
}

class KnowledgeBasesScreen extends StatelessWidget {
  const KnowledgeBasesScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final list = s.filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        appBar: AppBar(title: const Text('Knowledge Bases'), automaticallyImplyLeading: !embedded),
      ),
      floatingActionButton: GlassFab(
        icon: Icons.add,
        tooltip: 'New knowledge base',
        onPressed: () => Navigator.pushNamed(context, Routes.create),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: GlassTextField(
            hintText: 'Search knowledge bases...',
            prefixIcon: const Icon(Icons.search, size: 20),
            onChanged: s.setQuery,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final c in AppState.categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GlassChip(
                  label: c,
                  selected: s.filter == c,
                  onTap: () => s.setFilter(c),
                ),
              ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No matching knowledge bases'))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
                  for (final t in list)
                    TopicTile(t, onTap: () => Navigator.pushNamed(context, Routes.detail, arguments: t.id)),
                ]),
        ),
      ]),
    );
  }
}

class ChatPickerTab extends StatelessWidget {
  const ChatPickerTab({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(appBar: AppBar(title: const Text('Chat'))),
      body: s.topics.isEmpty
          ? const Center(child: Text('Create a knowledge base to start chatting.'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Padding(
                  padding: EdgeInsets.only(bottom: 12), child: Text('Choose a knowledge base to ask:')),
              for (final t in s.topics)
                TopicTile(t, onTap: () => Navigator.pushNamed(context, Routes.chat, arguments: t.id)),
            ]),
    );
  }
}

class NfcHubTab extends StatelessWidget {
  const NfcHubTab({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(appBar: AppBar(title: const Text('NFC'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Ripple(size: 200, child: const Icon(Icons.nfc, size: 56, color: AppColors.blue))),
        const SizedBox(height: 16),
        GradientButton(label: 'Scan NFC Tag', icon: Icons.sensors, onPressed: () => Navigator.pushNamed(context, Routes.nfcScan)),
        const SizedBox(height: 24),
        const Text('Link a tag to a knowledge base', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final t in s.topics)
          TopicTile(t, onTap: () => Navigator.pushNamed(context, Routes.nfcWrite, arguments: t.id)),
      ]),
    );
  }
}
