import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/common.dart';
import 'data/backend.dart';
import 'data/models.dart';
import 'features/auth/auth_screens.dart';
import 'features/auth/role_screens.dart';
import 'features/driver/driver_shell.dart';
import 'features/mechanic/mechanic_shell.dart';

/// Bump this after onboarding steps so [SessionGate] re-reads the profile.
final sessionVersion = ValueNotifier<int>(0);
void refreshSession() => sessionVersion.value++;

class AutoWaveApp extends StatelessWidget {
  const AutoWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoWave',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SessionGate(),
    );
  }
}

/// Signed out -> welcome. Signed in -> role choice -> (mechanic) workshop setup -> home.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  StreamSubscription<String?>? _sub;
  String? _uid;
  Profile? _profile;
  bool _hasWorkshop = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _uid = backend.currentUserId;
    _sub = backend.userChanges.listen((id) {
      if (id != _uid) {
        _uid = id;
        _load();
      }
    });
    sessionVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    sessionVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_uid == null) {
      setState(() {
        _profile = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final p = await backend.myProfile();
      var hasWorkshop = false;
      if (p?.role == UserRole.mechanic) hasWorkshop = (await backend.myWorkshop()) != null;
      if (!mounted) return;
      setState(() {
        _profile = p;
        _hasWorkshop = hasWorkshop;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.ink, body: Center(child: CircularProgressIndicator(color: AppColors.signal)));
    }
    if (_uid == null) return const WelcomeScreen();
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Can\'t reach AutoWave',
            body: friendlyError(_error!),
            action: Column(children: [
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
              TextButton(onPressed: backend.signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }
    final p = _profile!;
    if (p.role == null) return RoleSelectScreen(profile: p);
    if (p.role == UserRole.mechanic) {
      return _hasWorkshop ? MechanicShell(profile: p) : const WorkshopSetupScreen(firstTime: true);
    }
    return DriverShell(profile: p);
  }
}
