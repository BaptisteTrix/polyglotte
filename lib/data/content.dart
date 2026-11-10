import '../models.dart';
import 'mandarin.dart';
import 'russian.dart';

List<Unit> _build(
    Lang lang, List<(String, String, String, List<List<String>>)> raw) {
  final units = <Unit>[];
  for (var u = 0; u < raw.length; u++) {
    final (title, emoji, kindName, rows) = raw[u];
    final kind = ItemKind.values.byName(kindName);
    final items = <Item>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      items.add(Item(
        id: '${lang.name}-$u-$i',
        lang: lang,
        kind: kind,
        unit: u,
        text: r[0],
        roman: r[1],
        fr: r[2],
        note: r.length > 3 && r[3].isNotEmpty ? r[3] : null,
        speakText: r.length > 4 ? r[4] : null,
      ));
    }
    units.add(Unit(lang, u, title, emoji, items));
  }
  return units;
}

class Content {
  Content._();
  static final Map<Lang, List<Unit>> units = {
    Lang.ru: _build(Lang.ru, russianUnits),
    Lang.zh: _build(Lang.zh, mandarinUnits),
  };

  static final Map<String, Item> byId = {
    for (final l in units.values)
      for (final u in l)
        for (final it in u.items) it.id: it,
  };

  static List<Item> all(Lang lang) =>
      [for (final u in units[lang]!) ...u.items];
}
