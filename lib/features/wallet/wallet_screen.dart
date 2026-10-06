import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';

class WalletScreen extends StatefulWidget {
  final UserRole role;
  const WalletScreen({super.key, required this.role});
  @override
  State<WalletScreen> createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  WalletSummary? _s;
  List<WalletTxn>? _txns;
  Object? _error;

  bool get _mechanic => widget.role == UserRole.mechanic;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait([backend.walletSummary(), backend.transactions()]);
      if (!mounted) return;
      setState(() {
        _s = r[0] as WalletSummary;
        _txns = r[1] as List<WalletTxn>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (_error != null && s == null)
              EmptyState(icon: Icons.cloud_off_rounded, title: 'Couldn\'t load your wallet', body: friendlyError(_error!), action: OutlinedButton(onPressed: refresh, child: const Text('Try again')))
            else if (s == null)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else ...[
              _balanceCard(s),
              const SizedBox(height: 20),
              _escrowExplainer(),
              const SizedBox(height: 24),
              const Text('Activity', style: AppText.h3),
              const SizedBox(height: 6),
              if ((_txns ?? const []).isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No activity yet.', style: AppText.body.copyWith(color: AppColors.muted)))
              else
                for (final t in _txns!) _TxnRow(t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(WalletSummary s) {
    final held = _mechanic ? s.incomingKobo : s.inEscrowKobo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Available', style: TextStyle(color: Color(0xFFC5CCD3), fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(formatNaira(s.availableKobo), style: AppText.money.copyWith(color: Colors.white, fontSize: 38)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF223140), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.lock_rounded, size: 18, color: AppColors.signal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_mechanic ? 'Secured for you in escrow' : 'Held in escrow for jobs', style: const TextStyle(color: Color(0xFFE2E6EA), fontWeight: FontWeight.w500)),
            ),
            Text(formatNaira(held), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink, minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                if (_mechanic) {
                  await showWithdrawSheet(context, s.availableKobo);
                } else {
                  await showTopUpSheet(context, s);
                }
                refresh();
              },
              icon: Icon(_mechanic ? Icons.south_west_rounded : Icons.add_rounded),
              label: Text(_mechanic ? 'Withdraw' : 'Add money'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF3B4A59), width: 1.5), minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                if (_mechanic) {
                  await showTopUpSheet(context, s);
                } else {
                  await showWithdrawSheet(context, s.availableKobo);
                }
                refresh();
              },
              child: Text(_mechanic ? 'Add money' : 'Withdraw'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _escrowExplainer() {
    final steps = _mechanic
        ? const [
            ('Driver pays into escrow', 'You see the money is secured before you start work.'),
            ('You finish the job', 'Mark it complete in your jobs.'),
            ('Driver confirms', 'The money moves to your available balance. If they don\'t respond, it\'s released automatically after 48 hours.'),
          ]
        : const [
            ('You pay into escrow', 'After the mechanic accepts and sets a price.'),
            ('AutoWave holds it', 'The mechanic sees it\'s paid but can\'t take it yet.'),
            ('You confirm the job', 'Only then is the money released. Cancelled before work starts? Full refund.'),
          ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('How escrow payments work', style: AppText.title),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.goSoft, borderRadius: BorderRadius.circular(8)),
                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.go)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].$1, style: AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
                  Text(steps[i].$2, style: AppText.small),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final WalletTxn t;
  const _TxnRow(this.t);

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title) = switch (t.kind) {
      'topup' => (Icons.add_card_rounded, AppColors.go, 'Added money'),
      'test_topup' => (Icons.science_outlined, AppColors.muted, 'Test money'),
      'escrow_hold' => (Icons.lock_rounded, AppColors.ink, 'Paid into escrow'),
      'escrow_release' => t.amountKobo >= 0 ? (Icons.payments_rounded, AppColors.go, 'Job payment received') : (Icons.check_circle_rounded, AppColors.ink, 'Paid to mechanic'),
      'escrow_refund' => (Icons.undo_rounded, AppColors.go, 'Refund'),
      'escrow_incoming' => (Icons.hourglass_top_rounded, AppColors.info, 'Waiting for driver to confirm'),
      'withdrawal' => (Icons.south_west_rounded, AppColors.ink, 'Withdrawal'),
      'withdrawal_reversal' => (Icons.undo_rounded, AppColors.go, 'Withdrawal returned'),
      'recycling_payout' => (Icons.recycling_rounded, AppColors.go, 'Recycling payment'),
      _ => (Icons.swap_horiz_rounded, AppColors.ink, 'Transaction'),
    };
    final amount = t.amountKobo == 0 ? '' : (t.amountKobo > 0 ? '+${formatNaira(t.amountKobo)}' : '−${formatNaira(-t.amountKobo)}');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)), child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
            Text([if ((t.description ?? '').isNotEmpty) t.description!, formatDateTime(t.createdAt)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
          ]),
        ),
        Text(amount, style: TextStyle(fontWeight: FontWeight.w800, color: t.amountKobo > 0 ? AppColors.go : AppColors.ink)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Add money (Paystack) — returns true if the balance went up.
// ---------------------------------------------------------------------------
Future<bool?> showTopUpSheet(BuildContext context, WalletSummary s, {int? suggestedKobo}) {
  return showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _TopUpSheet(summary: s, suggested: suggestedKobo));
}

