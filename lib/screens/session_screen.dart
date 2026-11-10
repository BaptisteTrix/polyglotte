import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/speech.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/exercises.dart';

class SessionScreen extends StatefulWidget {
  final Lang lang;
  final SessionMode mode;
  final int? unit;
  final String title;
  const SessionScreen(
      {super.key,
      required this.lang,
      required this.mode,
      this.unit,
      required this.title});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late List<Exercise> queue;
  late SessionPlanner planner;
  int index = 0;
  ExResult? answered;
  final Set<String> recorded = {};
  int correct = 0, total = 0;
  bool finished = false;
  int startStreak = 0;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    Tts.rate = s.ttsRate;
    startStreak = s.currentStreak;
    planner = SessionPlanner(s, _rnd);
    queue = planner.build(widget.lang, widget.mode, unit: widget.unit);
  }

  Exercise get ex => queue[index];

  void _onAnswer(ExResult r) {
    if (r.skipped) {
      _next();
      return;
    }
    final s = AppScope.read(context);
    if (ex.graded && !recorded.contains(ex.item.id)) {
      s.recordReview(ex.item, r.quality, isNew: ex.isNew);
      recorded.add(ex.item.id);
    }
    total++;
    if (r.correct) {
      correct++;
    } else {
      final retry = Exercise(ex.item, planner.retryType(ex), graded: false);
      queue.insert(min(index + 4, queue.length), retry);
    }
    setState(() => answered = r);
  }

  void _next() {
    Tts.stop();
    if (index + 1 >= queue.length) {
      _finish();
    } else {
      setState(() {
        index++;
        answered = null;
      });
    }
  }

  void _finish() {
    if (total > 0) {
      AppScope.read(context).finishSession(correctAnswers: correct);
    }
    setState(() => finished = true);
  }

  Future<bool> _confirmQuit() async {
    if (finished || total == 0) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quitter la session ?'),
        content: const Text(
            'Tes réponses sont enregistrées, mais ta série du jour ne compte que si tu termines.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Continuer')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Quitter')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) return _empty(context);
    if (finished) return _summary(context);
    final progress = (index + (answered != null ? 1 : 0)) / queue.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmQuit()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await _confirmQuit()) nav.pop();
            },
          ),
          title: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 10),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${index + 1}/${queue.length}')),
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: buildExercise(ex, _onAnswer, key: ValueKey(index)),
                ),
              ),
              if (answered != null) _feedback(context, answered!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feedback(BuildContext context, ExResult r) {
    final it = ex.item;
    final ok = r.correct;
    final color = ok ? Colors.green : Colors.red;
    return Material(
      color: color.withValues(alpha: 0.14),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(ok ? Icons.check_circle : Icons.cancel, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? ['Bravo !', 'Excellent !', 'Parfait !', 'Super !'][index % 4]
                        : 'Pas tout à fait…',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                AudioButton(it, size: 22),
              ]),
              if (!ok || ex.type == ExType.tone) ...[
                const SizedBox(height: 6),
                Text('${it.display}  ·  ${it.roman}',
                    style: const TextStyle(fontSize: 18)),
                Text(it.fr),
              ],
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _next,
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('Rien à réviser pour le moment !',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
                'Tu as fait toutes tes révisions et tes nouveaux mots du jour. '
                'Lance un entraînement libre, ou augmente le nombre de nouveaux mots dans les réglages.',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SessionScreen(
                            lang: widget.lang,
                            mode: SessionMode.practice,
                            title: 'Entraînement libre'))),
                child: const Text('Entraînement libre')),
          ]),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final s = AppScope.of(context);
    final pct = total == 0 ? 100 : (correct * 100 / total).round();
    final streakUp = s.currentStreak > startStreak;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(pct >= 80 ? '🏆' : '💪', style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 12),
              Text('Session terminée !',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                _stat(context, '$pct %', 'réussite'),
                _stat(context, '+${correct * 10}', 'XP'),
                _stat(context, '🔥 ${s.currentStreak}', streakUp ? 'série +1 !' : 'jours'),
              ]),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.home),
                label: const Text('Retour'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String v, String l) => Card(
        child: SizedBox(
          width: 96,
          height: 84,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(v, style: Theme.of(context).textTheme.titleLarge),
            Text(l, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
