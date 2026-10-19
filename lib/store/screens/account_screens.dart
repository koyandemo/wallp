import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_format.dart';
import '../../core/store_palette.dart';
import '../../data/api/account_models.dart';
import '../../data/api/account_service.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/auth_session.dart';
import '../widgets/common.dart';

/// What to tell the user about [e]. Field errors go under their field
/// ([fieldError]); this is the line above the button.
String accountErrorText(Object e) {
  if (e is! ApiException) return 'Something went wrong. Try again later.';
  return switch (e.code) {
    ApiErrorCode.badCredentials => 'Wrong email or password.',
    ApiErrorCode.registrationFailed =>
      "Couldn't create the account. If you already have one, sign in.",
    ApiErrorCode.rateLimited => 'Too many tries. Wait a minute and try again.',
    ApiErrorCode.offline ||
    ApiErrorCode.timeout => "No connection. Try again when you're online.",
    ApiErrorCode.validationFailed ||
    ApiErrorCode.invalid => 'Check the details above.',
    ApiErrorCode.tokenExpired ||
    ApiErrorCode.tokenReused ||
    ApiErrorCode.unauthorized => 'You were signed out. Sign in again.',
    _ => 'Something went wrong. Try again later.',
  };
}

/// The server's complaint about [field], in plain words, or null.
String? fieldError(Object? e, String field) {
  if (e is! ApiException || e.messageFor(field) == null) return null;
  return switch (field) {
    'email' => 'Enter a valid email address',
    'password' || 'newPassword' => 'Use 10 to 256 characters',
    'currentPassword' => 'That password is wrong',
    'displayName' => 'Use 1 to 60 characters',
    _ => e.messageFor(field),
  };
}

