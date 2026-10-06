import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';

const _levels = <(String, String)>[
  ('7-10', 'Age 7–10'),
  ('11-14', 'Age 11–14'),
  ('15-18', 'Age 15–18'),
  ('adult', 'Driver / adult'),
];

const _languages = ['English', 'Nigerian Pidgin', 'Yoruba', 'Hausa', 'Igbo', 'French', 'Swahili', 'Arabic', 'Portuguese', 'Amharic', 'Zulu'];

const _topics = <(IconData, String, String)>[
  (Icons.settings_rounded, 'How engines work', 'How does a petrol engine turn fuel into movement?'),
  (Icons.battery_charging_full_rounded, 'Batteries & EVs', 'How does an electric car battery work, and why do EVs not need petrol?'),
  (Icons.cloud_outlined, 'Carbon & climate', 'What are carbon emissions from cars, and how do they affect our climate?'),
  (Icons.recycling_rounded, 'Recycling & reuse', 'What happens to old car batteries and tyres when they are recycled?'),
  (Icons.traffic_rounded, 'Road safety', 'What are the most important road safety rules for young people?'),
  (Icons.engineering_rounded, 'Future careers', 'What careers can I have in automotive engineering and the green economy?'),
];

/// AutoLearn: ask anything about STEM, cars, batteries, sustainability and careers.
/// Answers adapt to the learner's age band and language.
class AutoLearnScreen extends StatefulWidget {
  const AutoLearnScreen({super.key});
  @override
  State<AutoLearnScreen> createState() => _AutoLearnScreenState();
}

class _AutoLearnScreenState extends State<AutoLearnScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <LearnMessage>[];
  String _level = '11-14';
  String _language = 'English';
  String? _topic;
  bool _sending = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    backend.learnHistory().then((h) {
      if (!mounted) return;
      setState(() {
        _messages.addAll(h);
        _loaded = true;
      });
      _toBottom();
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(LearnMessage(role: 'user', content: msg, createdAt: DateTime.now()));
      _sending = true;
    });
    _toBottom();
    try {
      final reply = await backend.askAutoLearn(message: msg, level: _level, language: _language, topic: _topic);
      if (!mounted) return;
      setState(() => _messages.add(LearnMessage(role: 'assistant', content: reply, createdAt: DateTime.now())));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.removeLast());
      _input.text = msg;
      showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text('This clears your AutoLearn conversation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await backend.clearLearnHistory();
      if (mounted) setState(() => _messages.clear());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoLearn'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Language',
            initialValue: _language,
            onSelected: (v) => setState(() => _language = v),
            itemBuilder: (_) => [for (final l in _languages) PopupMenuItem(value: l, child: Text(l))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const Icon(Icons.translate_rounded, size: 20),
                const SizedBox(width: 4),
                Text(_language == 'Nigerian Pidgin' ? 'Pidgin' : _language, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          if (_messages.isNotEmpty) IconButton(tooltip: 'Start over', onPressed: _clear, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final l in _levels)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(l.$2), selected: _level == l.$1, onSelected: (_) => setState(() => _level = l.$1)),
                ),
            ],
          ),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? _intro()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (_, i) => i == _messages.length ? const _Typing() : _Bubble(_messages[i]),
                    ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.school_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 10),
            const Text('Learn how vehicles, energy and our planet connect.',
                style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w800, fontSize: 21, height: 1.2, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Ask any question. Answers match your age and your language, with activities you can try at home.',
                style: AppText.body.copyWith(color: const Color(0xFFDCE6F7))),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.info, minimumSize: const Size(0, 44)),
              onPressed: () => _send('Quiz me with one question about cars, batteries or the environment.'),
              icon: const Icon(Icons.quiz_rounded, size: 20),
              label: const Text('Quiz me'),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('Pick a topic', style: AppText.h3),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            for (final t in _topics)
              Panel(
                padding: const EdgeInsets.all(14),
                onTap: () {
                  _topic = t.$2;
                  _send(t.$3);
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(t.$1, color: AppColors.info),
                  const Spacer(),
                  Text(t.$2, style: AppText.title.copyWith(fontSize: 15)),
                ]),
              ),
          ],
        ),
      ],
    );
  }

  Widget _composer() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              maxLength: 1500,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Ask AutoLearn anything…', counterText: '', fillColor: AppColors.surface, isDense: true),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: 'Send',
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final LearnMessage m;
  const _Bubble(this.m);

  @override
  Widget build(BuildContext context) {
    final me = m.fromUser;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: me ? AppColors.ink : Colors.white,
          border: me ? null : Border.all(color: AppColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(me ? 18 : 4),
            bottomRight: Radius.circular(me ? 4 : 18),
          ),
        ),
        child: SelectableText(m.content, style: AppText.body.copyWith(color: me ? Colors.white : AppColors.ink, height: 1.5)),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(18)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info)),
            SizedBox(width: 10),
            Text('AutoLearn is thinking…', style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}