class _TopUpSheet extends StatefulWidget {
  final WalletSummary summary;
  final int? suggested;
  const _TopUpSheet({required this.summary, this.suggested});
  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  late final _amount = TextEditingController(text: widget.suggested == null ? '' : (widget.suggested! / 100).ceil().toString());

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int _kobo() {
    final k = parseNairaToKobo(_amount.text);
    if (k == null || k < 10000) throw const AppException('Enter at least ₦100.');
    if (k > 50000000) throw const AppException('The most you can add at once is ₦500,000.');
    return k;
  }

  Future<void> _paystack() async {
    final k = _kobo();
    final t = await backend.startTopup(k);
    await launchUrl(Uri.parse(t.url), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    // Back from Paystack: check the payment (the webhook usually got there first).
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _VerifyDialog(reference: t.reference));
    if (mounted) Navigator.pop(context, ok == true);
  }

  Future<void> _test() async {
    await backend.testTopup(_kobo());
    if (!mounted) return;
    showSnack(context, 'Test money added');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Add money', style: AppText.h2),
        const SizedBox(height: 4),
        Text('Balance: ${formatNaira(widget.summary.availableKobo)}', style: AppText.small),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: widget.suggested == null,
          keyboardType: TextInputType.number,
          style: AppText.h2,
          decoration: const InputDecoration(prefixText: '₦ ', hintText: '10,000'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final v in [5000, 10000, 20000, 50000]) ActionChip(label: Text(formatNaira(v * 100)), onPressed: () => setState(() => _amount.text = '$v')),
        ]),
        const SizedBox(height: 20),
        if (!backend.isDemo) BusyButton(label: 'Pay with card, transfer or USSD', icon: Icons.lock_rounded, onPressed: _paystack),
        if (!backend.isDemo)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Secured by Paystack. You\'ll come back here when you\'re done.', textAlign: TextAlign.center, style: AppText.small)),
        if (widget.summary.allowTestTopups) ...[
          const SizedBox(height: 10),
          OutlinedButtonTheme(
            data: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
            child: _TestButton(onPressed: _test),
          ),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Test money isn\'t real. It\'s for trying escrow before Paystack is live.', textAlign: TextAlign.center, style: AppText.small)),
        ],
      ]),
    );
  }
}

class _TestButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  const _TestButton({required this.onPressed});
  @override
  State<_TestButton> createState() => _TestButtonState();
}

class _TestButtonState extends State<_TestButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await widget.onPressed();
                } catch (e) {
                  if (context.mounted) showError(context, e);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.science_outlined),
        label: const Text('Add test money'),
      );
}

