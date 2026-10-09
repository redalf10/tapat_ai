import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
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
    _ctrl.clear();
    s.addMessage(topic.id, Message(q, true));
    setState(() => _busy = true);
    _down();
    final a = await s.rag.ask(topic, q);
    s.addMessage(topic.id, a);
    if (mounted) setState(() => _busy = false);
    _down();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final t = s.byId(widget.topicId);
    final msgs = s.chatOf(t.id);
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
            onSelected: (_) { s.chats.remove(t.id); s.setQuery(s.query); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'c', child: Text('Clear chat'))],
          ),
        ],
      ),
      body: Column(children: [
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
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: Align(alignment: Alignment.centerLeft,
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                      : _Bubble(msgs[i]),
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
              CircleAvatar(
                backgroundColor: AppColors.blue,
                child: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.white), onPressed: _send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final Message m;
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
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.docName, style: const TextStyle(fontSize: 11))),
                  Text('Page ${s.page}', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}