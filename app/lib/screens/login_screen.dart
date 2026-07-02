import 'package:flutter/material.dart';

import '../api.dart';
import 'admin_home.dart';
import 'student_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: ApiClient.instance.baseUrl);
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _signupMode = false;
  bool _showServer = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_signupMode && _password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiClient.instance;
      final server = _server.text.trim().isEmpty ? kDefaultServer : _server.text.trim();
      if (_signupMode) {
        await api.signup(server, _username.text.trim(), _password.text);
      } else {
        await api.login(server, _username.text.trim(), _password.text);
      }
      if (!mounted) return;
      final home = api.role == 'student' ? const StudentHome() : const AdminHome();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => home));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.face_retouching_natural, size: 72, color: Colors.indigo),
                const SizedBox(height: 8),
                Text('Face Attendance', style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  _signupMode ? 'Create your teacher account' : 'Welcome back',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _signupMode ? null : _submit(),
                ),
                if (_signupMode) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm password', border: OutlineInputBorder()),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_showServer) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _server,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      helperText: 'Leave default unless self-hosting',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator())
                      : Text(_signupMode ? 'Create Account' : 'Login'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signupMode = !_signupMode;
                            _error = null;
                          }),
                  child: Text(_signupMode
                      ? 'Already have an account? Login'
                      : 'New teacher? Create an account'),
                ),
                TextButton(
                  onPressed: () => setState(() => _showServer = !_showServer),
                  child: Text(_showServer ? 'Hide server settings' : 'Advanced: server settings',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
