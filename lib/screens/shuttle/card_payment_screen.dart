import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import '../../models/shuttle.dart';
import '../../services/passenger_api.dart';
import '../../services/reservation_service.dart';
import 'card_payment_flow.dart';

/// Displays the SoftCar-hosted Cybersource Unified Checkout inside the app.
///
/// Card fields and 3-D Secure screens are rendered by Cybersource; this app
/// only loads the opaque checkout URL and polls our server for the verified,
/// signed result. No PAN or CVV is exposed to Flutter or the SoftCar API.
class CardPaymentScreen extends StatefulWidget {
  const CardPaymentScreen({
    super.key,
    this.ticket,
    this.amount,
    required this.transactionId,
    required this.checkoutUrl,
  }) : assert(ticket != null || amount != null);

  final Ticket? ticket;
  final double? amount;
  final String transactionId;
  final String checkoutUrl;

  @override
  State<CardPaymentScreen> createState() => _CardPaymentScreenState();
}

class _CardPaymentScreenState extends State<CardPaymentScreen>
    with WidgetsBindingObserver {
  late final WebViewController _webView;
  late String _transactionId;
  late String _checkoutUrl;
  late final CardPaymentFlow _flow;
  Timer? _timer;
  bool _pageLoading = true;
  bool _checking = false;
  bool _terminalFailure = false;
  bool _restarting = false;
  String? _error;

  double get _amount => widget.amount ?? widget.ticket?.total ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transactionId = widget.transactionId;
    _checkoutUrl = widget.checkoutUrl;
    _flow = CardPaymentFlow(
      fetchStatus: (transactionId) =>
          passengerApi.getCardPaymentStatus(transactionId),
    );
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF020617))
      ..addJavaScriptChannel(
        'SoftCarCheckout',
        onMessageReceived: _handleCheckoutMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _pageLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _pageLoading = false;
                if (!_terminalFailure) _error = null;
              });
            }
            unawaited(_checkStatus());
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (target == null) return NavigationDecision.prevent;
            if (target.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            if (target.scheme != 'http') {
              unawaited(
                launchUrl(target, mode: LaunchMode.externalApplication),
              );
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (failure) {
            if (failure.isForMainFrame != true || !mounted) return;
            setState(() {
              _pageLoading = false;
              _terminalFailure = false;
              _error =
                  'Could not load the secure bank page: ${failure.description}';
            });
          },
        ),
      );
    unawaited(_prepareWebViewAndLoad());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
  }

  Future<void> _prepareWebViewAndLoad() async {
    final platformController = _webView.platform;
    if (platformController is AndroidWebViewController) {
      // Cybersource hosts the card fields and 3-D Secure challenge in secure
      // cross-site frames. Android WebView disables third-party cookies by
      // default, which can prevent those bank frames from initializing.
      final cookieManager = WebViewCookieManager();
      final platformCookieManager = cookieManager.platform;
      if (platformCookieManager is AndroidWebViewCookieManager) {
        try {
          await platformCookieManager.setAcceptThirdPartyCookies(
            platformController,
            true,
          );
        } catch (_) {
          // Continue loading: some Android WebView builds do not expose this
          // setting even though the hosted form can still work without it.
        }
      }
    }
    await _loadCheckout(_checkoutUrl);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkStatus());
  }

  void _handleCheckoutMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      final status = decoded['status']?.toString() ?? '';
      if (status.trim().toUpperCase() == 'CLOSE') {
        unawaited(_returnToBooking());
        return;
      }
      // The bridge is only a trigger for an authenticated re-check; the API
      // response is the sole source of truth for whether payment completed.
      if (_flow.shouldRecheck(status)) unawaited(_checkStatus());
    } catch (_) {
      // Ignore malformed page messages and keep polling the authenticated API.
    }
  }

  Future<void> _loadCheckout(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      if (!mounted) return;
      setState(() {
        _terminalFailure = false;
        _error = 'The secure payment link is invalid.';
        _pageLoading = false;
      });
      return;
    }
    await _webView.loadRequest(uri);
  }

  Future<void> _checkStatus() async {
    if (_flow.checking || _flow.completed || !mounted) return;
    setState(() => _checking = true);
    final result = await _flow.check(_transactionId);
    if (!mounted) return;
    if (result.outcome == CardPaymentStatusResult.completed) {
      _timer?.cancel();
      final ticket = widget.ticket;
      if (ticket == null) {
        Navigator.of(context).pop(true);
        return;
      }

      final reservations = context.read<ReservationService>();
      await reservations.syncFromLive();
      final paidTicket =
          reservations.byId(ticket.id) ??
          ticket.copyWith(paymentStatus: 'PAID');
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed('/booking-success', arguments: paidTicket);
      return;
    }
    setState(() {
      _checking = false;
      if (result.outcome == CardPaymentStatusResult.terminal) {
        _terminalFailure = true;
        _error =
            result.terminalMessage ??
            'The bank did not complete this payment. No payment was recorded.';
      }
    });
  }

  Future<void> _restartPayment() async {
    final ticket = widget.ticket;
    if (ticket == null) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    if (_restarting) return;
    setState(() => _restarting = true);
    try {
      final payment = await passengerApi.createCardPaymentSession(ticket.id);
      final transactionId = payment['transactionId']?.toString() ?? '';
      final checkoutUrl = payment['checkoutUrl']?.toString() ?? '';
      if (transactionId.isEmpty || checkoutUrl.isEmpty) {
        throw const PassengerApiException(
          'The bank did not return a secure checkout link.',
        );
      }
      _transactionId = transactionId;
      _checkoutUrl = checkoutUrl;
      if (!mounted) return;
      setState(() {
        _terminalFailure = false;
        _error = null;
        _pageLoading = true;
      });
      await _loadCheckout(checkoutUrl);
    } on PassengerApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Future<void> _close() async {
    await _checkStatus();
    if (!mounted || _flow.completed) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave card payment?'),
        content: const Text(
          'Your reservation will not be marked paid unless the bank completes and signs the transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue payment'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _returnToBooking() async {
    await _checkStatus();
    if (!mounted || _flow.completed) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _pageLoading = true;
    });
    await _loadCheckout(_checkoutUrl);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Secure card payment'),
              Text(
                'Cybersource · 3-D Secure',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.accentSoft,
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_amount.toStringAsFixed(2)} EGP · Meeza · Visa · Mastercard',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (_checking)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: WebViewWidget(controller: _webView)),
                  if (_pageLoading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0xFF020617),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  if (_error != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Color(0xFFF8FAFC),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_off_rounded,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                SizedBox(height: 14),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: _restarting
                                      ? null
                                      : _terminalFailure
                                      ? _restartPayment
                                      : _reload,
                                  icon: _restarting
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                          ),
                                        )
                                      : Icon(Icons.refresh_rounded),
                                  label: Text(
                                    _terminalFailure
                                        ? 'Try payment again'
                                        : 'Try again',
                                  ),
                                ),
                                if (_terminalFailure) ...[
                                  SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _restarting
                                        ? null
                                        : () =>
                                              Navigator.of(context).pop(false),
                                    child: Text('Return to booking'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
