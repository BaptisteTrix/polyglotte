import 'dart:math';

/// Langues proposées par l'application.
enum Lang { ru, zh }

extension LangX on Lang {
  String get label => this == Lang.ru ? 'Russe' : 'Mandarin';
  String get flag => this == Lang.ru ? '🇷🇺' : '🇨🇳';
  String get ttsLocale => this == Lang.ru ? 'ru-RU' : 'zh-CN';
  String get sttLocale => this == Lang.ru ? 'ru_RU' : 'zh_CN';
  String get nativeName => this == Lang.ru ? 'русский' : '中文';
  String get romanLabel => this == Lang.ru ? 'Translittération' : 'Pinyin';
}

/// Type d'élément à apprendre.
/// - [glyph] : une lettre cyrillique ou un caractère chinois de base (traçable)
/// - [word] : un mot de vocabulaire
/// - [phrase] : une phrase complète (exercice de remise en ordre)
enum ItemKind { glyph, word, phrase }

class Item {
  final String id;
  final Lang lang;
  final ItemKind kind;
  final int unit;

  /// Texte dans la langue cible. Pour les phrases chinoises, les mots sont
  /// séparés par des espaces dans les données (utilisé pour la remise en
  /// ordre), et [display] les retire.
  final String text;

  /// Prononciation : translittération (accent tonique marqué) ou pinyin.
  final String roman;

  /// Traduction / explication en français.
  final String fr;

  /// Exemple ou astuce (facultatif).
  final String? note;

  /// Texte prononcé par la synthèse vocale (par défaut [display]).
  final String? speakText;

  const Item({
    required this.id,
    required this.lang,
    required this.kind,
    required this.unit,
    required this.text,
    required this.roman,
    required this.fr,
    this.note,
    this.speakText,
  });

  static final _punct = RegExp(r'[.,!?;:«»"。，！？；：、]');

  /// Texte affiché.
  String get display =>
      lang == Lang.zh ? text.replaceAll(' ', '') : text;

  /// Texte à prononcer.
  String get speak => speakText ?? display;

  /// Caractère à tracer (première lettre majuscule pour le cyrillique).
  String get traceGlyph => text.split(' ').first;

  /// Morceaux à remettre dans l'ordre (sans ponctuation).
  List<String> get tokens => text
      .split(' ')
      .map((t) => t.replaceAll(_punct, ''))
      .where((t) => t.isNotEmpty)
      .toList();

  bool get canTrace => kind == ItemKind.glyph;
}

class Unit {
  final Lang lang;
  final int index;
  final String title;
  final String emoji;
  final List<Item> items;
  const Unit(this.lang, this.index, this.title, this.emoji, this.items);
}

/// État de répétition espacée d'une carte (algorithme de type SM-2).
class CardState {
  int reps;
  double interval; // en jours
  double ease;
  DateTime due;
  int lapses;
  int seen;
  int correct;

  CardState({
    this.reps = 0,
    this.interval = 0,
    this.ease = 2.5,
    DateTime? due,
    this.lapses = 0,
    this.seen = 0,
    this.correct = 0,
  }) : due = due ?? DateTime.now();

  bool get learned => reps > 0;
  bool get mastered => interval >= 21;

  /// [q] : 1 = raté, 3 = difficile, 4 = bien, 5 = facile.
  void review(int q, DateTime now) {
    seen++;
    final today = DateTime(now.year, now.month, now.day);
    if (q < 3) {
      reps = 0;
      lapses++;
      interval = 1;
      ease = max(1.3, ease - 0.2);
    } else {
      correct++;
      reps++;
      if (reps == 1) {
        interval = q == 5 ? 3 : 1;
      } else if (reps == 2) {
        interval = q == 3 ? 2 : (q == 5 ? 6 : 4);
      } else {
        final factor = q == 3 ? 1.2 : (q == 5 ? ease * 1.3 : ease);
        interval = max(interval + 1, interval * factor);
      }
      ease = max(1.3, ease + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    }
    interval = min(interval, 365);
    due = today.add(Duration(days: interval.round()));
  }

  Map<String, dynamic> toJson() => {
        'r': reps,
        'i': interval,
        'e': ease,
        'd': due.millisecondsSinceEpoch,
        'l': lapses,
        's': seen,
        'c': correct,
      };

  factory CardState.fromJson(Map<String, dynamic> j) => CardState(
        reps: j['r'] ?? 0,
        interval: (j['i'] ?? 0).toDouble(),
        ease: (j['e'] ?? 2.5).toDouble(),
        due: DateTime.fromMillisecondsSinceEpoch(j['d'] ?? 0),
        lapses: j['l'] ?? 0,
        seen: j['s'] ?? 0,
        correct: j['c'] ?? 0,
      );
}

/// Ton d'une syllabe pinyin (1 à 4, 5 = neutre).
int pinyinTone(String syllable) {
  const marks = {
    1: 'āēīōūǖ',
    2: 'áéíóúǘ',
    3: 'ǎěǐǒǔǚ',
    4: 'àèìòùǜ',
  };
  for (final e in marks.entries) {
    for (final c in e.value.split('')) {
      if (syllable.contains(c)) return e.key;
    }
  }
  return 5;
}

/// Liste des tons d'un pinyin (« nǐ hǎo » → [3, 3]).
List<int> pinyinTones(String pinyin) => pinyin
    .toLowerCase()
    .split(RegExp(r"[\s\-']+"))
    .map((s) => s.replaceAll(RegExp(r'[^a-zāáǎàēéěèīíǐìōóǒòūúǔùüǖǘǚǜ]'), ''))
    .where((s) => s.isNotEmpty)
    .map(pinyinTone)
    .toList();

/// Caractères chinois d'un texte (sans ponctuation ni espaces).
List<String> hanziChars(String text) => text.runes
    .map(String.fromCharCode)
    .where((c) => RegExp(r'[一-鿿]').hasMatch(c))
    .toList();
