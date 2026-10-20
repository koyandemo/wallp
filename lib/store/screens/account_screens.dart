import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_format.dart';
import '../../core/store_palette.dart';
import '../../data/account/account_models.dart';
import '../../data/account/account_repository.dart';
import '../../data/api/api_client.dart';
import '../state/favourites_sync.dart';
import '../widgets/common.dart';

/// What to tell the user about a failed account call. Branches on the
/// code, never the server's message (docs/app-api.md §1).
String accountErrorText(Object error) => switch (error) {
  ApiException(isNetwork: true) =>
    'No connection. Check your internet and try again.',
  ApiException(code: 'bad_credentials') => 'Wrong email or password.',
  ApiException(code: 'registration_failed') =>
    "Couldn't create the account. If you already have one, sign in.",
  ApiException(code: 'rate_limited') =>
    'Too many tries. Wait a minute and try again.',
  ApiException(code: 'invalid', field: 'currentPassword') ||
  ApiException(
    code: 'invalid',
    field: 'password',
  ) => 'That password is not right.',
  ApiException(code: 'invalid', field: 'newPassword') =>
    'Choose a stronger new password.',
  ApiException(code: 'validation_failed') => 'Check the fields and try again.',
  ApiException(status: 401) => 'You were signed out. Sign in again.',
  ApiException(isTransient: true) =>
    'Something went wrong on our side. Try again later.',
  _ => 'Something went wrong. Try again.',
};

