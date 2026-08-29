import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/screens/log_note_screen.dart';
import 'package:assiist_front_end/screens/quick_message_screen.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/widgets/nav_bar_back_button.dart';
import 'package:assiist_front_end/widgets/app_segmented_toggle.dart';

/// A combined interface for logging notes and drafting quick messages.
class AssistantInterfaceScreen extends StatefulWidget {
  /// Pre-selected contact for the child screens.
  final Contact? initialContact;
  const AssistantInterfaceScreen({Key? key, this.initialContact})
    : super(key: key);

  @override
  _AssistantInterfaceScreenState createState() =>
      _AssistantInterfaceScreenState();
}

class _AssistantInterfaceScreenState extends State<AssistantInterfaceScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = const <Widget>[Text('Update Assistant'), Text('Quick Draft')];
    final children = <Widget>[
      LogNoteScreen(initialContact: widget.initialContact),
      GetDraftScreen(initialContact: widget.initialContact),
    ];

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        leading: const NavBarBackButton(),
        middle: const Text('Delegate to Assistant'),
        backgroundColor: AppStyles.subtleBackgroundColor(context),
        border: const Border(
          bottom: BorderSide(color: CupertinoColors.separator, width: 0),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Segmented control section styled with default padding
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppSegmentedToggle<int>(
                    options: const {0: 'Update Assistant', 1: 'Quick Draft'},
                    groupValue: _selectedIndex,
                    onValueChanged: (int? newIndex) {
                      if (newIndex != null)
                        setState(() => _selectedIndex = newIndex);
                    },
                  ),
                ],
              ),
            ),
            // Add introductory text based on selected tab
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Text(
                _selectedIndex == 0
                    ? 'Give your assistant notes from a recent interaction or info about a contact so they can update your database and create follow-ups.'
                    : 'Quickly draft a text message by describing what you want to say. A little context can go a long way, just like with a human assistant!',
                style: AppStyles.captionTextStyle(context),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: children),
            ),
          ],
        ),
      ),
    );
  }
}
