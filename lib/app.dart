import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'auth/session_controller.dart';
import 'hotspots/hotspot_workspace.dart';
import 'hotspots/location_service.dart';

class OutreachApp extends StatefulWidget {
  const OutreachApp({
    super.key,
    required this.session,
    required this.hasAccounts,
    this.location,
  });
  final SessionController session;
  final bool hasAccounts;
  final HotspotLocationService? location;

  @override
  State<OutreachApp> createState() => _OutreachAppState();
}

class _OutreachAppState extends State<OutreachApp> with WidgetsBindingObserver {
  bool _hasSignedIn = false;
  late final _location = widget.location ?? HotspotLocationService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.session.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ANSVK Outreach',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C63)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.session.activity(),
      onPointerMove: (_) => widget.session.activity(),
      onPointerSignal: (_) => widget.session.activity(),
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final session = widget.session;
          if (session.worker != null) _hasSignedIn = true;
          return Stack(
            children: [
              if (session.worker == null)
                AuthForm(
                  session: session,
                  initiallyRegister: !widget.hasAccounts && !_hasSignedIn,
                )
              else ...[
                Offstage(
                  offstage: session.locked || session.hidden,
                  child: TickerMode(
                    enabled: !session.locked && !session.hidden,
                    child: HotspotWorkspace(
                      key: ValueKey(session.worker!.id),
                      session: session,
                      location: _location,
                    ),
                  ),
                ),
                if (session.locked)
                  AuthForm(
                    key: const ValueKey('unlock'),
                    session: session,
                    unlock: true,
                  ),
              ],
              if (session.hidden)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xFFF2F8F6),
                    child: Center(child: Icon(Icons.lock_outline, size: 48)),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    required this.session,
    this.initiallyRegister = false,
    this.unlock = false,
  });
  final SessionController session;
  final bool initiallyRegister;
  final bool unlock;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _register = widget.initiallyRegister;
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.session.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _passwordVisible = false;
      _confirmVisible = false;
    });
    try {
      if (widget.unlock) {
        await widget.session.unlock(_password.text);
      } else {
        await widget.session.signIn(
          _username.text,
          _password.text,
          register: _register,
        );
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to access your account. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        _confirm.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.busy;
    final title = widget.unlock
        ? 'App locked'
        : _register
        ? 'Create your account'
        : 'Sign in';
    return Scaffold(
      appBar: AppBar(title: const Text('ANSVK Outreach')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      widget.unlock
                          ? Icons.lock_outline
                          : Icons.volunteer_activism_outlined,
                      size: 52,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.unlock
                          ? 'Enter the password for ${widget.session.worker!.username}.'
                          : 'Your account works offline on this phone.',
                      textAlign: TextAlign.center,
                    ),
                    if (!widget.unlock) ...[
                      const SizedBox(height: 16),
                      const _PasswordRecoveryWarning(),
                    ],
                    const SizedBox(height: 28),
                    if (!widget.unlock) ...[
                      TextFormField(
                        key: const ValueKey('username'),
                        controller: _username,
                        enabled: !busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          helperText: 'Usernames are case-sensitive.',
                        ),
                        validator: (value) =>
                            value == null ||
                                value.trim().isEmpty ||
                                value.trim().length > 64
                            ? 'Enter a username of 1–64 characters.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const ValueKey('password'),
                      controller: _password,
                      enabled: !busy,
                      obscureText: !_passwordVisible,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: widget.unlock
                            ? null
                            : IconButton(
                                key: const ValueKey('toggle-password'),
                                tooltip: _passwordVisible
                                    ? 'Hide password'
                                    : 'Show password',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                        () => _passwordVisible =
                                            !_passwordVisible,
                                      ),
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                        helperText: !widget.unlock && _register
                            ? 'Use 8–128 characters.'
                            : null,
                      ),
                      textInputAction: _register && !widget.unlock
                          ? TextInputAction.next
                          : TextInputAction.done,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password.';
                        }
                        if (value.length > 128 ||
                            (_register && !widget.unlock && value.length < 8)) {
                          return 'Use 8–128 characters.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) {
                        if (!_register || widget.unlock) _submit();
                      },
                    ),
                    if (_register && !widget.unlock) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('confirm'),
                        controller: _confirm,
                        enabled: !busy,
                        obscureText: !_confirmVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          suffixIcon: IconButton(
                            key: const ValueKey('toggle-confirm'),
                            tooltip: _confirmVisible
                                ? 'Hide confirm password'
                                : 'Show confirm password',
                            onPressed: busy
                                ? null
                                : () => setState(
                                    () => _confirmVisible = !_confirmVisible,
                                  ),
                            icon: Icon(
                              _confirmVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (value) => value != _password.text
                            ? 'Passwords do not match.'
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        semanticsLabel: _error,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('submit'),
                      onPressed: busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          busy
                              ? 'Please wait…'
                              : widget.unlock
                              ? 'Unlock'
                              : _register
                              ? 'Create account'
                              : 'Sign in',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.unlock)
                      TextButton(
                        onPressed: busy ? null : widget.session.logout,
                        child: const Text('Sign out'),
                      )
                    else
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                setState(() {
                                  _register = !_register;
                                  _error = null;
                                  _passwordVisible = false;
                                  _confirmVisible = false;
                                });
                                _password.clear();
                                _confirm.clear();
                                _form.currentState?.reset();
                              },
                        child: Text(
                          _register
                              ? 'Already have an account? Sign in'
                              : 'Create an account',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordRecoveryWarning extends StatelessWidget {
  const _PasswordRecoveryWarning();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Remember your password. Password recovery is not available '
                'in this pilot, and unsynced records may be lost if you cannot '
                'sign in.\n\nUse this app only on a phone with a device screen '
                'lock or passcode.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
