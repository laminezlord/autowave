import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import 'countries.dart';

/// First screen for signed-out users.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Column(
        children: [
          const DemoRibbon(),
          Expanded(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Wordmark(),
                          const SizedBox(height: 56),
                          const Text('Stuck on the road?\nHelp is one tap away.',
                              style: TextStyle(fontFamily: AppText.display, fontSize: 32, height: 1.12, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.6)),
                          const SizedBox(height: 18),
                          const _LaneMarking(),
                          const SizedBox(height: 18),
                          Text(
                            'Find a trusted mechanic near you, track them to your car, and pay safely. Your money is only released when the job is done.',
                            style: AppText.body.copyWith(color: const Color(0xFFC5CCD3), fontSize: 16),
                          ),
                          const SizedBox(height: 40),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneAuthScreen())),
                            icon: const Icon(Icons.phone_iphone_rounded),
                            label: const Text('Continue with phone'),
                          ),
                          const SizedBox(height: 12),
                          _GoogleButton(),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF3B4A59), width: 1.5)),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailAuthScreen())),
                            child: const Text('Continue with email'),
                          ),
                          const SizedBox(height: 20),
                          const Text('Mechanics sign up here too. You\'ll choose your role next.',
                              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E9AA6), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: AppColors.signal, borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.waves_rounded, color: AppColors.ink, size: 24),
        ),
        const SizedBox(width: 10),
        const Text('AutoWave', style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white, letterSpacing: -0.3)),
      ],
    );
  }
}

/// Dashed road-marking line: the brand's one decorative element.
class _LaneMarking extends StatelessWidget {
  const _LaneMarking();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        5,
        (i) => Container(
          width: 26,
          height: 5,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(color: AppColors.signal, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatefulWidget {
  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await backend.signInWithGoogle();
              } catch (e) {
                if (context.mounted) showError(context, e);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: _busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('G', style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF4285F4))),
                SizedBox(width: 10),
                Text('Continue with Google'),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone: number with country picker -> 6-digit code
// ---------------------------------------------------------------------------
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});
  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  Country _country = countryByCode(Env.defaultCountry);
  final _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_country.looksValid(_phone.text)) throw const AppException('Check the phone number.');
    final e164 = _country.toE164(_phone.text);
    await backend.sendPhoneCode(e164);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: e164)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Text('Your phone number', style: AppText.h1),
            const SizedBox(height: 10),
            Text('We\'ll text you a 6-digit code. Mechanics and drivers use this number to reach each other on a job.', style: AppText.body),
            const SizedBox(height: 28),
            PhoneField(country: _country, onCountry: (c) => setState(() => _country = c), controller: _phone, autofocus: true),
            const SizedBox(height: 24),
            BusyButton(label: 'Send code', onPressed: _send),
          ],
        ),
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  int _wait = 30;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _t?.cancel();
    setState(() => _wait = 30);
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _autoVerify() async {
    try {
      await _verify();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _verify() async {
    await backend.verifyPhoneCode(widget.phone, _code.text);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Text('Enter the code', style: AppText.h1),
            const SizedBox(height: 10),
            Text('Sent to ${widget.phone}${backend.isDemo ? '. In demo mode any 6 digits work.' : '.'}', style: AppText.body),
            const SizedBox(height: 28),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              style: const TextStyle(fontFamily: AppText.display, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 14),
              decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              onChanged: (v) {
                if (v.length == 6) _autoVerify();
              },
            ),
            const SizedBox(height: 24),
            BusyButton(label: 'Verify', onPressed: _verify),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _wait > 0
                  ? null
                  : () async {
                      try {
                        await backend.sendPhoneCode(widget.phone);
                        _startTimer();
                        if (context.mounted) showSnack(context, 'New code sent');
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
              child: Text(_wait > 0 ? 'Resend code in ${_wait}s' : 'Resend code'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Email + password
// ---------------------------------------------------------------------------
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});
  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  bool _create = false;
  bool _showPw = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) throw const AppException('Enter a valid email address.');
    if (_pw.text.length < 8) throw const AppException('Use at least 8 characters for your password.');
    if (_create) {
      if (_name.text.trim().length < 2) throw const AppException('Enter your name.');
      final needsConfirm = await backend.signUpWithEmail(fullName: _name.text, email: email, password: _pw.text);
      if (!mounted) return;
      if (needsConfirm) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Check your email'),
            content: Text('We sent a confirmation link to $email. Open it on this phone, then sign in.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        if (mounted) setState(() => _create = false);
        return;
      }
    } else {
      await backend.signInWithEmail(email, _pw.text);
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showSnack(context, 'Type your email above first.');
      return;
    }
    try {
      await backend.resetPassword(email);
      if (mounted) showSnack(context, 'Password reset link sent to $email');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(_create ? 'Create your account' : 'Welcome back', style: AppText.h1),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Sign in')), ButtonSegment(value: true, label: Text('Create account'))],
                selected: {_create},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _create = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.ink,
                  selectedForegroundColor: Colors.white,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.line),
                  textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 20),
              if (_create) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                obscureText: !_showPw,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _create ? 'At least 8 characters' : null,
                  suffixIcon: IconButton(
                    tooltip: _showPw ? 'Hide password' : 'Show password',
                    icon: Icon(_showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPw = !_showPw),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              BusyButton(label: _create ? 'Create account' : 'Sign in', onPressed: _submit),
              if (!_create) TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
            ],
          ),
        ),
      ),
    );
  }
}
