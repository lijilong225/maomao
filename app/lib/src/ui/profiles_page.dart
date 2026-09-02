import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../profile/profile_models.dart';
import '../profile/profile_providers.dart';
import '../tunnel/tunnel_controller.dart';
import 'format.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileControllerProvider);

    return Scaffold(
      body: state.profiles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(AppLocalizations.of(context).profilesEmpty),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.profiles.length,
              itemBuilder: (context, index) {
                final profile = state.profiles[index];
                return _ProfileTile(
                  profile: profile,
                  selected: profile.id == state.activeId,
                  busy: profile.id == state.busyId,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_SubscriptionDraft>(
      context: context,
      builder: (context) => const _AddSubscriptionDialog(),
    );
    if (draft == null || draft.url.isEmpty) return;
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .addRemote(url: draft.url, name: draft.name);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _ProfileTile extends ConsumerWidget {
  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.busy,
  });

  final Profile profile;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(profileControllerProvider.notifier);
    final info = profile.userInfo;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
            title: Text(profile.name),
            subtitle: Text(
              l10n.profileUpdated(formatRelative(l10n, profile.updatedAt)),
            ),
            onTap: () => controller.setActive(profile.id),
            trailing: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : PopupMenuButton<String>(
                    onSelected: (action) => _onAction(context, ref, action),
                    itemBuilder: (context) => [
                      if (profile.isRemote)
                        PopupMenuItem(
                          value: 'update',
                          child: Text(l10n.actionUpdate),
                        ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l10n.actionEdit),
                      ),
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(l10n.actionRename),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.actionDelete),
                      ),
                    ],
                  ),
          ),
          if (info != null && info.hasQuota)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: info.usedRatio),
                  const SizedBox(height: 6),
                  Text(
                    '${formatBytes(info.used)} / ${formatBytes(info.total)}'
                    '${info.expire != null ? '  ·  ${l10n.profileExpires(formatDate(info.expire!))}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final controller = ref.read(profileControllerProvider.notifier);
    try {
      switch (action) {
        case 'update':
          await controller.update(profile.id);
        case 'edit':
          await _openEditor(context, ref);
        case 'rename':
          await _rename(context, controller);
        case 'delete':
          await controller.remove(profile.id);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _rename(
    BuildContext context,
    ProfileController controller,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: profile.name),
    );
    if (name == null || name.isEmpty) return;
    await controller.rename(profile.id, name);
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final body = await ref
        .read(profileControllerProvider.notifier)
        .readBody(profile.id);
    if (!context.mounted) return;
    if (body == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).profileNotDownloaded),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfileEditorPage(profile: profile, initialBody: body),
      ),
    );
  }
}

/// What the add dialog collects; an empty name falls back to the subscription
/// host.
class _SubscriptionDraft {
  const _SubscriptionDraft({required this.url, required this.name});

  final String url;
  final String name;
}

class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog();

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
    context,
    _SubscriptionDraft(url: _url.text.trim(), name: _name.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addSubscription),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.subscriptionUrl,
              hintText: 'https://…',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.profileName,
              helperText: l10n.profileNameOptional,
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionAdd)),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.actionRename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: l10n.profileName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionSave)),
      ],
    );
  }
}

class _ProfileEditorPage extends ConsumerStatefulWidget {
  const _ProfileEditorPage({required this.profile, required this.initialBody});

  final Profile profile;
  final String initialBody;

  @override
  ConsumerState<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends ConsumerState<_ProfileEditorPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialBody,
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String? failure;
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .writeBody(widget.profile.id, _controller.text);
      if (ref.read(profileControllerProvider).activeId == widget.profile.id) {
        final tunnel = ref.read(tunnelControllerProvider.notifier);
        await tunnel.applyConfigChanges();
        // applyConfigChanges surfaces failures through its state, not by throwing.
        failure = ref.read(tunnelControllerProvider).error;
        if (failure != null) tunnel.clearError();
      }
    } catch (error) {
      failure = '$error';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editProfile),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: l10n.actionSave,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            helperText: l10n.editProfileHelper,
            helperMaxLines: 2,
          ),
        ),
      ),
    );
  }
}
