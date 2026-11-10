import 'package:flutter_test/flutter_test.dart';
import 'package:polyglotte/app_state.dart';
import 'package:polyglotte/data/content.dart';
import 'package:polyglotte/models.dart';
import 'package:polyglotte/services/ai_tutor.dart';
import 'package:polyglotte/services/speech.dart';
import 'package:polyglotte/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Contenu', () {
    test('alphabet russe complet (33 lettres)', () {
      expect(Content.units[Lang.ru]![0].items.length, 33);
    });

    test('chaque élément chinois a autant de syllabes pinyin que de caractères', () {
      for (final it in Content.all(Lang.zh)) {
        expect(pinyinTones(it.roman).length, hanziChars(it.display).length,
            reason: '${it.display} / ${it.roman}');
      }
    });

    test('identifiants uniques et champs remplis', () {
      final ids = <String>{};
      for (final l in Lang.values) {
        for (final it in Content.all(l)) {
          expect(ids.add(it.id), isTrue);
          expect(it.text.trim(), isNotEmpty);
          expect(it.roman.trim(), isNotEmpty);
          expect(it.fr.trim(), isNotEmpty);
        }
      }
    });

    test('les phrases ont au moins 2 morceaux à remettre en ordre', () {
      for (final l in Lang.values) {
        for (final it in Content.all(l).where((x) => x.kind == ItemKind.phrase)) {
          expect(it.tokens.length, greaterThanOrEqualTo(1), reason: it.text);
          expect(it.tokens.join(), isNot(contains('。')));
        }
      }
    });

    test('affichage chinois sans espaces', () {
      final it = Content.all(Lang.zh).firstWhere((x) => x.kind == ItemKind.phrase);
      expect(it.display.contains(' '), isFalse);
    });
  });

  group('Tons', () {
    test('détection', () {
      expect(pinyinTones('nǐ hǎo'), [3, 3]);
      expect(pinyinTones('mā má mǎ mà ma'), [1, 2, 3, 4, 5]);
      expect(pinyinTones('nǚ'), [3]);
    });
  });

  group('Répétition espacée', () {
    test('les intervalles augmentent quand on réussit', () {
      final c = CardState();
      final now = DateTime(2026, 1, 1);
      c.review(4, now);
      expect(c.interval, 1);
      c.review(4, now);
      expect(c.interval, 4);
      c.review(4, now);
      expect(c.interval, greaterThan(8));
    });

    test('une erreur remet la carte à zéro', () {
      final c = CardState();
      final now = DateTime(2026, 1, 1);
      c
        ..review(4, now)
        ..review(4, now)
        ..review(1, now);
      expect(c.reps, 0);
      expect(c.interval, 1);
      expect(c.lapses, 1);
    });
  });

  group('Session', () {
    late AppState s;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      s = AppState(await SharedPreferences.getInstance());
    });

    test('session du jour : nouveaux éléments présentés puis testés', () {
      final plan = SessionPlanner(s).build(Lang.ru, SessionMode.daily);
      final intros = plan.where((e) => e.type == ExType.intro).length;
      expect(intros, s.newPerDay);
      expect(plan.first.type, ExType.intro);
    });

    test('révisions dues incluses', () {
      final it = Content.all(Lang.zh)[3];
      s.recordReview(it, 1);
      s.cards[it.id]!.due = DateTime.now().subtract(const Duration(days: 1));
      final plan = SessionPlanner(s).build(Lang.zh, SessionMode.daily);
      expect(plan.any((e) => e.item.id == it.id && e.type != ExType.intro), isTrue);
    });

    test('série de jours', () {
      s.finishSession(correctAnswers: 5);
      expect(s.currentStreak, 1);
      expect(s.xp, 50);
    });
  });

  group('Divers', () {
    test('comparaison de prononciation tolérante', () {
      expect(similarity('Привет', 'привет!'), 1);
      expect(similarity('ёлка', 'елка'), 1);
      expect(similarity('你好', '你好！'), 1);
      expect(similarity('пока', 'привет'), lessThan(0.5));
    });

    test('analyse de la réponse du tuteur', () {
      final r = TutorReply.parse('**CIBLE:** Привет! Как дела?\n'
          'PRONONCIATION: privét! kak delá?\n'
          'FRANÇAIS: Salut ! Ça va ?\n'
          'CORRECTION: —');
      expect(r.target, 'Привет! Как дела?');
      expect(r.pron, 'privét! kak delá?');
      expect(r.french, 'Salut ! Ça va ?');
      expect(r.correction, '—');
    });
  });
}
