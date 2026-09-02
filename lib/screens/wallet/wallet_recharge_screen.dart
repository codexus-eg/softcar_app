import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../services/passenger_api.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';
import '../payment/payment_webview_screen.dart';

/// Wallet top-up: the passenger picks a channel — a bank transfer (amount +
/// sender phone + a screenshot receipt, POSTed as channel TRANSFER with the
/// screenshot to `/wallet/evidence` for finance review) or a card payment
/// (POSTed as channel CARD, which returns a checkout URL that opens in the
/// system browser to complete the payment).
class WalletRechargeScreen extends StatefulWidget {
  const WalletRechargeScreen({super.key});

  @override
  State<WalletRechargeScreen> createState() => _WalletRechargeScreenState();
}

class _WalletRechargeScreenState extends State<WalletRechargeScreen>
    with WidgetsBindingObserver {
  final _amount = TextEditingController();
  final _sender = TextEditingController();
  XFile? _receipt;
  bool _busy = false;
  bool _isCard = false;

  /// True while we wait for the passenger to return from the card checkout
  /// page so we can verify the payment status against the refreshed wallet.
  bool _pendingCheckout = false;
  bool _checking = false;
  double? _balanceBefore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amount.dispose();
    _sender.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCheckout) {
      _pendingCheckout = false;
      _checkPaymentStatus();
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (picked != null) {
        setState(() => _receipt = picked);
        Haptics.selection();
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _toast(context, L10n.t(context, 'amountRequired'));
      return;
    }
    final sender = _sender.text.trim();
    if (!_isCard) {
      if (sender.isEmpty) {
        _toast(context, L10n.t(context, 'senderRequired'));
        return;
      }
      if (_receipt == null) {
        _toast(context, L10n.t(context, 'receiptRequired'));
        return;
      }
    }
    setState(() => _busy = true);
    final wallet = context.read<WalletService>();
    try {
      final json = await wallet.requestRecharge(
        amount: amount,
        senderNumber: _isCard ? '' : sender,
        channel: _isCard ? 'CARD' : 'TRANSFER',
      );
      if (_isCard) {
        final url = _checkoutUrl(json);
        final txId = json['transaction'] is Map
            ? json['transaction']['id']?.toString()
            : json['id']?.toString();
        if (!mounted) return;
        if (url != null && txId != null) {
          // Navigate to in-app WebView for secure payment
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => PaymentWebViewScreen(
                checkoutUrl: url,
                transactionId: txId,
                amount: amount,
              ),
            ),
          );
          
          if (mounted) {
            setState(() => _busy = false);
            if (result == true) {
              // Payment successful
              Haptics.success();
              _showStatus(
                icon: Icons.check_circle,
                iconColor: AppColors.success,
                title: L10n.t(context, 'paymentConfirmed'),
                body: L10n.t(context, 'paymentConfirmedSub'),
              );
            } else {
              // Payment cancelled or failed
              _showSubmitted();
            }
          }
        } else {
          Haptics.success();
          _showSubmitted();
          if (mounted) setState(() => _busy = false);
        }
        return;
      }
      final txId = _findTxId(json);
      if (txId != null) {
        final bytes = await _receipt!.readAsBytes();
        await wallet.submitEvidence(
          transactionId: txId,
          bytes: bytes,
          contentType:
              _receipt!.name.endsWith('.png') ? 'image/png' : 'image/jpeg',
        );
      }
      if (!mounted) return;
      Haptics.success();
      _showSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e is PassengerApiException && e.status == 409) {
        // Backend-limit rejections (WALLET_TOPUP_LIMIT_REACHED /
        // WALLET_TOPUP_DUPLICATE) carry a human-readable Arabic message we
        // surface verbatim instead of the generic failure toast.
        _toast(context, e.message);
      } else {
        _toast(context, '${L10n.t(context, 'rechargeFailed')} $e');
      }
    }
  }

  /// Pulls the hosted-checkout URL out of the card recharge response. The
  /// backend nests it either under `checkout`, the created `transaction` or
  /// at the top level.
  String? _checkoutUrl(Map<String, dynamic> json) {
    String? first(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return null;
    }

    final checkout = json['checkout'];
    if (checkout is Map) {
      final url = first(Map<String, dynamic>.from(checkout), [
        'url',
        'checkoutUrl',
      ]);
      if (url != null) return url;
    }
    final tx = json['transaction'];
    if (tx is Map) {
      final url = first(Map<String, dynamic>.from(tx), ['checkoutUrl', 'url']);
      if (url != null) return url;
    }
    return first(json, ['checkoutUrl', 'url']);
  }

  String? _findTxId(Map<String, dynamic> json) {
    final direct = json['id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final tx = json['transaction'] ?? json['topup'];
    if (tx is Map) {
      final id = tx['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  void _showSubmitted() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: AppColors.accent,
              size: 40,
            ),
            title: Text(L10n.t(ctx, 'rechargeSubmitted')),
            content: Text(L10n.t(ctx, 'rechargePending')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).popUntil((r) => r.isFirst),
                child: Text(L10n.t(ctx, 'done')),
              ),
            ],
          ),
    );
  }

  /// After the passenger returns from the hosted card checkout, re-fetches
  /// the wallet and reports whether the recharge landed or is still pending.
  Future<void> _checkPaymentStatus() async {
    if (_checking) return;
    _checking = true;
    if (mounted) setState(() {});
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            icon: const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            title: Text(L10n.t(ctx, 'checkingPayment')),
            content: Text(L10n.t(ctx, 'cardCheckoutNote')),
          ),
    );
    try {
      final wallet = context.read<WalletService>();
      await wallet.refresh();
      if (!mounted) return;
      final credited =
          _balanceBefore != null &&
          wallet.data.balance > (_balanceBefore ?? 0) + 0.01;
      Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      if (credited) {
        Haptics.success();
        _showStatus(
          icon: Icons.check_circle,
          iconColor: AppColors.success,
          title: L10n.t(context, 'paymentConfirmed'),
          body: L10n.t(context, 'paymentConfirmedSub'),
        );
      } else {
        _showStatus(
          icon: Icons.hourglass_top_rounded,
          iconColor: AppColors.warning,
          title: L10n.t(context, 'paymentStillPending'),
          body: L10n.t(context, 'paymentStillPendingSub'),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showStatus({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            icon: Icon(icon, color: iconColor, size: 40),
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'done')),
              ),
            ],
          ),
    );
  }

  void _toast(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final recipient = _recipientNumber(wallet);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'rechargeWallet'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      L10n.t(context, 'availableBalance'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${wallet.data.balance.toStringAsFixed(0)} EGP',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (wallet.data.status == 'PENDING_REVIEW') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      L10n.t(context, 'pendingReview'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (wallet.pendingTopups >= 1) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'pendingTopupsCount')
                          .replaceFirst('{count}', '${wallet.pendingTopups}')
                          .replaceFirst('{max}', '2'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'transfer',
                icon: const Icon(
                  Icons.account_balance_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                label: Text(L10n.t(context, 'channelTransfer')),
              ),
              ButtonSegment(
                value: 'card',
                icon: const Icon(
                  Icons.credit_card_rounded,
                  size: 18,
                  color: AppColors.accent,
                ),
                label: Text(L10n.t(context, 'channelCard')),
              ),
            ],
            selected: {_isCard ? 'card' : 'transfer'},
            onSelectionChanged: (selection) {
              setState(() => _isCard = selection.contains('card'));
              Haptics.selection();
            },
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          if (!_isCard && recipient.isNotEmpty) ...[
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'walletInstructions'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          recipient,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: recipient),
                          );
                          if (!context.mounted) return;
                          Haptics.success();
                          _toast(context, L10n.t(context, 'numberCopied'));
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(L10n.t(context, 'copyNumber')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: L10n.t(context, 'rechargeAmount'),
              prefixIcon: const Icon(Icons.payments_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          if (_isCard) ...[
            SoftCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'cardCheckoutNote'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            TextField(
              controller: _sender,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              decoration: InputDecoration(
                labelText: L10n.t(context, 'senderNumber'),
                prefixIcon: const Icon(Icons.phone_iphone, size: 20),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickReceipt,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      _receipt == null
                          ? AppColors.accentSoft
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        _receipt == null ? AppColors.accent : AppColors.success,
                  ),
                ),
                child:
                    _receipt == null
                        ? Column(
                          children: [
                            const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 32,
                              color: AppColors.accent,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              L10n.t(context, 'uploadReceipt'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              L10n.t(context, 'uploadReceiptSub'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                        : Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    L10n.t(context, 'receiptUploaded'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _receipt!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _pickReceipt,
                              child: Text(L10n.t(context, 'changePhoto')),
                            ),
                          ],
                        ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label:
                wallet.pendingTopups >= 2
                    ? L10n.t(context, 'pendingTopupsBlocked')
                    : L10n.t(context, 'submitRecharge'),
            icon: Icons.send_outlined,
            loading: _busy,
            onPressed: (_busy || wallet.pendingTopups >= 2) ? null : _submit,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _recipientNumber(WalletService wallet) {
    // The GET /wallet/transactions payload includes the wallet's recipient
    // number so passengers know where to transfer.
    final raw = wallet.data.transactions;
    for (final t in raw) {
      final r = t['recipientNumber']?.toString();
      if (r != null && r.isNotEmpty) return r;
    }
    return '';
  }
}
