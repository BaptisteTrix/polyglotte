import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../session.dart';
import '../services/speech.dart';
import 'common.dart';
import 'trace_pad.dart';

class ExResult {
  final bool correct;

  /// Qualité pour la répétition espacée (1 raté, 3 difficile, 4 bien, 5 facile).
  final int quality;

  /// Exercice passé (ne compte pas).
  final bool skipped;
  const ExResult(this.correct, {int? quality, this.skipped = false})
      : quality = quality ?? (correct ? 4 : 1);
  static const skip = ExResult(true, skipped: true);
}

typedef OnAnswer = void Function(ExResult r);

Widget buildExercise(Exercise ex, OnAnswer onAnswer, {Key? key}) {
  switch (ex.type) {
    case ExType.intro:
      return IntroView(ex.item, onAnswer: onAnswer, key: key);
    case ExType.recall:
      return RecallView(ex.item, onAnswer: onAnswer, key: key);
    case ExType.order:
      return OrderView(ex.item, onAnswer: onAnswer, key: key);
    case ExType.speak:
      return SpeakView(ex.item, onAnswer: onAnswer, key: key);
    case ExType.trace:
      return TraceView(ex.item, onAnswer: onAnswer, key: key);
    case ExType.meaning:
    case ExType.reverse:
    case ExType.listen:
    case ExType.sound:
    case ExType.tone:
      return McqView(ex, onAnswer: onAnswer, key: key);
  }
}

class _Prompt extends StatelessWidget {
  final String text;
  const _Prompt(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      );
}

