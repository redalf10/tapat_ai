import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/actions.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class NfcScanScreen extends StatefulWidget {
  const NfcScanScreen({super.key});
  @override
  State<NfcScanScreen> createState() => _NfcScanState();
}

class _NfcScanState extends State<NfcScanScreen> {
  late final AppState _s = AppState.read(context);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _s.nfc.isAvailable()) {
      if (mounted) {
        snack(context, 'NFC is not available on this device');
        Navigator.pop(context);
      }
      return;
    }
    final id = await _s.nfc.scan();
    if (!mounted || id == null) return;
    final t = _s.byNfcId(id);
    if (t == null) {
      snack(context, 'No knowledge base found for this tag');
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, Routes.nfcDetected, arguments: t.id);
    }
  }

  @override
  void dispose() { _s.nfc.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => DarkScaffold(
        child: Column(children: [
          const SizedBox(height: 16),
          const Text('Scan NFC Tag', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          const Text('Hold your phone near the\nknowledge base NFC tag.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
          const Spacer(),
          Ripple(size: 280, child: const Icon(Icons.phone_android, size: 72, color: Colors.white)),
          const Spacer(),
          const Text('Looking for NFC tags...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          SoftButton(label: 'Cancel', dark: true, onPressed: () => Navigator.pop(context)),
        ]),
      );
}

class NfcDetectedScreen extends StatelessWidget {
  const NfcDetectedScreen({super.key, required this.topicId});
  final String topicId;
  @override
  Widget build(BuildContext context) {
    final t = AppState.read(context).byId(topicId);
    return DarkScaffold(
      child: Column(children: [
        const Spacer(),
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent.withValues(alpha: .12),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: .6), width: 2)),
          child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
        ),
        const SizedBox(height: 24),
        const Text('NFC Tag Detected', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            TopicIcon(t.iconIndex, size: 52),
            const SizedBox(height: 10),
            Text(t.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('RAG: ${t.nfcId}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text(t.stats, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        const Spacer(),
        GradientButton(label: 'Open Knowledge Base',
            onPressed: () => Navigator.pushReplacementNamed(context, Routes.detail, arguments: t.id)),
        const SizedBox(height: 12),
        SoftButton(label: 'Cancel', dark: true, onPressed: () => Navigator.pop(context)),
      ]),
    );
  }
}

class NfcWriteScreen extends StatefulWidget {
  const NfcWriteScreen({super.key, required this.topicId});
  final String topicId;
  @override
  State<NfcWriteScreen> createState() => _NfcWriteState();
}

class _NfcWriteState extends State<NfcWriteScreen> {
  late final AppState _s = AppState.read(context);
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _s.nfc.write('tapat://kb/${_s.byId(widget.topicId).nfcId}').then((v) {
      if (mounted) setState(() => _ok = v);
    });
  }

  @override
  void dispose() { _s.nfc.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = _s.byId(widget.topicId);
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: const Text('Link NFC Tag')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 12),
          TopicIcon(t.iconIndex, size: 72),
          const SizedBox(height: 12),
          Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('RAG: ${t.nfcId}', style: TextStyle(color: hint, fontSize: 12)),
          const SizedBox(height: 16),
          Text(_ok ? 'Tag linked successfully!' : 'Hold a blank NFC tag near\nyour phone to write.',
              textAlign: TextAlign.center, style: TextStyle(color: _ok ? Colors.green : hint)),
          const Spacer(),
          _ok
              ? const Icon(Icons.check_circle, color: Colors.green, size: 120)
              : Ripple(size: 240, child: const Icon(Icons.phone_android, size: 64, color: AppColors.blue)),
          const Spacer(),
          if (!_ok)
            Text('This will write a link to this knowledge base so you can open it by tapping the tag later.',
                textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 12)),
          const SizedBox(height: 16),
          SoftButton(label: _ok ? 'Done' : 'Cancel', onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}