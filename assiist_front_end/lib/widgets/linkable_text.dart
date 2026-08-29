import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

class LinkableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkableText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _parseTextWithLinks(context, text);

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.visible,
    );
  }

  List<TextSpan> _parseTextWithLinks(BuildContext context, String text) {
    final List<TextSpan> spans = [];
    final defaultStyle = style ?? AppStyles.bodyTextStyle(context);

    // Regex to match markdown-style links [text](url)
    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

    int lastMatchEnd = 0;

    for (final match in linkRegex.allMatches(text)) {
      // Add text before the link
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: defaultStyle,
          ),
        );
      }

      // Add the clickable link
      final linkText = match.group(1) ?? '';
      final linkUrl = match.group(2) ?? '';

      spans.add(
        TextSpan(
          text: linkText,
          style: defaultStyle.copyWith(
            color: CupertinoColors.systemBlue.resolveFrom(context),
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(linkUrl),
        ),
      );

      lastMatchEnd = match.end;
    }

    // Add remaining text after the last link
    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(text: text.substring(lastMatchEnd), style: defaultStyle),
      );
    }

    // If no links were found, return the original text
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: defaultStyle));
    }

    return spans;
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch URL: $url');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }
}
