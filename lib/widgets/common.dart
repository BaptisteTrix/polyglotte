import 'package:flutter/material.dart';

import '../models.dart';
import '../services/speech.dart';

/// Couleurs des tons (convention courante : 1 rouge, 2 vert, 3 bleu, 4 violet).
Color toneColor(int tone, BuildContext context) {
  switch (tone) {
    case 1:
      return const Color(0xFFE53935);
    case 2:
      return const Color(0xFF43A047);
    case 3:
      return const Color(0xFF1E88E5);
    case 4:
      return const Color(0xFF8E24AA);
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

const toneSymbols = {1: '¯', 2: 'ˊ', 3: 'ˇ', 4: 'ˋ', 5: '·'};

/// Affiche le texte cible ; en chinois, chaque caractère est coloré selon son ton.
class TargetText extends StatelessWidget {
  final Item item;
  final double size;
  final bool colorTones;
  const TargetText(this.item,
      {super.key, this.size = 40, this.colorTones = true});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.25,
    );
    if (item.lang == Lang.zh && colorTones) {
      final tones = pinyinTones(item.roman);
      final hanzi = hanziChars(item.display);
      if (tones.length == hanzi.length) {
        var i = 0;
        final spans = <TextSpan>[];
        for (final ch in item.display.runes.map(String.fromCharCode)) {
          if (RegExp(r'[一-鿿]').hasMatch(ch)) {
            spans.add(TextSpan(
                text: ch,
                style: base.copyWith(color: toneColor(tones[i], context))));
            i++;
          } else {
            spans.add(TextSpan(text: ch, style: base));
          }
        }
        return Text.rich(TextSpan(children: spans),
            textAlign: TextAlign.center);
      }
    }
    return Text(item.display, style: base, textAlign: TextAlign.center);
  }
}

/// Prononciation (pinyin / translittération).
class RomanText extends StatelessWidget {
  final Item item;
  final double size;
  const RomanText(this.item, {super.key, this.size = 18});
  @override
  Widget build(BuildContext context) => Text(
        item.roman,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

class AudioButton extends StatelessWidget {
  final Item item;
  final double size;
  final bool slow;
  const AudioButton(this.item, {super.key, this.size = 28, this.slow = false});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      iconSize: size,
      tooltip: slow ? 'Écouter lentement' : 'Écouter',
      onPressed: () => Tts.speak(item.speak, item.lang,
          speed: slow ? (Tts.rate * 0.6) : null),
      icon: Icon(slow ? Icons.slow_motion_video : Icons.volume_up),
    );
  }
}

class AudioRow extends StatelessWidget {
  final Item item;
  final double size;
  const AudioRow(this.item, {super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AudioButton(item, size: size),
          const SizedBox(width: 8),
          AudioButton(item, size: size * 0.8, slow: true),
        ],
      );
}

enum OptionState { idle, correct, wrong, dimmed }

class OptionButton extends StatelessWidget {
  final Widget child;
  final OptionState state;
  final VoidCallback? onTap;
  const OptionButton(
      {super.key, required this.child, this.state = OptionState.idle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color border = cs.outlineVariant;
    Color bg = cs.surfaceContainerLow;
    switch (state) {
      case OptionState.correct:
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.15);
      case OptionState.wrong:
        border = Colors.red;
        bg = Colors.red.withValues(alpha: 0.12);
      case OptionState.dimmed:
        bg = cs.surfaceContainerLowest;
      case OptionState.idle:
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte d'information « mot » (utilisée dans les listes et la présentation).
class ItemDetails extends StatelessWidget {
  final Item item;
  final bool showRoman;
  final double size;
  const ItemDetails(this.item,
      {super.key, this.showRoman = true, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TargetText(item, size: size),
        if (showRoman) ...[
          const SizedBox(height: 6),
          RomanText(item),
        ],
        const SizedBox(height: 10),
        Text(item.fr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        if (item.note != null) ...[
          const SizedBox(height: 10),
          Text(item.note!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ],
    );
  }
}
