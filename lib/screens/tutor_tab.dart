import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ai_tutor.dart';
import '../services/speech.dart';
import 'settings_screen.dart';

const scenarios = [
  ('🗣️', 'Conversation libre', 'une conversation libre et amicale sur la vie quotidienne'),
  ('🙋', 'Se présenter', 'une première rencontre : se présenter, dire d\'où l\'on vient, ses loisirs'),
  ('☕', 'Au café', 'tu es serveur dans un café et l\'élève commande une boisson'),
  ('🍜', 'Au restaurant', 'tu es serveur dans un restaurant et l\'élève commande un repas puis demande l\'addition'),
  ('🗺️', 'Demander son chemin', 'l\'élève est perdu dans la rue et te demande comment aller à la gare ou au métro'),
  ('🏨', 'À l\'hôtel', 'tu es réceptionniste d\'hôtel et l\'élève arrive pour faire son enregistrement'),
  ('🛍️', 'Faire les courses', 'tu es vendeur au marché ; l\'élève demande les prix et achète des fruits'),
  ('🚕', 'En taxi', 'tu es chauffeur de taxi et l\'élève t\'indique sa destination'),
];

class TutorTab extends StatefulWidget {
  const TutorTab({super.key});
  @override
  State<TutorTab> createState() => _TutorTabState();
}

class _TutorTabState extends State<TutorTab> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final List<ChatMsg> history = [];
  String? scenario;
  Lang? convLang;
  bool loading = false;
  bool listening = false;
  String? error;
  bool? hasKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkKey();
  }

  Future<void> _checkKey() async {
    final s = AppScope.read(context);
    final k = await AiTutor.getKey(s.aiProvider);
    if (mounted) setState(() => hasKey = k != null && k.isNotEmpty);
  }

  String _model(AppState s) =>
      s.aiModels[s.aiProvider] ?? providerInfo(s.aiProvider).defaultModel;

  Future<void> _start(String scen) async {
    final s = AppScope.read(context);
    setState(() {
      scenario = scen;
      convLang = s.lang;
      history
        ..clear()
        ..add(const ChatMsg(true, 'Commence la conversation.', hidden: true));
    });
    await _ask();
  }

  Future<void> _ask() async {
    final s = AppScope.read(context);
    setState(() {
      loading = true;
      error = null;
    });
    _scrollDown();
    try {
      final reply = await AiTutor.send(
        provider: s.aiProvider,
        model: _model(s),
        system: AiTutor.systemPrompt(convLang!, s.tutorLevel, scenario!),
        history: history,
      );
      if (!mounted) return;
      setState(() => history.add(ChatMsg(false, reply)));
      final parsed = TutorReply.parse(reply);
      if (parsed.target != null) {
        Tts.speak(parsed.target!, convLang!);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
      _scrollDown();
    }
  }

  void _send() {
    final t = input.text.trim();
    if (t.isEmpty || loading) return;
    input.clear();
    setState(() => history.add(ChatMsg(true, t)));
    _ask();
  }

  Future<void> _mic() async {
    if (listening) {
      await Stt.stop();
      setState(() => listening = false);
      return;
    }
    setState(() => listening = true);
    final ok = await Stt.listen(convLang!, onResult: (w, fin) {
      if (!mounted) return;
      setState(() {
        input.text = w;
        if (fin) listening = false;
      });
    });
    if (!ok && mounted) {
      setState(() {
        listening = false;
        error = 'Reconnaissance vocale indisponible sur cet appareil.';
      });
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (hasKey == false) return _setup(context, s);
    if (scenario == null || convLang != s.lang) return _pickScenario(context, s);
    final visible = history.where((m) => !m.hidden).toList();
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: ListTile(
          dense: true,
          leading: Text(s.lang.flag, style: const TextStyle(fontSize: 22)),
          title: Text(scenarios.firstWhere((x) => x.$3 == scenario).$2),
          subtitle: Text('${providerInfo(s.aiProvider).label} · ${_model(s)}'),
          trailing: TextButton.icon(
            onPressed: () => setState(() => scenario = null),
            icon: const Icon(Icons.refresh),
            label: const Text('Changer'),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(12),
          children: [
            for (final m in visible) _bubble(context, m),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Text(error!),
                    TextButton(onPressed: _ask, child: const Text('Réessayer')),
                  ]),
                ),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(children: [
            IconButton.filledTonal(
              tooltip: 'Parler',
              onPressed: loading ? null : _mic,
              icon: Icon(listening ? Icons.stop : Icons.mic),
              color: listening ? Colors.red : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Écris en ${s.lang.label.toLowerCase()} ou en français…',
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24))),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
                onPressed: loading ? null : _send, icon: const Icon(Icons.send)),
          ]),
        ),
      ),
    ]);
  }

  Widget _bubble(BuildContext context, ChatMsg m) {
    final cs = Theme.of(context).colorScheme;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
              color: cs.primary, borderRadius: BorderRadius.circular(18)),
          child: Text(m.text, style: TextStyle(color: cs.onPrimary, fontSize: 16)),
        ),
      );
    }
    final r = TutorReply.parse(m.text);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18)),
        child: !r.structured
            ? Text(m.text)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r.correction != null &&
                    r.correction != '—' &&
                    r.correction != '-')
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: r.correction!.contains('✓')
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(r.correction!, style: const TextStyle(fontSize: 14)),
                  ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(r.target!,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.volume_up),
                    onPressed: () => Tts.speak(r.target!, convLang!),
                  ),
                ]),
                if (r.pron != null)
                  Text(r.pron!,
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: cs.primary)),
                if (r.french != null) ...[
                  const SizedBox(height: 4),
                  Text(r.french!, style: TextStyle(color: cs.outline)),
                ],
              ]),
      ),
    );
  }

  Widget _pickScenario(BuildContext context, AppState s) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choisis une situation', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
            'Le tuteur joue la scène en ${s.lang.label.toLowerCase()}, te corrige et traduit tout. '
            'Niveau : ${s.tutorLevel}.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            for (final (emoji, title, desc) in scenarios)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _start(desc),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(title, textAlign: TextAlign.center),
                  ]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _setup(BuildContext context, AppState s) {
    final p = providerInfo(s.aiProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('🤖', style: TextStyle(fontSize: 64), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Configure ton tuteur IA',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
          'Le tuteur a besoin d\'une clé API. La plus simple et gratuite : Google Gemini.\n\n'
          '1. Va sur aistudio.google.com/apikey\n'
          '2. Connecte-toi avec ton compte Google\n'
          '3. Clique sur « Create API key » et copie-la\n'
          '4. Colle-la dans Réglages › Tuteur IA',
        ),
        const SizedBox(height: 8),
        Text('Fournisseur actuel : ${p.label}',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
            _checkKey();
          },
          icon: const Icon(Icons.key),
          label: const Text('Ajouter ma clé'),
        ),
      ],
    );
  }
}
