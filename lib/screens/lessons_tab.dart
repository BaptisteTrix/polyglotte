import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/content.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/exercises.dart';
import 'session_screen.dart';

class LessonsTab extends StatelessWidget {
  const LessonsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final units = Content.units[s.lang]!;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: units.length,
      itemBuilder: (context, i) {
        final u = units[i];
        final p = s.unitProgress(u);
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              radius: 24,
              child: Text(u.emoji, style: const TextStyle(fontSize: 22)),
            ),
            title: Text('${i + 1}. ${u.title}'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: p, minHeight: 6),
                ),
                const SizedBox(height: 4),
                Text('${(p * u.items.length).round()} / ${u.items.length}'),
              ]),
            ),
            trailing: p >= 1
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => UnitScreen(unit: u))),
          ),
        );
      },
    );
  }
}

class UnitScreen extends StatelessWidget {
  final Unit unit;
  const UnitScreen({super.key, required this.unit});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${unit.emoji} ${unit.title}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionScreen(
                lang: unit.lang,
                mode: SessionMode.unit,
                unit: unit.index,
                title: unit.title),
          ),
        ),
        icon: const Icon(Icons.school),
        label: const Text('Étudier cette unité'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        itemCount: unit.items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final it = unit.items[i];
          final c = s.card(it.id);
          return ListTile(
            leading: SizedBox(
              width: it.kind == ItemKind.phrase ? 0 : 72,
              child: it.kind == ItemKind.phrase
                  ? null
                  : Center(child: TargetText(it, size: it.display.length > 4 ? 18 : 26)),
            ),
            title: it.kind == ItemKind.phrase
                ? TargetText(it, size: 20)
                : Text(it.fr),
            subtitle: Text(it.kind == ItemKind.phrase ? '${it.roman}\n${it.fr}' : it.roman),
            isThreeLine: it.kind == ItemKind.phrase,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (c?.mastered ?? false)
                const Icon(Icons.star, color: Colors.amber, size: 20)
              else if (c?.learned ?? false)
                const Icon(Icons.check, color: Colors.green, size: 20),
              if (it.canTrace)
                IconButton(
                  tooltip: 'S\'entraîner à tracer',
                  icon: const Icon(Icons.draw),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TracePracticeScreen(
                              items: unit.items, start: i))),
                ),
              AudioButton(it, size: 20),
            ]),
          );
        },
      ),
    );
  }
}

/// Entraînement libre au tracé, caractère par caractère.
class TracePracticeScreen extends StatefulWidget {
  final List<Item> items;
  final int start;
  const TracePracticeScreen({super.key, required this.items, this.start = 0});
  @override
  State<TracePracticeScreen> createState() => _TracePracticeScreenState();
}

class _TracePracticeScreenState extends State<TracePracticeScreen> {
  late int i = widget.start;

  @override
  Widget build(BuildContext context) {
    final it = widget.items[i];
    return Scaffold(
      appBar: AppBar(
        title: Text('Tracé ${i + 1}/${widget.items.length}'),
        actions: [
          IconButton(
              onPressed: i > 0 ? () => setState(() => i--) : null,
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              onPressed: i < widget.items.length - 1 ? () => setState(() => i++) : null,
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TraceView(it, key: ValueKey(it.id)),
        ),
      ),
    );
  }
}
