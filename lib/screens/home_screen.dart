import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/content.dart';
import '../models.dart';
import '../session.dart';
import 'lessons_tab.dart';
import 'progress_tab.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'tutor_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pages = [
      TodayTab(onOpenTutor: () => setState(() => tab = 2)),
      const LessonsTab(),
      const TutorTab(),
      const ProgressTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polyglotte'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SegmentedButton<Lang>(
              showSelectedIcon: false,
              segments: [
                for (final l in Lang.values)
                  ButtonSegment(
                      value: l,
                      tooltip: l.label,
                      label: Text(l.flag, style: const TextStyle(fontSize: 20))),
              ],
              selected: {s.lang},
              onSelectionChanged: (v) => s.setLang(v.first),
            ),
          ),
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Aujourd\'hui'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Leçons'),
          NavigationDestination(icon: Icon(Icons.forum), label: 'Tuteur IA'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Progrès'),
        ],
      ),
    );
  }
}

class TodayTab extends StatelessWidget {
  final VoidCallback onOpenTutor;
  const TodayTab({super.key, required this.onOpenTutor});

  void _start(BuildContext context, SessionMode mode, String title) {
    final s = AppScope.read(context);
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SessionScreen(lang: s.lang, mode: mode, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final due = s.dueItems(s.lang).length;
    final fresh = s.nextNewItems(s.lang, s.newRemainingToday(s.lang)).length;
    final learned = s.learnedItems(s.lang).length;
    final totalItems = Content.all(s.lang).length;
    final streak = s.currentStreak;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Text(streak > 0 ? '🔥' : '🌱', style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    streak > 0 ? '$streak jour${streak > 1 ? 's' : ''} de suite' : 'Commence ta série !',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    s.studiedToday
                        ? 'Session du jour faite ✅'
                        : 'Fais ta session pour garder ta série.',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${s.lang.flag}  ${s.lang.label} — ${s.lang.nativeName}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                _pill(context, Icons.replay, '$due à réviser'),
                const SizedBox(width: 8),
                _pill(context, Icons.fiber_new, '$fresh nouveaux'),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: totalItems == 0 ? 0 : learned / totalItems, minHeight: 8),
              ),
              const SizedBox(height: 4),
              Text('$learned / $totalItems éléments appris',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
                onPressed: () => _start(context, SessionMode.daily, 'Session du jour'),
                icon: const Icon(Icons.play_arrow),
                label: Text(due + fresh == 0
                    ? 'Tout est à jour !'
                    : 'Session du jour (~${((due + fresh * 3) * 0.25).ceil().clamp(1, 30)} min)'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text('Entraînements rapides', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _quick(context, '🎯', 'Entraînement libre',
            'Revois des éléments déjà vus, sans pression', () => _start(context, SessionMode.practice, 'Entraînement libre')),
        if (s.lang == Lang.ru)
          _quick(context, '🔤', 'Alphabet cyrillique',
              'Apprends les 33 lettres en quelques jours', () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SessionScreen(
                        lang: Lang.ru, mode: SessionMode.unit, unit: 0, title: 'Alphabet')));
          }),
        if (s.lang == Lang.zh)
          _quick(context, '🎵', 'Oreille des tons',
              'Reconnais les 4 tons du mandarin à l\'écoute', () => _start(context, SessionMode.tones, 'Tons')),
        _quick(context, '💬', 'Parler avec le tuteur IA',
            'Mets en pratique dans une vraie conversation', onOpenTutor),
        const SizedBox(height: 12),
        Card(
          color: cs.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '💡 La méthode : chaque jour, quelques nouveaux mots et les révisions '
              'que l\'algorithme te propose juste avant que tu les oublies '
              '(répétition espacée). 10 à 15 minutes par jour valent mieux '
              'qu\'une heure une fois par semaine !',
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(text),
      );

  Widget _quick(BuildContext context, String emoji, String title, String sub,
          VoidCallback onTap) =>
      Card(
        child: ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 28)),
          title: Text(title),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
