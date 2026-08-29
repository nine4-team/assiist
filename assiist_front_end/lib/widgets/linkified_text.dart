import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/screens/log_note_screen.dart';

/// Custom linkifier for assiist:// deep links
class AssiistLinkifier extends Linkifier {
  const AssiistLinkifier();

  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    final result = <LinkifyElement>[];

    for (final element in elements) {
      if (element is TextElement) {
        final text = element.text;
        final regex = RegExp(r'assiist://[^\s]+');
        final matches = regex.allMatches(text);

        if (matches.isEmpty) {
          result.add(element);
        } else {
          int start = 0;
          for (final match in matches) {
            if (match.start > start) {
              result.add(TextElement(text.substring(start, match.start)));
            }
            result.add(UrlElement(match.group(0)!, match.group(0)!));
            start = match.end;
          }
          if (start < text.length) {
            result.add(TextElement(text.substring(start)));
          }
        }
      } else {
        result.add(element);
      }
    }

    return result;
  }
}

/// A reusable widget that automatically linkifies text, handling both regular URLs
/// and assiist:// deep links. This provides a consistent linkification experience
/// across the entire app with proper gradient styling support.
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    // Parse the text to find links
    final linkifyElements = _parseText(text);

    // If no links found, return simple text
    if (linkifyElements.every((element) => element is TextElement)) {
      return Text(
        text,
        style: style ?? AppStyles.bodyTextStyle(context),
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    // Build TextSpans for RichText
    final textSpans = <InlineSpan>[];

    for (final element in linkifyElements) {
      if (element is TextElement) {
        textSpans.add(
          TextSpan(
            text: element.text,
            style: style ?? AppStyles.bodyTextStyle(context),
          ),
        );
      } else if (element is LinkableElement) {
        // Create a custom widget span for gradient links
        textSpans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () => _handleLinkTap(context, element),
              child:
                  AppStyles.useGradientAccent
                      ? AppStyles.gradientText(
                        child: Text(
                          element.text,
                          style: (linkStyle ??
                                  style ??
                                  AppStyles.bodyTextStyle(context))
                              .copyWith(
                                color:
                                    CupertinoColors
                                        .white, // Base color for gradient
                                decoration: TextDecoration.none,
                              ),
                        ),
                      )
                      : Text(
                        element.text,
                        style: (linkStyle ??
                                style ??
                                AppStyles.bodyTextStyle(context))
                            .copyWith(
                              color: AppStyles.solidAccent,
                              decoration: TextDecoration.none,
                            ),
                      ),
            ),
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(children: textSpans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  /// Parse text to find links using the same linkifiers as the original implementation
  List<LinkifyElement> _parseText(String text) {
    const linkifiers = [
      AssiistLinkifier(), // Custom linkifier for assiist:// deep links
      UrlLinkifier(), // Default URL linkifier for http/https
      EmailLinkifier(), // Email linkifier for mailto:
    ];

    List<LinkifyElement> elements = [TextElement(text)];

    for (final linkifier in linkifiers) {
      elements = linkifier.parse(elements, const LinkifyOptions());
    }

    return elements;
  }

  /// Handle link taps for both regular URLs and assiist:// deep links
  static Future<void> _handleLinkTap(
    BuildContext context,
    LinkableElement link,
  ) async {
    final url = link.url;

    try {
      final uri = Uri.parse(url);

      // Handle assiist:// deep links
      if (uri.scheme == 'assiist') {
        _handleDeepLink(context, uri);
      } else {
        // Handle regular URLs (http, https, mailto, etc.)
        await _handleExternalUrl(url);
      }
    } catch (e) {
      print('Error parsing URL: $url, error: $e');
      _showErrorDialog(context, 'Invalid link format');
    }
  }

  /// Handle assiist:// deep links
  static void _handleDeepLink(BuildContext context, Uri uri) {
    if (uri.host == 'log-note') {
      // Navigate to LogNoteScreen with parameters from the deep link
      final appointmentId = uri.queryParameters['appointment_id'];
      final contactIds = uri.queryParameters['contact_ids'];
      final prefillType = uri.queryParameters['prefill_type'];

      print(
        'Deep link navigation: appointmentId=$appointmentId, contactIds=$contactIds, prefillType=$prefillType',
      );

      // Use the existing LogNoteScreen.fromDeepLink method
      Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => LogNoteScreen.fromDeepLink(uri)),
      );
    } else {
      print('Unsupported deep link: $uri');
      _showErrorDialog(context, 'Unsupported deep link');
    }
  }

  /// Handle external URLs
  static Future<void> _handleExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('Cannot launch URL: $url');
      }
    } catch (e) {
      print('Error launching URL: $url, error: $e');
    }
  }

  /// Show error dialog for link handling issues
  static void _showErrorDialog(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Link Error'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
                isDefaultAction: true,
              ),
            ],
          ),
    );
  }
}
