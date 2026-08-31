import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/profile_models.dart';
import '../profile/profile_providers.dart';
import 'format.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileControllerProvider);

    return Scaffold(
      body: state.profiles.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Add a subscription to get started.'),
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
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _UrlDialog(),
    );
    if (url == null || url.isEmpty) return;
    try {
      await ref.read(profileControllerProvider.notifier).addRemote(url: url);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
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
            subtitle: Text('Updated ${formatRelative(profile.updatedAt)}'),
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
                        const PopupMenuItem(
                          value: 'update',
                          child: Text('Update'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
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
                    '${info.expire != null ? '  ·  expires ${formatDate(info.expire!)}' : ''}',
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
        case 'delete':
          await controller.remove(profile.id);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _UrlDialog extends StatefulWidget {
  const _UrlDialog();

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add subscription'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: 'URL',
        hintText: 'https://…',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Add'),
      ),
    ],
  );
}