class _VerifyDialog extends StatefulWidget {
  final String reference;
  const _VerifyDialog({required this.reference});
  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  String _status = 'pending';
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final s = await backend.verifyTopup(widget.reference);
      if (!mounted) return;
      setState(() => _status = s);
      if (s == 'success') {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = switch (_status) {
      'success' => 'Payment received. Your wallet has been topped up.',
      'failed' => 'The payment didn\'t go through. Nothing was charged.',
      _ => 'Finished paying on Paystack? Tap below to update your balance.',
    };
    return AlertDialog(
      title: const Text('Checking your payment'),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _status == 'success'), child: Text(_status == 'pending' ? 'Close' : 'Done')),
        if (_status == 'pending')
          TextButton(onPressed: _checking ? null : _check, child: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('I\'ve paid')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Withdraw to bank
// ---------------------------------------------------------------------------
Future<void> showWithdrawSheet(BuildContext context, int availableKobo) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _WithdrawSheet(available: availableKobo));
}

class _WithdrawSheet extends StatefulWidget {
  final int available;
  const _WithdrawSheet({required this.available});
  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  PayoutAccount? _account;
  bool _loading = true;
  bool _editing = false;
  List<Bank> _banks = const [];
  Bank? _bank;
  final _number = TextEditingController();
  final _amount = TextEditingController();
  String? _resolvedName;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _account = await backend.payoutAccount();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    if (_account == null) _startEditing();
  }

  Future<void> _startEditing() async {
    setState(() => _editing = true);
    if (_banks.isNotEmpty) return;
    try {
      final b = await backend.banks();
      if (mounted) setState(() => _banks = b);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _resolve() async {
    if (_bank == null || _number.text.length != 10) return;
    setState(() {
      _resolving = true;
      _resolvedName = null;
    });
    try {
      final n = await backend.resolveAccount(_number.text, _bank!.code);
      if (mounted) setState(() => _resolvedName = n);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _saveAccount() async {
    if (_bank == null) throw const AppException('Choose your bank.');
    if (!RegExp(r'^\d{10}$').hasMatch(_number.text)) throw const AppException('Account numbers have 10 digits.');
    final a = PayoutAccount(bankName: _bank!.name, bankCode: _bank!.code, accountNumber: _number.text, accountName: _resolvedName);
    await backend.savePayoutAccount(a);
    if (mounted) {
      setState(() {
        _account = a;
        _editing = false;
      });
    }
  }

  Future<void> _withdraw() async {
    final k = parseNairaToKobo(_amount.text);
    if (k == null || k < 10000) throw const AppException('The minimum withdrawal is ₦100.');
    if (k > widget.available) throw const AppException('That\'s more than your available balance.');
    final msg = await backend.withdraw(k);
    if (!mounted) return;
    showSnack(context, msg);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_editing ? 'Your bank account' : 'Withdraw to bank', style: AppText.h2),
              const SizedBox(height: 16),
              if (_editing) ...[
                DropdownButtonFormField<Bank>(
                  initialValue: _bank,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  items: [for (final b in _banks) DropdownMenuItem(value: b, child: Text(b.name))],
                  onChanged: (b) {
                    setState(() => _bank = b);
                    _resolve();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _number,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  decoration: const InputDecoration(labelText: 'Account number', counterText: ''),
                  onChanged: (v) {
                    if (v.length == 10) _resolve();
                  },
                ),
                const SizedBox(height: 8),
                if (_resolving) Text('Checking account…', style: AppText.small),
                if (_resolvedName != null) Text(_resolvedName!, style: AppText.title.copyWith(color: AppColors.go)),
                const SizedBox(height: 16),
                BusyButton(label: 'Save account', onPressed: _saveAccount),
              ] else ...[
                Panel(
                  color: AppColors.surface,
                  child: Row(children: [
                    const Icon(Icons.account_balance_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_account!.accountName ?? _account!.bankName, style: AppText.title),
                        Text('${_account!.bankName} · ${_account!.accountNumber}', style: AppText.small),
                      ]),
                    ),
                    TextButton(onPressed: _startEditing, child: const Text('Change')),
                  ]),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  style: AppText.h2,
                  decoration: InputDecoration(prefixText: '₦ ', hintText: '0', helperText: 'Available: ${formatNaira(widget.available)}'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setState(() => _amount.text = '${widget.available ~/ 100}'), child: const Text('Withdraw everything')),
                ),
                const SizedBox(height: 8),
                BusyButton(label: 'Withdraw', onPressed: widget.available < 10000 ? null : _withdraw),
              ],
            ]),
    );
  }
}
