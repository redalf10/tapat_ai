import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/source_ref_model.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.topicId});
  final String topicId;
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _stopped = false;
  String _partial = '';
  String? _lastQuestion;

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    final s = AppState.read(context);
    final topic = s.byId(widget.topicId);
    if (!s.useMocks && (!s.embeddingEngine.isLoaded || !s.llmEngine.isLoaded)) {
      Navigator.pushNamed(context, Routes.models);
      return;
    }
    _ctrl.clear();
    s.addMessage(topic.id, Message(q, true));
    _lastQuestion = q;
    _stopped = false;
    setState(() { _busy = true; _partial = ''; });
    _down();
    try {
      Message? answer;
      await for (final event in s.rag.askStream(topic, q)) {
        if (!mounted || _stopped) break;
        if (event.text.isNotEmpty) setState(() => _partial += event.text);
        if (event.message != null) answer = event.message;
        _down();
      }
      if (!_stopped && answer != null) s.addMessage(topic.id, answer);
    } catch (e) {
      if (mounted && !_stopped) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not answer with the local models: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _busy = false; _partial = ''; });
      _down();
    }
  }

  Future<void> _stop() async {
    _stopped = true;
    await AppState.read(context).llmEngine.stop();
  }

  Future<void> _regenerate() async {
    final question = _lastQuestion;
    if (question == null || _busy) return;
    final state = AppState.read(context);
    state.removeLastAssistant(widget.topicId);
    await _sendQuestion(question);
  }

  Future<void> _sendQuestion(String question) async {
    final topic = AppState.read(context).byId(widget.topicId);
    final state = AppState.read(context);
    _stopped = false;
    setState(() { _busy = true; _partial = ''; });
    try {
      Message? answer;
      await for (final event in state.rag.askStream(topic, question)) {
        if (!mounted || _stopped) break;
        if (event.text.isNotEmpty) setState(() => _partial += event.text);
        if (event.message != null) answer = event.message;
      }
      if (!_stopped && answer != null) state.addMessage(topic.id, answer);
    } catch (e) {
      if (mounted && !_stopped) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() { _busy = false; _partial = ''; }); }
  }

  void _showSource(SourceRef source) {
    final state = AppState.read(context);
    final topic = state.repositories.topics.byUuid(widget.topicId);
    if (topic == null) return;
    final chunks = state.repositories.chunks.forTopic(topic.id).where((chunk) =>
      chunk.pageNumber == source.page && chunk.document.target?.name == source.docName).toList();
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${source.docName} · Page ${source.page}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final chunk in chunks) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(chunk.text)),
          if (chunks.isEmpty) const Text('The cited text is no longer available.'),
        ])))));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final t = s.byId(widget.topicId);
    final msgs = s.chatOf(t.id);
    final needsModels = !s.useMocks && (!s.embeddingEngine.isLoaded || !s.llmEngine.isLoaded);
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          TopicIcon(t.iconIndex, size: 24),
          const SizedBox(width: 8),
          Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) { if (value == 'clear') s.clearChat(t.id); if (value == 'regenerate') _regenerate(); },
            itemBuilder: (_) => [
              if (_lastQuestion != null) const PopupMenuItem(value: 'regenerate', child: Text('Regenerate answer')),
              const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (needsModels) MaterialBanner(
          content: const Text('Download a local language model and embedding model to chat offline.'),
          actions: [TextButton(onPressed: () => Navigator.pushNamed(context, Routes.models), child: const Text('Choose models'))]),
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const BrandLogo(size: 56),
                    const SizedBox(height: 8),
                    Text('Ask anything about ${t.name}', style: TextStyle(color: hint)),
                  ]),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) => i == msgs.length
                      ? _partial.isEmpty ? const Padding(padding: EdgeInsets.all(8), child: Align(alignment: Alignment.centerLeft,
                          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                          : _Bubble(Message(_partial, false), onSource: _showSource)
                      : _Bubble(msgs[i], onSource: _showSource, onCopy: () async {
                          await Clipboard.setData(ClipboardData(text: msgs[i].text));
                          if (!mounted) return;
                          messenger.showSnackBar(const SnackBar(content: Text('Copied')));
                        }),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Ask a question...',
                    suffixIcon: IconButton(icon: const Icon(Icons.mic_none), onPressed: () {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(backgroundColor: AppColors.blue,
                child: IconButton(icon: Icon(_busy ? Icons.stop : Icons.arrow_forward, color: Colors.white),
                  onPressed: _busy ? _stop : (needsModels ? () => Navigator.pushNamed(context, Routes.models) : _send)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m, {this.onSource, this.onCopy});
  final Message m;
  final ValueChanged<SourceRef>? onSource;
  final VoidCallback? onCopy;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.of(context).size.width * .8;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: w),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.isUser
              ? (dark ? const Color(0xFF1E3A8A) : const Color(0xFFDCE8FF))
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text, style: const TextStyle(height: 1.4)),
          if (m.sources.isNotEmpty) ...[
            const Divider(height: 20),
            Text('Sources (${m.sources.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            for (final s in m.sources)
              InkWell(onTap: onSource == null ? null : () => onSource!(s), borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.picture_as_pdf, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s.docName, style: const TextStyle(fontSize: 11))),
                    Text('Page ${s.page}', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                  ]),
                ),
              ),
          ],
          if (onCopy != null && !m.isUser)
            Align(alignment: Alignment.centerRight, child: IconButton(
              visualDensity: VisualDensity.compact, tooltip: 'Copy message',
              icon: const Icon(Icons.copy, size: 16), onPressed: onCopy)),
        ]),
      ),
    );
  }
}
