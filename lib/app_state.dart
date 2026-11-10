import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/content.dart';
import 'models.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// État global : progression, réglages, série de jours.
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  AppState(this.prefs) {
    _load();
  }

  // ---- Réglages ----
  Lang lang = Lang.ru;
  int newPerDay = 8;
  double ttsRate = 0.45;
  bool showRoman = true;
  bool speakingEnabled = true;
  bool reminderOn = false;
  int reminderHour = 19;
  int reminderMinute = 0;
  String aiProvider = 'gemini';
  Map<String, String> aiModels = {};
  String tutorLevel = 'débutant';

  // ---- Progression ----
  final Map<String, CardState> cards = {};
  int streak = 0;
  String? lastStudyDay;
  int xp = 0;
  Map<String, int> dayLog = {}; // jour -> nb d'exercices réussis
  Map<String, int> newToday = {}; // "lang|jour" -> nb de nouveaux mots

  void _load() {
    final s = prefs.getString('settings');
    if (s != null) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      lang = Lang.values.byName(j['lang'] ?? 'ru');
      newPerDay = j['newPerDay'] ?? 8;
      ttsRate = (j['ttsRate'] ?? 0.45).toDouble();
      showRoman = j['showRoman'] ?? true;
      speakingEnabled = j['speakingEnabled'] ?? true;
      reminderOn = j['reminderOn'] ?? false;
      reminderHour = j['reminderHour'] ?? 19;
      reminderMinute = j['reminderMinute'] ?? 0;
      aiProvider = j['aiProvider'] ?? 'gemini';
      aiModels = Map<String, String>.from(j['aiModels'] ?? {});
      tutorLevel = j['tutorLevel'] ?? 'débutant';
    }
    final p = prefs.getString('progress');
    if (p != null) {
      final j = jsonDecode(p) as Map<String, dynamic>;
      (j['cards'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        if (Content.byId.containsKey(k)) {
          cards[k] = CardState.fromJson(v as Map<String, dynamic>);
        }
      });
      streak = j['streak'] ?? 0;
      lastStudyDay = j['lastStudyDay'];
      xp = j['xp'] ?? 0;
      dayLog = Map<String, int>.from(j['dayLog'] ?? {});
      newToday = Map<String, int>.from(j['newToday'] ?? {});
    }
  }

  Future<void> saveSettings() async {
    await prefs.setString(
        'settings',
        jsonEncode({
          'lang': lang.name,
          'newPerDay': newPerDay,
          'ttsRate': ttsRate,
          'showRoman': showRoman,
          'speakingEnabled': speakingEnabled,
          'reminderOn': reminderOn,
          'reminderHour': reminderHour,
          'reminderMinute': reminderMinute,
          'aiProvider': aiProvider,
          'aiModels': aiModels,
          'tutorLevel': tutorLevel,
        }));
    notifyListeners();
  }

  Future<void> _saveProgress() async {
    // On ne garde que les 60 derniers jours du journal.
    if (dayLog.length > 60) {
      final keys = dayLog.keys.toList()..sort();
      for (final k in keys.take(keys.length - 60)) {
        dayLog.remove(k);
      }
    }
    final today = dayKey(DateTime.now());
    newToday.removeWhere((k, _) => !k.endsWith(today));
    await prefs.setString(
        'progress',
        jsonEncode({
          'cards': cards.map((k, v) => MapEntry(k, v.toJson())),
          'streak': streak,
          'lastStudyDay': lastStudyDay,
          'xp': xp,
          'dayLog': dayLog,
          'newToday': newToday,
        }));
  }

  void setLang(Lang l) {
    lang = l;
    saveSettings();
  }

  // ---- Requêtes ----
  CardState? card(String id) => cards[id];

  int get currentStreak {
    if (lastStudyDay == null) return 0;
    final now = DateTime.now();
    final today = dayKey(now);
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    return (lastStudyDay == today || lastStudyDay == yesterday) ? streak : 0;
  }

  bool get studiedToday => lastStudyDay == dayKey(DateTime.now());

  List<Item> dueItems(Lang l) {
    final now = DateTime.now();
    final list = Content.all(l)
        .where((it) => cards[it.id] != null && !cards[it.id]!.due.isAfter(now))
        .toList();
    list.sort((a, b) => cards[a.id]!.due.compareTo(cards[b.id]!.due));
    return list;
  }

  int newIntroducedToday(Lang l) =>
      newToday['${l.name}|${dayKey(DateTime.now())}'] ?? 0;

  int newRemainingToday(Lang l) =>
      (newPerDay - newIntroducedToday(l)).clamp(0, 999);

  /// Prochains éléments jamais vus, dans l'ordre du cours.
  List<Item> nextNewItems(Lang l, int count, {int? unit}) {
    final src = unit == null
        ? Content.all(l)
        : Content.units[l]![unit].items;
    return src.where((it) => cards[it.id] == null).take(count).toList();
  }

  List<Item> learnedItems(Lang l) =>
      Content.all(l).where((it) => cards[it.id]?.learned ?? false).toList();

  List<Item> seenItems(Lang l) =>
      Content.all(l).where((it) => cards[it.id] != null).toList();

  double unitProgress(Unit u) {
    if (u.items.isEmpty) return 0;
    final n = u.items.where((it) => cards[it.id]?.learned ?? false).length;
    return n / u.items.length;
  }

  // ---- Mises à jour ----
  void recordReview(Item it, int quality, {bool isNew = false}) {
    final c = cards.putIfAbsent(it.id, () => CardState());
    c.review(quality, DateTime.now());
    if (isNew) {
      final k = '${it.lang.name}|${dayKey(DateTime.now())}';
      newToday[k] = (newToday[k] ?? 0) + 1;
    }
    _saveProgress();
  }

  /// Appelé à la fin d'une session.
  void finishSession({required int correctAnswers}) {
    final now = DateTime.now();
    final today = dayKey(now);
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    if (lastStudyDay != today) {
      streak = lastStudyDay == yesterday ? streak + 1 : 1;
      lastStudyDay = today;
    }
    xp += correctAnswers * 10;
    dayLog[today] = (dayLog[today] ?? 0) + correctAnswers;
    _saveProgress();
    notifyListeners();
  }

  Future<void> resetProgress() async {
    cards.clear();
    streak = 0;
    lastStudyDay = null;
    xp = 0;
    dayLog.clear();
    newToday.clear();
    await _saveProgress();
    notifyListeners();
  }
}

/// Donne accès à [AppState] dans l'arbre de widgets.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
