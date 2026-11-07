import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';

import '../theme/game_icon_data.dart';
import '../theme/voxel_icons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TEXT THAT DRAWS OUR ICONS INSTEAD OF EMOJI
//
// Files that show game data import Flutter's material library with
// `hide Text` and this file instead:
//
//   import 'package:flutter/material.dart' hide Text;
//   import '<path>/core/ui/game_text.dart';
//
// [Text] has exactly the constructors of Flutter's Text. A string without a
// known emoji goes straight to the real Text; every emoji we drew an icon for
// (kEmojiToIcon — resources, rewards, status effects, actions) becomes that
// picture, sized to the text. Emoji we did not draw stay ordinary text.
// ─────────────────────────────────────────────────────────────────────────────

const int _fe0f = 0xFE0F;

bool _mayHaveEmoji(String s) {
  for (final u in s.codeUnits) {
    if (u >= 0x2190) return true;
  }
  return false;
}

/// An icon inside text that still reports the emoji it replaces as its plain
/// text, so finders, copy and screen readers see what the string really says.
class EmojiSpan extends WidgetSpan {
  final String emoji;
  const EmojiSpan(this.emoji, {required super.child, super.alignment});

  @override
  void computeToPlainText(StringBuffer buffer,
      {bool includeSemanticsLabels = true, bool includePlaceholders = true}) {
    buffer.write(emoji);
  }
}

/// Splits [s] into text and icon spans; null when it holds no known emoji.
List<InlineSpan>? emojiSpans(String s, double fontSize) {
  if (!_mayHaveEmoji(s)) return null;
  final out = <InlineSpan>[];
  final buf = StringBuffer();
  var found = false;
  final runes = s.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final ch = String.fromCharCode(runes[i]);
    final key = kEmojiToIcon[ch];
    if (key == null) {
      buf.write(ch);
      continue;
    }
    found = true;
    if (buf.isNotEmpty) {
      out.add(TextSpan(text: buf.toString()));
      buf.clear();
    }
    var original = ch;
    if (i + 1 < runes.length && runes[i + 1] == _fe0f) {
      original += String.fromCharCode(_fe0f);
      i++;
    }
    out.add(EmojiSpan(
      original,
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.04),
        child: GameIcon(key, size: fontSize * 1.2),
      ),
    ));
  }
  if (!found) return null;
  if (buf.isNotEmpty) out.add(TextSpan(text: buf.toString()));
  return out;
}

class Text extends StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d != null) {
      final base = DefaultTextStyle.of(context).style.merge(style);
      // The size the text will really be drawn at (the app's own scaler has a
      // floor, so this is NOT fontSize x a constant factor).
      final fs = (textScaler ?? MediaQuery.textScalerOf(context))
          .scale(base.fontSize ?? 14);
      final spans = emojiSpans(d, fs);
      if (spans != null) {
        return m.Text.rich(
          TextSpan(children: spans),
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel ?? d,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      }
      return m.Text(
        d,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return m.Text.rich(
      textSpan!,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
