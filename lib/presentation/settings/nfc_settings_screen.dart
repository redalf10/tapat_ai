import 'package:flutter/material.dart';
import '../../const/app_common.dart';
import '../../core/services/nfc_servide.dart';
import '../../provider/app_provider.dart';

class NfcSettingsScreen extends StatefulWidget {
  const NfcSettingsScreen({super.key});

  @override
  State<NfcSettingsScreen> createState() => _NfcSettingsScreenState();
}

class _NfcSettingsScreenState extends State<NfcSettingsScreen> {
  bool? _available;
  bool _busy = false;
  String? _result;
  late final NfcService _nfc;

  @override
  void initState() {
    super.initState();
    _nfc = AppState.read(context).nfc;
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final available = await _nfc.isAvailable();
      if (mounted) { setState(() => _available = available); }
  }

  Future<void> _testRead() async {
    setState(() { _busy = true; _result = 'Hold a tag near your phone…'; });
    try {
      final topicId = await _nfc.scan();
      if (mounted) {
        setState(() => _result = topicId == null
            ? 'No Tapat topic record was read.' : 'Read topic ID: $topicId');
      }
    } catch (e) {
      if (mounted) setState(() => _result = 'NFC read failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _eraseTag() async {
    final confirm = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Erase NFC tag?'),
      content: const Text('This clears the NDEF data from the next writable tag you scan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
      ],
    ));
    if (confirm != true || !mounted) return;
    setState(() { _busy = true; _result = 'Hold a writable tag near your phone…'; });
    try {
      final erased = await _nfc.erase();
      if (mounted) setState(() => _result = erased ? 'NFC tag erased.' : 'Tag erase was cancelled.');
    } catch (e) {
      if (mounted) setState(() => _result = 'Could not erase tag: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (_busy) _nfc.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    return Scaffold(
      appBar: AppBar(title: const Text('NFC Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(available == null ? 'Checking NFC…' : available ? 'NFC is ready' : 'NFC is unavailable',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text(available == false
              ? 'This device may not have NFC hardware, or NFC may be turned off. Enable NFC in your device settings and try again.'
              : 'Use the tools below to test reading a tag or clear data from a writable tag.'),
          if (available == false) Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: _checkAvailability,
            icon: const Icon(Icons.refresh), label: const Text('Check again'))),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(children: [
          ListTile(leading: const Icon(Icons.nfc), title: const Text('Test NFC read'),
            subtitle: const Text('Scan a tag and display its Tapat topic ID'),
            enabled: available == true && !_busy, onTap: available == true && !_busy ? _testRead : null),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.cleaning_services_outlined), title: const Text('Format / erase tag'),
            subtitle: const Text('Write an empty NDEF message to a tag'),
            enabled: available == true && !_busy, onTap: available == true && !_busy ? _eraseTag : null),
        ])),
        if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (_result case final result?) Padding(padding: const EdgeInsets.all(16), child: Text(result)),
      ]),
    );
  }
}