/// The Me tab's account card: an invitation when signed out, who's signed
/// in otherwise. Signing in is optional; wallp works fully without it.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountRepository>();
    final sync = context.watch<FavouritesSync>();
    final p = context.palette;
    final user = account.user;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                user == null ? const SignInScreen() : const AccountScreen(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.outline),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: p.brand,
                foregroundColor: p.onBrand,
                child: user == null
                    ? const Icon(Icons.cloud_sync_outlined)
                    : Text(user.name.characters.first.toUpperCase()),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Sync favourites across devices',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user == null
                          ? 'Optional. Sign in to keep your hearts on every phone.'
                          : sync.isSyncing
                          ? 'Syncing favourites…'
                          : sync.lastError != null
                          ? "Favourites will sync when you're online"
                          : 'Favourites synced',
                      style: TextStyle(fontSize: 13, color: p.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sign in, or create an account.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.register = false});

  final bool register;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late bool _register = widget.register;
  bool _busy = false;
  bool _showPassword = false;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final account = context.read<AccountRepository>();
    try {
      final user = _register
          ? await account.register(
              email: _email.text,
              password: _password.text,
              displayName: _name.text,
            )
          : await account.login(email: _email.text, password: _password.text);
      if (!mounted) return;
      showToast(context, 'Signed in as ${user.name}. Syncing favourites.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _serverError(String field) =>
      _error?.code == 'validation_failed' ? _error!.messageFor(field) : null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Create account' : 'Sign in')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              'An account only syncs your favourites between phones. '
              'Everything else works without one.',
              style: TextStyle(color: p.muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (_register) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _serverError('displayName'),
                ),
                validator: (v) {
                  final n = v?.trim().length ?? 0;
                  if (n == 0) return 'Enter a name';
                  if (n > 60) return 'At most 60 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _serverError('email'),
              ),
              validator: (v) {
                final e = v?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
                  return 'Enter a valid email';
                }
                if (e.length > 254) return 'That email is too long';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? 'At least 10 characters' : null,
                errorText: _serverError('password'),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) {
                final n = v?.length ?? 0;
                if (n == 0) return 'Enter your password';
                if (_register && n < 10) return 'At least 10 characters';
                if (n > 256) return 'At most 256 characters';
                return null;
              },
            ),
            if (_error case final e?) ...[
              const SizedBox(height: 16),
              Text(
                accountErrorText(e),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(_register ? 'Create account' : 'Sign in'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
              child: Text(
                _register
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in user's account: name, password, where they're signed
/// in, sign out and delete.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Future<List<DeviceSession>>? _sessions;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  void _loadSessions() =>
      _sessions = context.read<AccountRepository>().sessions();

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done);
    } on Object catch (e) {
      if (mounted) showToast(context, accountErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountRepository>();
    final sync = context.watch<FavouritesSync>();
    final user = account.user;
    final p = context.palette;
    if (user == null) {
      // Signed out from elsewhere (another phone, a reused token).
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Center(
          child: Text("You're signed out", style: TextStyle(color: p.muted)),
        ),
      );
    }
    final now = nowOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: CircleAvatar(
              backgroundColor: p.brand,
              foregroundColor: p.onBrand,
              child: Text(user.name.characters.first.toUpperCase()),
            ),
            title: Text(user.name),
            subtitle: Text(user.email),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Name'),
            subtitle: Text(user.displayName),
            onTap: () => _editName(user.displayName),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Change password'),
            subtitle: const Text('Signs out your other phones'),
            onTap: _changePassword,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.favorite_outline_rounded),
            title: const Text('Favourites'),
            subtitle: Text(
              sync.isSyncing
                  ? 'Syncing…'
                  : sync.lastError != null
                  ? "Not synced yet. They'll sync when you're online."
                  : sync.lastSyncedAt == null
                  ? 'Themes and wallpapers sync between your phones'
                  : 'Synced ${DateFormatX.ago(sync.lastSyncedAt!, now)}',
            ),
            trailing: TextButton(
              onPressed: sync.isSyncing ? null : sync.sync,
              child: const Text('Sync now'),
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: "Where you're signed in"),
          FutureBuilder(
            future: _sessions,
            builder: (context, snap) {
              if (snap.hasError) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(accountErrorText(snap.error!)),
                  trailing: TextButton(
                    onPressed: () => setState(_loadSessions),
                    child: const Text('Retry'),
                  ),
                );
              }
              final list = snap.data;
              if (list == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: [
                  for (final s in list)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      leading: Icon(
                        s.current
                            ? Icons.smartphone_rounded
                            : Icons.devices_other_rounded,
                      ),
                      title: Text(
                        s.current
                            ? 'This phone'
                            : s.userAgent.isEmpty
                            ? 'Another device'
                            : s.userAgent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Signed in ${DateFormatX.ago(s.createdAt.toLocal(), now)}'
                        '${s.ip.isEmpty ? '' : ' · ${s.ip}'}',
                      ),
                      trailing: s.current
                          ? null
                          : IconButton(
                              tooltip: 'Sign out this device',
                              icon: const Icon(Icons.logout_rounded),
                              onPressed: () => _run(() async {
                                await account.revokeSession(s.id);
                                if (mounted) setState(_loadSessions);
                              }, 'Device signed out'),
                            ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: OutlinedButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await account.logout();
                if (!context.mounted) return;
                showToast(context, 'Signed out. Your favourites stay here.');
                navigator.pop();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _deleteAccount,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete account'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(String current) async {
    final name = await _prompt(
      title: 'Your name',
      fields: [_Field('Name', initial: current, maxLength: 60)],
      action: 'Save',
    );
    if (name == null || name.first.trim().isEmpty || !mounted) return;
    await _run(
      () => context.read<AccountRepository>().updateDisplayName(name.first),
      'Name saved',
    );
  }

  Future<void> _changePassword() async {
    final values = await _prompt(
      title: 'Change password',
      fields: const [
        _Field('Current password', secret: true),
        _Field('New password (10+ characters)', secret: true, minLength: 10),
      ],
      action: 'Change',
    );
    if (values == null || !mounted) return;
    await _run(
      () => context.read<AccountRepository>().changePassword(
        currentPassword: values[0],
        newPassword: values[1],
      ),
      'Password changed. Your other phones are signed out.',
    );
    if (mounted) setState(_loadSessions);
  }

  Future<void> _deleteAccount() async {
    final values = await _prompt(
      title: 'Delete account?',
      message:
          'This deletes your account and the favourites saved in it. '
          'Favourites on this phone stay. It cannot be undone.',
      fields: const [_Field('Password', secret: true)],
      action: 'Delete',
      destructive: true,
    );
    if (values == null || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await context.read<AccountRepository>().deleteAccount(values.first);
      if (!mounted) return;
      showToast(context, 'Account deleted');
      navigator.pop();
    } on Object catch (e) {
      if (mounted) showToast(context, accountErrorText(e));
    }
  }

  /// A small form in a dialog; null if cancelled.
  Future<List<String>?> _prompt({
    required String title,
    String? message,
    required List<_Field> fields,
    required String action,
    bool destructive = false,
  }) => showDialog<List<String>>(
    context: context,
    builder: (context) => _PromptDialog(
      title: title,
      message: message,
      fields: fields,
      action: action,
      destructive: destructive,
    ),
  );
}

class _Field {
  const _Field(
    this.label, {
    this.initial = '',
    this.secret = false,
    this.minLength = 1,
    this.maxLength = 256,
  });

  final String label;
  final String initial;
  final bool secret;
  final int minLength;
  final int maxLength;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.message,
    required this.fields,
    required this.action,
    required this.destructive,
  });

  final String title;
  final String? message;
  final List<_Field> fields;
  final String action;
  final bool destructive;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, [for (final c in _controllers) c.text]);
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message case final m?) ...[
              Text(m),
              const SizedBox(height: 12),
            ],
            for (final (i, f) in widget.fields.indexed)
              TextFormField(
                controller: _controllers[i],
                obscureText: f.secret,
                autofocus: i == 0,
                decoration: InputDecoration(labelText: f.label),
                validator: (v) {
                  final n = f.secret
                      ? (v ?? '').length
                      : (v ?? '').trim().length;
                  if (n < f.minLength) {
                    return f.minLength == 1
                        ? 'Required'
                        : 'At least ${f.minLength} characters';
                  }
                  if (n > f.maxLength) {
                    return 'At most ${f.maxLength} characters';
                  }
                  return null;
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: widget.destructive
              ? TextButton.styleFrom(foregroundColor: error)
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
