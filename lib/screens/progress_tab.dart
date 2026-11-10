import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/content.dart';
import '../models.dart';

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final now = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i)),
    ];
    const dayNames = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: _big(context, '🔥', '${s.currentStreak}', 'jours de suite')),
          Expanded(child: _big(context, '⭐', '${s.xp}', 'XP au total')),
        ]),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('7 derniers jours', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final d in days)
                    Column(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (s.dayLog[dayKey(d)] ?? 0) > 0
                              ? Colors.orange
                              : cs.surfaceContainerHighest,
                        ),
                        child: Center(
                          child: (s.dayLog[dayKey(d)] ?? 0) > 0
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(dayNames[d.weekday - 1],
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                ],
              ),
            ]),
          ),
        ),
        for (final l in Lang.values) _langCard(context, s, l),
      ],
    );
  }

  Widget _big(BuildContext context, String emoji, String v, String label) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            Text(v, style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ]),
        ),
      );

  Widget _langCard(BuildContext context, AppState s, Lang l) {
    final all = Content.all(l);
    final seen = all.where((it) => s.card(it.id) != null).toList();
    final learned = seen.where((it) => s.card(it.id)!.learned).length;
    final mastered = seen.where((it) => s.card(it.id)!.mastered).length;
    var reviews = 0, ok = 0;
    for (final it in seen) {
      reviews += s.card(it.id)!.seen;
      ok += s.card(it.id)!.correct;
    }
    final due = s.dueItems(l).length;
    final hardest = [...seen]
      ..sort((a, b) => s.card(b.id)!.lapses.compareTo(s.card(a.id)!.lapses));
    final tough = hardest.where((it) => s.card(it.id)!.lapses > 0).take(5).toList();

    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.bold))]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l.flag}  ${l.label}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          row('Éléments vus', '${seen.length} / ${all.length}'),
          row('Appris', '$learned'),
          row('Maîtrisés (intervalle ≥ 3 semaines)', '$mastered'),
          row('À réviser maintenant', '$due'),
          row('Taux de réussite', reviews == 0 ? '—' : '${(ok * 100 / reviews).round()} %'),
          if (tough.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Tes mots difficiles :'),
            Wrap(spacing: 6, children: [
              for (final it in tough) Chip(label: Text('${it.display} · ${it.fr}')),
            ]),
          ],
        ]),
      ),
    );
  }
}
