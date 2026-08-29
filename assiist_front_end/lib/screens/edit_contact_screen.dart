import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SnackBar, ScaffoldMessenger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';
import 'package:assiist_front_end/widgets/edit_contact_form.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'contact_record_screen.dart'; // Import for contactByIdProvider

class EditContactScreen extends ConsumerStatefulWidget {
  final Contact contact;

  const EditContactScreen({super.key, required this.contact});

  @override
  ConsumerState<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends ConsumerState<EditContactScreen> {
  final GlobalKey<EditContactFormState> _formKey =
      GlobalKey<EditContactFormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleFormSave(Contact updatedContact) async {
    setState(() => _isSaving = true);

    try {
      // Compute a diff so we only send changed fields to the backend (PATCH semantics)
      final originalJson = widget.contact.toJson();
      final updatedJson = updatedContact.toJson();

      // Build the updates map by comparing original and updated values.
      final Map<String, dynamic> updates = {};
      for (final entry in updatedJson.entries) {
        final key = entry.key;
        final newValue = entry.value;
        final oldValue = originalJson[key];

        // Skip if value is unchanged (including both null)
        if (newValue == oldValue) continue;

        // Add to updates if it changed
        updates[key] = newValue;
      }

      // Remove fields that should never be updated via PATCH (server controlled or immutable)
      const disallowedKeys = {
        'id',
        'account_id',
        'created_by',
        'created_on',
        'updated_on',
        'updated_by',
        'last_contacted_on',
        'last_contacted_days',
        'is_deleted',
      };
      updates.removeWhere((key, _) => disallowedKeys.contains(key));

      // Remove any keys whose value is null
      updates.removeWhere((key, value) => value == null);

      // Clean nested maps that violate schema
      if (updates['business_details'] is Map) {
        final bd = Map<String, dynamic>.from(updates['business_details']);
        // If opportunities is null or empty -> drop business_details entirely
        final opp = bd['opportunities'];
        if (opp == null || (opp is List && opp.isEmpty)) {
          updates.remove('business_details');
        }
      }

      print('Updating contact with diff: $updates');

      if (updates.isEmpty) {
        // Nothing to update, exit early.
        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.pop(context, false);
        }
        return;
      }

      final contactRepo = ref.read(contactRepositoryProvider);
      await contactRepo.updateContact(widget.contact.id, updates);

      if (mounted) {
        ref.invalidate(contactRepositoryProvider);
        ref.invalidate(contactByIdProvider(widget.contact.id));

        showCupertinoDialog(
          context: context,
          builder:
              (context) => CupertinoAlertDialog(
                title: const Text('Success'),
                content: const Text('Contact updated successfully'),
                actions: [
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    child: const Text('OK'),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context, true);
                    },
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to update contact: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppStyles.subtleBackgroundColor(context),
        middle: const Text('Edit Contact'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child:
              _isSaving
                  ? const CupertinoActivityIndicator()
                  : const Text('Save'),
          onPressed:
              _isSaving ? null : () => _formKey.currentState?.triggerSave(),
        ),
      ),
      child: SafeArea(
        child: EditContactForm(
          key: _formKey,
          contact: widget.contact,
          onSave: _handleFormSave,
          labels: const {'firstName': 'First Name', 'lastName': 'Last Name'},
        ),
      ),
    );
  }
}
