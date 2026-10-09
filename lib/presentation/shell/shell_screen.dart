import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
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
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _i, children: [
          HomeTab(onSeeAll: () => setState(() => _i = 1)),
          const KnowledgeBasesScreen(embedded: true),
          const ChatPickerTab(),
          const NfcHubTab(),
          const SettingsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Knowledge'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.nfc), label: 'NFC'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(this.title, this.sub, this.icon, this.colors, this.onTap);
  final String title, sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 150,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: Colors.white)),
              const Spacer(),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ),
      );
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
          const CircleAvatar(radius: 16, backgroundColor: AppColors.blue, child: Icon(Icons.person, size: 18, color: Colors.white)),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          _ActionCard('Scan NFC', 'Open a knowledge base by tapping an NFC tag.', Icons.sensors,
              const [Color(0xFF2563EB), Color(0xFF3B82F6)], () => Navigator.pushNamed(context, Routes.nfcScan)),
          const SizedBox(width: 12),
          _ActionCard('Upload Document', 'Add new documents to your knowledge base.', Icons.upload_file,
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
      appBar: AppBar(title: const Text('Knowledge Bases'), automaticallyImplyLeading: !embedded),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => Navigator.pushNamed(context, Routes.create),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: s.setQuery,
            decoration: const InputDecoration(
                hintText: 'Search knowledge bases...', prefixIcon: Icon(Icons.search, size: 20)),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final c in AppState.categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  selected: s.filter == c,
                  onSelected: (_) => s.setFilter(c),
                  selectedColor: AppColors.blue,
                  labelStyle: TextStyle(color: s.filter == c ? Colors.white : null),
                  showCheckmark: false,
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
      appBar: AppBar(title: const Text('Chat')),
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
      appBar: AppBar(title: const Text('NFC')),
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