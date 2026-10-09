import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/actions.dart';
import 'package:tapat_ai/provider/app_provider.dart';
import 'package:tapat_ai/data/repositories.dart';
import 'package:tapat_ai/data/backup_service.dart';
import 'package:tapat_ai/presentation/settings/nfc_settings_screen.dart';

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
              () => Navigator.pushNamed(context, Routes.models)),
          _Item(Icons.image_outlined, 'Image Generation', s.imageConfig.enabled ? 'Illustration service enabled · Diagrams stay local' : 'Local diagrams · Optional illustration service',
              () => Navigator.pushNamed(context, Routes.images)),
          _Item(Icons.storage_outlined, 'Storage Usage', '${s.storageGb.toStringAsFixed(1)} GB used',
              () => _storageDialog(context, s)),
          _Item(Icons.nfc, 'NFC Settings', 'Availability, test read, format / erase', () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const NfcSettingsScreen()))),
          _Item(Icons.light_mode_outlined, 'App Appearance', '${_themeNames[s.themeMode]}', () => _themeDialog(context, s)),
          _Item(Icons.folder_outlined, 'Data Management', 'Export, Backup, Delete', () async {
            await _dataManagement(context, s);
          }),
        ]),
        const SizedBox(height: 16),
        _Group([
          _Item(Icons.info_outline, 'About', 'Tapat AI · Version 1.0.0', () => showAboutDialog(
              context: context, applicationName: 'Tapat AI', applicationVersion: '1.0.0',
              applicationIcon: const BrandLogo(size: 40),
              children: const [Text('Local RAG AI with NFC. Your knowledge. On your device.')])),
          _Item(Icons.help_outline, 'Help & Support', null, () => snack(context, 'support@tapat.ai')),
          _Item(Icons.shield_outlined, 'Privacy', 'Local text and document search', () => snack(context,
              'Text generation, documents and search stay on this device. If enabled, illustration prompts are sent to your configured image server and may reflect chat or document content.')),
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

  Future<void> _storageDialog(BuildContext context, AppState state) async {
    final documents = state.repositories.documents.getAll();
    final models = state.repositories.models.getAll();
    final dbDir = Directory(state.repositories.store.store.directoryPath);
    var databaseBytes = 0;
    if (dbDir.existsSync()) {
      for (final entity in dbDir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) databaseBytes += entity.lengthSync();
      }
    }
    String size(int bytes) => bytes > 1073741824
        ? '${(bytes / 1073741824).toStringAsFixed(2)} GB'
        : '${(bytes / 1048576).toStringAsFixed(1)} MB';
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Storage Usage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Local AI models'), trailing: Text(size(models.fold<int>(0, (n, m) => n + m.sizeBytes)))),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Documents'), trailing: Text(size(documents.fold<int>(0, (n, d) => n + d.sizeBytes)))),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('ObjectBox database'), trailing: Text(size(databaseBytes))),
          const Divider(),
          for (final topic in state.topics)
            ListTile(contentPadding: EdgeInsets.zero, title: Text(topic.name), subtitle: Text(topic.stats),
              trailing: Text(size(topic.docs.fold<int>(0, (n, d) => n + (d.sizeMb * 1048576).round())))),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear cache'), onPressed: () async {
              final modelDir = await LocalFiles.modelsDirectory();
              for (final file in modelDir.listSync().whereType<File>().where((f) => f.path.endsWith('.part'))) { await file.delete(); }
              final temporary = await getTemporaryDirectory();
              for (final file in temporary.listSync().whereType<File>()) { await file.delete(); }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (context.mounted) snack(context, 'Temporary files cleared.');
            })),
        ],
      ))));
  }

  Future<void> _dataManagement(BuildContext context, AppState state) async {
    final action = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Data Management')),
        ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Export backup'),
          subtitle: const Text('Topics, chats, document text and local files'), onTap: () => Navigator.pop(context, 'export')),
        ListTile(leading: const Icon(Icons.unarchive_outlined), title: const Text('Import backup'),
          onTap: () => Navigator.pop(context, 'import')),
        ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Clear chat history'),
          onTap: () => Navigator.pop(context, 'clearChats')),
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete all app data'),
          onTap: () => Navigator.pop(context, 'reset')),
      ])));
    if (!context.mounted || action == null) return;
    try {
      if (action == 'export') {
        await BackupService(state.repositories).exportBackup();
        if (!context.mounted) return;
        snack(context, 'Backup exported.');
      } else if (action == 'import') {
        if (!await _confirm(context, 'Import backup?', 'This replaces the current knowledge bases and chat history.')) return;
        await BackupService(state.repositories).importBackup();
        state.refreshFromStorage();
        if (!context.mounted) return;
        snack(context, 'Backup imported.');
      } else if (action == 'clearChats') {
        if (!await _confirm(context, 'Clear chat history?', 'All conversations will be deleted.')) return;
        state.clearChats();
        if (!context.mounted) return;
        snack(context, 'Chat history cleared.');
      } else if (action == 'reset') {
        if (!await _confirm(context, 'Reset Tapat AI?', 'This deletes all topics, documents, chats and downloaded models.')) return;
        await state.resetApp();
        if (!context.mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, Routes.splash, (_) => false);
      }
    } catch (e) { if (context.mounted) snack(context, 'Data operation failed: $e'); }
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
