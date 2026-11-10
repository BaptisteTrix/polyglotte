import 'dart:math';

import 'app_state.dart';
import 'data/content.dart';
import 'models.dart';

enum ExType {
  intro, // présentation d'un nouvel élément
  meaning, // cible -> français (QCM)
  reverse, // français -> cible (QCM)
  listen, // audio -> français (QCM)
  sound, // lettre -> son (QCM)
  recall, // carte mémoire auto-évaluée
  order, // remettre la phrase dans l'ordre
  speak, // prononcer à voix haute
  trace, // tracer le caractère
  tone, // reconnaître les tons
}

class Exercise {
  final Item item;
  final ExType type;

  /// Le résultat compte pour la répétition espacée.
  final bool graded;
  final bool isNew;
  const Exercise(this.item, this.type, {this.graded = true, this.isNew = false});
}

enum SessionMode { daily, unit, practice, tones }

class SessionPlanner {
  final AppState s;
  final Random rnd;
  SessionPlanner(this.s, [Random? r]) : rnd = r ?? Random();

  List<ExType> _reviewTypes(Item it) {
    final speak = s.speakingEnabled;
    switch (it.kind) {
      case ItemKind.glyph:
        return it.lang == Lang.ru
            ? [ExType.sound, ExType.sound, ExType.trace]
            : [ExType.meaning, ExType.trace, ExType.tone, ExType.reverse];
      case ItemKind.word:
        return [
          ExType.meaning,
          ExType.reverse,
          ExType.listen,
          ExType.recall,
          if (it.lang == Lang.zh) ExType.tone,
          if (speak) ExType.speak,
        ];
      case ItemKind.phrase:
        return [
          ExType.order,
          ExType.order,
          ExType.listen,
          ExType.recall,
          if (speak) ExType.speak,
        ];
    }
  }

  ExType reviewType(Item it) {
    final t = _reviewTypes(it);
    return t[rnd.nextInt(t.length)];
  }

  /// Type d'exercice pour réessayer après une erreur (différent si possible).
  ExType retryType(Exercise ex) {
    final t = _reviewTypes(ex.item).where((x) => x != ex.type).toList();
    if (t.isEmpty) return ex.type;
    return t[rnd.nextInt(t.length)];
  }

  ExType _firstType(Item it) => it.kind == ItemKind.glyph && it.lang == Lang.ru
      ? ExType.sound
      : ExType.meaning;

  ExType _secondType(Item it) {
    switch (it.kind) {
      case ItemKind.glyph:
        return ExType.trace;
      case ItemKind.word:
        return it.lang == Lang.zh && rnd.nextBool() ? ExType.tone : ExType.reverse;
      case ItemKind.phrase:
        return ExType.order;
    }
  }

  List<Exercise> _interleave(List<Item> news, List<Item> reviews) {
    final out = <Exercise>[];
    final rev = [...reviews]..shuffle(rnd);
    final reviewExs = [for (final it in rev) Exercise(it, reviewType(it))];
    var ri = 0;
    for (var c = 0; c < news.length; c += 3) {
      final chunk = news.sublist(c, min(c + 3, news.length));
      for (final it in chunk) {
        out.add(Exercise(it, ExType.intro, graded: false, isNew: true));
        out.add(Exercise(it, _firstType(it), isNew: true));
      }
      for (var k = 0; k < 4 && ri < reviewExs.length; k++) {
        out.add(reviewExs[ri++]);
      }
      for (final it in chunk) {
        out.add(Exercise(it, _secondType(it), graded: false));
      }
    }
    out.addAll(reviewExs.sublist(ri));
    return out;
  }

  List<Exercise> build(Lang lang, SessionMode mode, {int? unit}) {
    switch (mode) {
      case SessionMode.daily:
        final reviews = s.dueItems(lang).take(40).toList();
        final news = s.nextNewItems(lang, s.newRemainingToday(lang));
        return _interleave(news, reviews);
      case SessionMode.unit:
        final u = Content.units[lang]![unit!];
        final news = s.nextNewItems(lang, 8, unit: unit);
        final now = DateTime.now();
        final reviews = u.items
            .where((it) => s.card(it.id) != null && !s.card(it.id)!.due.isAfter(now))
            .toList();
        if (news.isEmpty && reviews.isEmpty) {
          // Unité déjà vue : entraînement libre sur ses éléments.
          final pool = [...u.items]..shuffle(rnd);
          return [
            for (final it in pool.take(12))
              Exercise(it, reviewType(it), graded: false)
          ];
        }
        return _interleave(news, reviews);
      case SessionMode.practice:
        var pool = s.seenItems(lang);
        if (pool.isEmpty) pool = Content.units[lang]!.first.items;
        pool = [...pool]..shuffle(rnd);
        return [
          for (final it in pool.take(15))
            Exercise(it, reviewType(it), graded: false)
        ];
      case SessionMode.tones:
        var pool = s
            .seenItems(Lang.zh)
            .where((it) => it.kind != ItemKind.phrase)
            .toList();
        if (pool.length < 6) pool = Content.units[Lang.zh]![0].items;
        pool = [...pool]..shuffle(rnd);
        return [
          for (final it in pool.take(15))
            Exercise(it, ExType.tone, graded: false)
        ];
    }
  }
}

/// Choisit des distracteurs plausibles pour un QCM.
List<Item> distractors(Item it, int count, Random rnd,
    {bool Function(Item a, Item b)? same}) {
  same ??= (a, b) => a.fr == b.fr || a.display == b.display;
  final all = Content.all(it.lang)
      .where((x) => x.id != it.id && x.kind == it.kind && !same!(x, it))
      .toList();
  final sameUnit = all.where((x) => x.unit == it.unit).toList()..shuffle(rnd);
  final others = all.where((x) => x.unit != it.unit).toList()..shuffle(rnd);
  final picked = <Item>[];
  for (final x in [...sameUnit, ...others]) {
    if (picked.length >= count) break;
    if (picked.any((p) => same!(p, x))) continue;
    picked.add(x);
  }
  return picked;
}