// ---------------------------------------------------------------------------
// Présentation d'un nouvel élément
// ---------------------------------------------------------------------------
class IntroView extends StatefulWidget {
  final Item item;
  final OnAnswer onAnswer;
  const IntroView(this.item, {super.key, required this.onAnswer});
  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> {
  @override
  void initState() {
    super.initState();
    Tts.speak(widget.item.speak, widget.item.lang);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(switch (it.kind) {
          ItemKind.glyph => it.lang == Lang.ru ? '✨ Nouvelle lettre' : '✨ Nouveau caractère',
          ItemKind.phrase => '✨ Nouvelle phrase',
          ItemKind.word => '✨ Nouveau mot',
        }),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      ItemDetails(it, size: it.kind == ItemKind.phrase ? 32 : 56),
                      if (it.speakText != null && it.kind == ItemKind.glyph) ...[
                        const SizedBox(height: 8),
                        Text('🔊 exemple : ${it.speakText}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 16),
                      AudioRow(it),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => widget.onAnswer(ExResult.skip),
          icon: const Icon(Icons.check),
          label: const Text('J\'ai compris'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// QCM (sens, sens inverse, écoute, son d'une lettre, tons)
// ---------------------------------------------------------------------------
class McqView extends StatefulWidget {
  final Exercise ex;
  final OnAnswer onAnswer;
  const McqView(this.ex, {super.key, required this.onAnswer});
  @override
  State<McqView> createState() => _McqViewState();
}

class _McqViewState extends State<McqView> {
  final rnd = Random();
  late List<String> options;
  late String answer;
  int? chosen;

  Item get it => widget.ex.item;
  ExType get type => widget.ex.type;

  String _tonePattern(List<int> t) => t.map((x) => '${toneSymbols[x]} $x').join('   ');

  @override
  void initState() {
    super.initState();
    switch (type) {
      case ExType.meaning:
      case ExType.listen:
        answer = it.fr;
        options = [answer, ...distractors(it, 3, rnd).map((x) => x.fr)];
      case ExType.reverse:
        answer = it.display;
        options = [answer, ...distractors(it, 3, rnd).map((x) => x.display)];
      case ExType.sound:
        answer = it.roman;
        options = [
          answer,
          ...distractors(it, 3, rnd, same: (a, b) => a.roman == b.roman)
              .map((x) => x.roman)
        ];
      case ExType.tone:
        final tones = pinyinTones(it.roman);
        answer = _tonePattern(tones);
        final set = <String>{answer};
        var guard = 0;
        while (set.length < 4 && guard++ < 100) {
          final alt = [
            for (final t in tones)
              rnd.nextDouble() < 0.6 ? 1 + rnd.nextInt(4) : t
          ];
          set.add(_tonePattern(alt));
        }
        options = set.toList();
      default:
        answer = '';
        options = [];
    }
    options.shuffle(rnd);
    if (type == ExType.listen || type == ExType.tone || type == ExType.meaning) {
      Future.delayed(const Duration(milliseconds: 250),
          () => Tts.speak(it.speak, it.lang));
    }
  }

  void _choose(int i) {
    if (chosen != null) return;
    setState(() => chosen = i);
    final ok = options[i] == answer;
    if (type == ExType.reverse || type == ExType.sound) {
      Tts.speak(it.speak, it.lang);
    }
    widget.onAnswer(ExResult(ok));
  }

  @override
  Widget build(BuildContext context) {
    final showRoman = AppScope.of(context).showRoman;
    final String prompt;
    final Widget head;
    switch (type) {
      case ExType.meaning:
        prompt = 'Que signifie…';
        head = Column(children: [
          TargetText(it, size: it.kind == ItemKind.phrase ? 30 : 48),
          if (showRoman) RomanText(it),
          const SizedBox(height: 8),
          AudioButton(it),
        ]);
      case ExType.reverse:
        prompt = 'Comment dit-on…';
        head = Text('« ${it.fr} »',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall);
      case ExType.listen:
        prompt = 'Écoute et choisis la traduction';
        head = AudioRow(it, size: 44);
      case ExType.sound:
        prompt = 'Quel son fait cette lettre ?';
        head = TargetText(it, size: 72);
      case ExType.tone:
        prompt = 'Écoute : quels sont les tons ?';
        head = Column(children: [
          TargetText(it, size: 52, colorTones: chosen != null),
          if (chosen != null) RomanText(it),
          const SizedBox(height: 8),
          AudioRow(it),
        ]);
      default:
        prompt = '';
        head = const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(prompt),
        Expanded(child: Center(child: SingleChildScrollView(child: head))),
        const SizedBox(height: 12),
        for (var i = 0; i < options.length; i++)
          OptionButton(
            state: chosen == null
                ? OptionState.idle
                : options[i] == answer
                    ? OptionState.correct
                    : i == chosen
                        ? OptionState.wrong
                        : OptionState.dimmed,
            onTap: () => _choose(i),
            child: Text(options[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: type == ExType.reverse && it.lang == Lang.zh
                        ? 24
                        : 17)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Carte mémoire auto-évaluée
// ---------------------------------------------------------------------------
class RecallView extends StatefulWidget {
  final Item item;
  final OnAnswer onAnswer;
  const RecallView(this.item, {super.key, required this.onAnswer});
  @override
  State<RecallView> createState() => _RecallViewState();
}

class _RecallViewState extends State<RecallView> {
  bool revealed = false;
  bool graded = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final showRoman = AppScope.of(context).showRoman;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Prompt('Traduis dans ta tête, puis retourne la carte'),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Text('« ${it.fr} »',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const Divider(height: 40),
                    if (revealed) ...[
                      TargetText(it, size: it.kind == ItemKind.phrase ? 30 : 44),
                      if (showRoman) RomanText(it),
                      const SizedBox(height: 8),
                      AudioRow(it),
                    ] else
                      const Icon(Icons.help_outline, size: 56),
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (!revealed)
          FilledButton(
            onPressed: () {
              setState(() => revealed = true);
              Tts.speak(it.speak, it.lang);
            },
            child: const Text('Retourner la carte'),
          )
        else if (!graded)
          Row(children: [
            for (final (label, q, color) in [
              ('Raté', 1, Colors.red),
              ('Difficile', 3, Colors.orange),
              ('Bien', 4, Colors.green),
              ('Facile', 5, Colors.blue),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () {
                      setState(() => graded = true);
                      widget.onAnswer(ExResult(q >= 3, quality: q));
                    },
                    child: FittedBox(child: Text(label)),
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Remettre la phrase dans l'ordre
// ---------------------------------------------------------------------------
class OrderView extends StatefulWidget {
  final Item item;
  final OnAnswer onAnswer;
  const OrderView(this.item, {super.key, required this.onAnswer});
  @override
  State<OrderView> createState() => _OrderViewState();
}

class _OrderViewState extends State<OrderView> {
  late final List<String> tokens; // ordre correct
  late List<int> pool; // indices mélangés encore disponibles
  final List<int> picked = [];
  late final List<String> tokenPinyin;
  bool? result;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    tokens = it.tokens;
    // Pinyin de chaque morceau (chinois) en consommant les syllabes.
    if (it.lang == Lang.zh) {
      final syl = it.roman.split(RegExp(r'\s+'));
      var k = 0;
      tokenPinyin = [
        for (final t in tokens)
          () {
            final n = hanziChars(t).length;
            final s = syl.skip(k).take(n).join(' ');
            k += n;
            return s;
          }()
      ];
    } else {
      tokenPinyin = List.filled(tokens.length, '');
    }
    pool = List.generate(tokens.length, (i) => i);
    final rnd = Random();
    do {
      pool.shuffle(rnd);
    } while (tokens.length > 1 &&
        List.generate(pool.length, (i) => tokens[pool[i]]).join('|') ==
            tokens.join('|'));
  }

  Widget _chip(int idx, {required VoidCallback? onTap, bool showPinyin = false}) {
    final isZh = widget.item.lang == Lang.zh;
    return ActionChip(
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      label: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tokens[idx], style: TextStyle(fontSize: isZh ? 24 : 18)),
        if (isZh && showPinyin)
          Text(tokenPinyin[idx],
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.primary)),
      ]),
    );
  }

  void _check() {
    final ok = List.generate(picked.length, (i) => tokens[picked[i]]).join('|') ==
        tokens.join('|');
    setState(() => result = ok);
    Tts.speak(widget.item.speak, widget.item.lang);
    widget.onAnswer(ExResult(ok));
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final showRoman = AppScope.of(context).showRoman;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Prompt('Construis la phrase'),
        Text('« ${it.fr} »',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Center(child: AudioButton(it)),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
                color: result == null
                    ? cs.outlineVariant
                    : (result! ? Colors.green : Colors.red),
                width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < picked.length; i++)
                _chip(picked[i],
                    showPinyin: showRoman,
                    onTap: result != null
                        ? null
                        : () => setState(() {
                              pool.add(picked.removeAt(i));
                            })),
            ],
          ),
        ),
        if (result == false) ...[
          const SizedBox(height: 8),
          Text('Bonne réponse : ${it.display}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 18)),
        ],
        const Spacer(),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final idx in pool)
              _chip(idx,
                  showPinyin: showRoman,
                  onTap: result != null
                      ? null
                      : () => setState(() {
                            pool.remove(idx);
                            picked.add(idx);
                          })),
          ],
        ),
        const SizedBox(height: 16),
        if (result == null)
          FilledButton(
            onPressed: pool.isEmpty ? _check : null,
            child: const Text('Vérifier'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Prononciation
// ---------------------------------------------------------------------------
class SpeakView extends StatefulWidget {
  final Item item;
  final OnAnswer onAnswer;
  const SpeakView(this.item, {super.key, required this.onAnswer});
  @override
  State<SpeakView> createState() => _SpeakViewState();
}

class _SpeakViewState extends State<SpeakView> {
  String heard = '';
  bool listening = false;
  bool done = false;
  String? error;
  int attempts = 0;
  double? score;

  @override
  void dispose() {
    if (listening) Stt.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    await Tts.stop();
    setState(() {
      listening = true;
      heard = '';
      error = null;
      score = null;
    });
    final ok = await Stt.listen(widget.item.lang, onResult: (w, fin) {
      if (!mounted) return;
      setState(() => heard = w);
      if (fin) _evaluate();
    });
    if (!ok && mounted) {
      setState(() {
        listening = false;
        error =
            'Reconnaissance vocale indisponible. Vérifie l\'autorisation du micro et installe la langue ${widget.item.lang.label.toLowerCase()} dans « Saisie vocale Google ».';
      });
    }
    // Sécurité : si aucun résultat final n'arrive.
    Timer(const Duration(seconds: 14), () {
      if (mounted && listening) _evaluate();
    });
  }

  void _evaluate() {
    if (!listening) return;
    Stt.stop();
    final sim = similarity(heard, widget.item.display);
    attempts++;
    setState(() {
      listening = false;
      score = sim;
    });
    if (sim >= 0.7) {
      setState(() => done = true);
      widget.onAnswer(ExResult(true, quality: sim >= 0.9 ? 5 : 4));
    } else if (attempts >= 3) {
      setState(() => done = true);
      widget.onAnswer(const ExResult(false, quality: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final showRoman = AppScope.of(context).showRoman;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Prompt('Écoute, puis dis-le à voix haute'),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(children: [
                TargetText(it, size: it.kind == ItemKind.phrase ? 30 : 48),
                if (showRoman) RomanText(it),
                const SizedBox(height: 6),
                Text(it.fr, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                AudioRow(it),
                const SizedBox(height: 24),
                if (heard.isNotEmpty)
                  Text('J\'ai entendu : « $heard »',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                if (score != null && !done)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Presque ! (${(score! * 100).round()} %) Réessaie (${3 - attempts} essai(s) restant(s)).',
                        style: const TextStyle(color: Colors.orange)),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ]),
            ),
          ),
        ),
        if (!done) ...[
          Center(
            child: SizedBox(
              width: 88,
              height: 88,
              child: FloatingActionButton.large(
                heroTag: null,
                backgroundColor: listening ? Colors.red : null,
                onPressed: listening ? _evaluate : _listen,
                child: Icon(listening ? Icons.stop : Icons.mic, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => done = true);
              Stt.stop();
              widget.onAnswer(ExResult.skip);
            },
            child: const Text('Je ne peux pas parler maintenant'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tracé
// ---------------------------------------------------------------------------
class TraceView extends StatefulWidget {
  final Item item;
  final OnAnswer? onAnswer;
  const TraceView(this.item, {super.key, this.onAnswer});
  @override
  State<TraceView> createState() => _TraceViewState();
}

class _TraceViewState extends State<TraceView> {
  final ctrl = TracePadController();
  double? score;
  bool guide = true;
  bool done = false;
  int attempts = 0;

  Future<void> _check() async {
    final s = await ctrl.score(widget.item.traceGlyph);
    attempts++;
    setState(() => score = s);
    final ok = s >= 0.55;
    if (widget.onAnswer != null && (ok || attempts >= 3)) {
      setState(() => done = true);
      widget.onAnswer!(ExResult(ok, quality: ok ? (s > 0.75 ? 5 : 4) : 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trace « ${it.traceGlyph} »',
                  style: Theme.of(context).textTheme.titleLarge),
              Text('${it.roman} — ${it.fr}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.outline)),
            ]),
          ),
          AudioButton(it),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: TracePad(
                glyph: it.traceGlyph, controller: ctrl, showGuide: guide),
          ),
        ),
        if (score != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              score! >= 0.55
                  ? 'Bravo ! Précision ${(score! * 100).round()} %'
                  : 'Précision ${(score! * 100).round()} % — suis mieux le modèle et réessaie.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: score! >= 0.55 ? Colors.green : Colors.orange,
                  fontSize: 16),
            ),
          ),
        if (it.lang == Lang.zh)
          Text(
            'Astuce : en général, de haut en bas et de gauche à droite ; horizontal avant vertical.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        const SizedBox(height: 8),
        if (!done)
          Row(children: [
            IconButton(
                tooltip: 'Annuler le dernier trait',
                onPressed: ctrl.undo,
                icon: const Icon(Icons.undo)),
            IconButton(
                tooltip: 'Effacer',
                onPressed: () => setState(() {
                      ctrl.clear();
                      score = null;
                    }),
                icon: const Icon(Icons.delete_outline)),
            IconButton(
                tooltip: guide ? 'Cacher le modèle' : 'Montrer le modèle',
                onPressed: () => setState(() => guide = !guide),
                icon: Icon(guide ? Icons.visibility_off : Icons.visibility)),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                  onPressed: _check, child: const Text('Vérifier')),
            ),
          ]),
        if (widget.onAnswer != null && !done)
          TextButton(
              onPressed: () {
                setState(() => done = true);
                widget.onAnswer!(ExResult.skip);
              },
              child: const Text('Passer')),
      ],
    );
  }
}
