import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/actions.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _themeNames = {ThemeMode.light: 'Light', ThemeMode.dark: 'Dark', ThemeMode.system: 'System'};

  Future<void> _themeDialog(BuildContext c, AppState s) => showDialog(
        context: c,
        builder: (_) => SimpleDialog(title: const Text('App Appearance'), children: [
          for (final m in ThemeMode.values)
            ListTile(
              title: Text(_themeNames[m]!),
              trailing: s.themeMode == m ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { s.setTheme(m); Navigator.pop(c); },
            ),
        ]),
      );

  Future<bool> _confirm(BuildContext c, String title, String body) async =>
      await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(title: Text(title), content: Text(body), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ]),
      ) ?? false;

  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _Group([
          _Item(Icons.memory, 'Local AI Models', 'Manage LLM and embedding models',
              () => snack(context, 'Plug your local LLM / embedding models in data/services.dart')),
          _Item(Icons.storage_outlined, 'Storage Usage', '${s.storageGb.toStringAsFixed(1)} GB used',
              () => snack(context, '${s.topics.length} knowledge bases · ${s.totalDocs} documents')),
          _Item(Icons.nfc, 'NFC Settings', 'Read / Write NFC tags', () => Navigator.pushNamed(context, Routes.nfcScan)),
          _Item(Icons.light_mode_outlined, 'App Appearance', '${_themeNames[s.themeMode]}', () => _themeDialog(context, s)),
          _Item(Icons.folder_outlined, 'Data Management', 'Export, Backup, Delete', () async {
            if (await _confirm(context, 'Clear chat history?', 'All conversations will be deleted.')) {
              s.clearChats();
              if (context.mounted) snack(context, 'Chat history cleared');
            }
          }),
        ]),
        const SizedBox(height: 16),
        _Group([
          _Item(Icons.info_outline, 'About', 'Tapat AI · Version 1.0.0', () => showAboutDialog(
              context: context, applicationName: 'Tapat AI', applicationVersion: '1.0.0',
              applicationIcon: const BrandLogo(size: 40),
              children: const [Text('Local RAG AI with NFC. Your knowledge. On your device.')])),
          _Item(Icons.help_outline, 'Help & Support', null, () => snack(context, 'support@tapat.ai')),
          _Item(Icons.shield_outlined, 'Privacy', 'All data stays on your device', () => snack(context, 'Tapat AI never uploads your documents.')),
          _Item(Icons.power_settings_new, 'Reset App', null, () async {
            if (await _confirm(context, 'Reset Tapat AI?', 'This restores defaults and replays onboarding.')) {
              await s.resetApp();
              if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.splash, (_) => false);
            }
          }, danger: true),
        ]),
      ]),
    );
  }
}

class _Item {
  const _Item(this.icon, this.title, this.sub, this.onTap, {this.danger = false});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final bool danger;
}

class _Group extends StatelessWidget {
  const _Group(this.items);
  final List<_Item> items;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              leading: Icon(items[i].icon, color: items[i].danger ? Colors.red : null),
              title: Text(items[i].title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: items[i].danger ? Colors.red : null)),
              subtitle: items[i].sub == null ? null : Text(items[i].sub!, style: const TextStyle(fontSize: 12)),
              trailing: items[i].danger ? null : const Icon(Icons.chevron_right, size: 20),
              onTap: items[i].onTap,
            ),
            if (i < items.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ]),
      );
}