// Same limits as the server (docs/app-client.md §3), checked before sending.
String? _checkEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email';
  if (s.length > 254 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _checkNewPassword(String? v) {
  final n = v?.length ?? 0;
  return n < 10 || n > 256 ? 'Use 10 to 256 characters' : null;
}

String? _checkName(String? v) {
  final n = v?.trim().length ?? 0;
  return n < 1 || n > 60 ? 'Use 1 to 60 characters' : null;
}

/// Sign in, or create an account. Pops with true once signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.startWithRegister = false});

  final bool startWithRegister;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late bool _register = widget.startWithRegister;
  bool _busy = false;
  bool _showPassword = false;
  Object? _error;

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
    final session = context.read<AuthSession>();
    try {
      if (_register) {
        await session.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _name.text.trim(),
        );
      } else {
        await session.login(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Create account' : 'Sign in')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              'An account keeps your favourites on every phone. '
              'Everything else works without one.',
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 24),
            if (_register) ...[
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: fieldError(_error, 'displayName'),
                ),
                validator: _checkName,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: fieldError(_error, 'email'),
              ),
              validator: _checkEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? 'At least 10 characters' : null,
                errorText: fieldError(_error, 'password'),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: _register
                  ? _checkNewPassword
                  : (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                accountErrorText(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_register ? 'Create account' : 'Sign in'),
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
                    ? 'I already have an account'
                    : 'New here? Create an account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in account: name, password, devices, sign out, delete.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Future<List<LoginSession>>? _sessions;

  AccountService get _account => context.read<AccountService>();

  @override
  void initState() {
    super.initState();
    _sessions = _account.sessions();
  }

  void _loadSessions() {
    final next = _account.sessions();
    // A block: `=> _sessions = next` would hand setState a Future.
    setState(() {
      _sessions = next;
    });
  }

  /// Runs [action], showing its error as a toast. True if it worked.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on Object catch (e) {
      if (mounted) showToast(context, accountErrorText(e));
      return false;
    }
  }

  Future<void> _rename(AccountUser user) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: 'Your name',
        label: 'Name',
        initial: user.displayName,
        action: 'Save',
        validator: _checkName,
      ),
    );
    if (name == null || name.trim() == user.displayName) return;
    if (await _run(() => _account.updateDisplayName(name.trim())) && mounted) {
      showToast(context, 'Name saved');
    }
  }

  Future<void> _changePassword() async {
    final account = _account;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(account: account),
    );
    if (changed == null || !mounted) return;
    showToast(
      context,
      changed
          ? 'Password changed. Other phones were signed out.'
          : 'Password changed. Sign in again with the new one.',
    );
    if (!changed) Navigator.of(context).pop();
  }

  Future<void> _signOut() async {
    await context.read<AuthSession>().logout();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final account = _account;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(account: account),
    );
    if (deleted != true || !mounted) return;
    showToast(context, 'Account deleted. Your favourites stay on this phone.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthSession>();
    final user = session.user;
    final palette = context.palette;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: const EmptyMessage(
          icon: Icons.person_off_rounded,
          title: 'Signed out',
          message: 'Sign in again from Me.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: AccountAvatar(user: user, size: 48),
            title: Text(user.displayName),
            subtitle: Text(user.email),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => _rename(user),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('Change password'),
            subtitle: const Text('Signs out your other phones'),
            onTap: _changePassword,
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Signed-in phones'),
          FutureBuilder(
            future: _sessions,
            builder: (context, snap) {
              if (snap.hasError) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(accountErrorText(snap.error!)),
                  trailing: TextButton(
                    onPressed: _loadSessions,
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
                      title: Text(s.current ? 'This phone' : _device(s)),
                      subtitle: Text(
                        'Signed in ${DateFormatX.longDate(s.createdAt.toLocal())}',
                      ),
                      trailing: s.current
                          ? null
                          : IconButton(
                              tooltip: 'Sign out this phone',
                              icon: const Icon(Icons.logout_rounded),
                              onPressed: () async {
                                if (await _run(
                                  () => _account.revokeSession(s),
                                )) {
                                  _loadSessions();
                                }
                              },
                            ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            subtitle: const Text('Favourites stay on this phone'),
            onTap: _signOut,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(
              Icons.delete_forever_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete account',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text(
              'Removes the account and its synced favourites',
              style: TextStyle(color: palette.muted),
            ),
            onTap: _delete,
          ),
        ],
      ),
    );
  }

  static String _device(LoginSession s) =>
      s.userAgent.isEmpty ? 'Another device' : s.userAgent;
}

/// The first letter of the name in a circle.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.user, this.size = 40});

  final AccountUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = user?.displayName.trim() ?? '';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: user == null ? palette.surface2 : palette.brand,
      foregroundColor: user == null ? palette.muted : palette.onBrand,
      child: name.isEmpty
          ? Icon(Icons.person_rounded, size: size * 0.55)
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
    this.validator,
  });

  final String title;
  final String label;
  final String action;
  final String initial;
  final FormFieldValidator<String>? validator;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    if (_form.currentState!.validate()) Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        validator: widget.validator,
        onFieldSubmitted: (_) => _done(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: Text(widget.action)),
    ],
  );
}

/// Pops true (signed back in), false (changed, but signed out), or null.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.account});

  final AccountService account;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.account.changePassword(
        current: _current.text,
        next: _next.text,
      );
      if (mounted) Navigator.pop(context, ok);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _current,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Current password',
              errorText: fieldError(_error, 'currentPassword'),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Enter it' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _next,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New password',
              helperText: 'At least 10 characters',
              errorText: fieldError(_error, 'newPassword'),
            ),
            validator: _checkNewPassword,
          ),
          if (_error != null &&
              fieldError(_error, 'currentPassword') == null &&
              fieldError(_error, 'newPassword') == null) ...[
            const SizedBox(height: 12),
            Text(
              accountErrorText(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('Change'),
      ),
    ],
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.account});

  final AccountService account;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.deleteAccount(_password.text);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This removes your account and synced favourites for good. '
            'Your themes and favourites on this phone stay.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error == null
                  ? null
                  : fieldError(_error, 'password') ?? accountErrorText(_error!),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: _busy ? null : _submit,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
