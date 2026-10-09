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
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppState.of(context);
    if (_state == state) return;
    _state?.removeListener(_down);
    _state?.answerProgress.removeListener(_down);
    _state = state;
    state.addListener(_down);
    state.answerProgress.addListener(_down);
  }

  @override
  void dispose() {
    _state?.removeListener(_down);
    _state?.answerProgress.removeListener(_down);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  bool _needsModels(AppState state) =>
      !state.useMocks &&
      (!state.embeddingEngine.isLoaded || !state.llmEngine.isLoaded);

  void _send() {
    final question = _ctrl.text.trim();
    final state = AppState.read(context);
    if (question.isEmpty || state.isGenerating) return;
    if (_needsModels(state)) {
      Navigator.pushNamed(context, Routes.models);
      return;
    }
    if (state.askQuestion(widget.topicId, question)) {
      _ctrl.clear();
      _down();
    }
  }

  Future<void> _stop() => AppState.read(context).stopAnswer(widget.topicId);

  void _regenerate() {
    final state = AppState.read(context);
    final question = state.lastQuestion(widget.topicId);
    if (question == null || state.isGenerating) return;
    if (_needsModels(state)) {
      Navigator.pushNamed(context, Routes.models);
      return;
    }
    state.askQuestion(widget.topicId, question, regenerate: true);
    _down();
  }

  void _explore() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil(
        (route) => route.settings.name == Routes.shell || route.isFirst,
      );
    } else {
      navigator.pushReplacementNamed(Routes.shell);
    }
  }

  void _showSource(SourceRef source) {
    final state = AppState.read(context);
    final topic = state.repositories.topics.byUuid(widget.topicId);
    if (topic == null) return;
    final chunks = state.repositories.chunks
        .forTopic(topic.id)
        .where(
          (chunk) =>
              chunk.pageNumber == source.page &&
              chunk.document.target?.name == source.docName,
        )
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        return FractionallySizedBox(
          heightFactor: .78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.docName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Source document',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Page ${source.page}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Cited passage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: chunks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.find_in_page_outlined,
                                size: 38,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'This cited passage is no longer available.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: chunks.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: .65),
                              ),
                            ),
                            child: Text(
                              chunks[index].text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.55,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final t = s.topics.where((topic) => topic.id == widget.topicId).firstOrNull;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(
          child: Text('This knowledge base is no longer available.'),
        ),
      );
    }
    final msgs = s.chatOf(t.id);
    final busy = s.isAnswering(t.id);
    final generatingElsewhere = s.isGenerating && !busy;
    final needsModels = !s.isGenerating && _needsModels(s);
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TopicIcon(t.iconIndex, size: 24),
            const SizedBox(width: 8),
            Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') s.clearChat(t.id);
              if (value == 'regenerate') _regenerate();
            },
            itemBuilder: (_) => [
              if (s.lastQuestion(t.id) != null)
                PopupMenuItem(
                  value: 'regenerate',
                  enabled: !s.isGenerating,
                  child: const Text('Regenerate answer'),
                ),
              const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy)
            MaterialBanner(
              leading: const Icon(Icons.auto_awesome_outlined),
              content: Text(
                s.isStopping ? 'Stopping the local AI...' : 'Local AI is answering. Explore the app; we will notify you when it is ready.',
              ),
              actions: [
                TextButton(
                  onPressed: _explore,
                  child: const Text('Explore app'),
                ),
              ],
            ),
          if (generatingElsewhere)
            MaterialBanner(
              content: Text(
                'Local AI is answering in ${s.answeringTopic!.name}. Please wait before asking another question.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    Routes.chat,
                    arguments: s.answeringTopic!.id,
                  ),
                  child: const Text('View progress'),
                ),
              ],
            ),
          if (needsModels)
            MaterialBanner(
              content: const Text(
                'Download a local language model and embedding model to chat offline.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, Routes.models),
                  child: const Text('Choose models'),
                ),
              ],
            ),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: s.answerProgress,
              builder: (_, partial, _) => msgs.isEmpty && !busy
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BrandLogo(size: 56),
                          const SizedBox(height: 8),
                          Text(
                            'Ask anything about ${t.name}',
                            style: TextStyle(color: hint),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: msgs.length + (busy ? 1 : 0),
                      itemBuilder: (_, i) => i == msgs.length
                          ? partial.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                : _Bubble(
                                    Message(partial, false),
                                    onSource: _showSource,
                                  )
                          : _Bubble(
                              msgs[i],
                              onSource: _showSource,
                              onCopy: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: msgs[i].text),
                                );
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Copied')),
                                );
                              },
                            ),
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      enabled: !generatingElsewhere,
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Ask a question...',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.mic_none),
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.blue,
                    child: IconButton(
                      icon: Icon(
                        busy ? Icons.stop : Icons.arrow_forward,
                        color: Colors.white,
                      ),
                      tooltip: busy ? 'Stop answer' : 'Send question',
                      onPressed: busy
                          ? (s.isStopping ? null : _stop)
                          : generatingElsewhere
                          ? null
                          : (needsModels
                                ? () => Navigator.pushNamed(
                                    context,
                                    Routes.models,
                                  )
                                : _send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FormattedMessage(m.text),
            if (m.sources.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 15,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Sources',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${m.sources.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final source in m.sources)
                          ActionChip(
                            onPressed: onSource == null
                                ? null
                                : () => onSource!(source),
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 16,
                            ),
                            label: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: w * .54),
                              child: Text(
                                '${source.docName} · p. ${source.page}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelStyle: Theme.of(context).textTheme.labelSmall,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _messageTimestamp(context, m.sentAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (onCopy != null && !m.isUser)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy message',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: onCopy,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _messageTimestamp(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final date = MaterialLocalizations.of(context).formatShortDate(local);
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}

class _FormattedMessage extends StatelessWidget {
  const _FormattedMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5) ??
        const TextStyle(height: 1.5);
    final emphasis = base.copyWith(fontWeight: FontWeight.w700);
    final italic = base.copyWith(fontStyle: FontStyle.italic);
    final code = base.copyWith(
      fontFamily: 'monospace',
      fontSize: (base.fontSize ?? 14) - 1,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*.+?\*\*|__.+?__|\*[^*\n]+\*|_[^_\n]+_|`[^`]+`)',
    );
    final lines = text.split('\n');
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      if (lineIndex > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[lineIndex];
      var cursor = 0;
      for (final match in pattern.allMatches(line)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: line.substring(cursor, match.start)));
        }
        final token = match.group(0)!;
        if (token.startsWith('**') || token.startsWith('__')) {
          spans.add(
            TextSpan(
              text: token.substring(2, token.length - 2),
              style: emphasis,
            ),
          );
        } else if (token.startsWith('`')) {
          spans.add(
            TextSpan(text: token.substring(1, token.length - 1), style: code),
          );
        } else {
          spans.add(
            TextSpan(text: token.substring(1, token.length - 1), style: italic),
          );
        }
        cursor = match.end;
      }
      if (cursor < line.length) {
        spans.add(TextSpan(text: line.substring(cursor)));
      }
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
