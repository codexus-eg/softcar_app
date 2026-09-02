import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/passenger_api.dart';

/// In-app WebView screen for Visa/Mastercard payment via Cybersource.
/// Opens the hosted checkout page and polls the backend until the
/// PaymentTransaction status becomes AUTHORIZED/PAID or expires.
class PaymentWebViewScreen extends StatefulWidget {
  final String checkoutUrl;
  final String transactionId;
  final double amount;
  final String currency;

  const PaymentWebViewScreen({
    super.key,
    required this.checkoutUrl,
    required this.transactionId,
    required this.amount,
    this.currency = 'EGP',
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;
  Timer? _pollTimer;

  static const _paidStatuses = {'AUTHORIZED', 'PAID', 'COMPLETED'};
  static const _failedStatuses = {
    'FAILED',
    'DECLINED',
    'EXPIRED',
    'CANCELLED',
    'BANK_CHECKOUT_FAILED',
  };

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            _injectConsoleLogger();
            _startPollingIfReady();
          },
          onWebResourceError: (error) {
            debugPrint('[PaymentWebView] Resource error: ${error.description} '
                '(${error.errorCode}) isMain=${error.isForMainFrame}');
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _error = error.description;
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.checkoutUrl),
        headers: {
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      );
  }

  /// Inject JS to capture console.log/warn/error messages from the Cybersource
  /// SDK so we can diagnose why the card form doesn't appear.
  void _injectConsoleLogger() {
    _controller.runJavaScript('''
      (function() {
        var origLog = console.log;
        var origWarn = console.warn;
        var origError = console.error;
        console.log = function() {
          origLog.apply(console, arguments);
          window.consoleMessages = window.consoleMessages || [];
          window.consoleMessages.push({level: 'LOG', args: Array.from(arguments).map(String).join(' ')});
        };
        console.warn = function() {
          origWarn.apply(console, arguments);
          window.consoleMessages = window.consoleMessages || [];
          window.consoleMessages.push({level: 'WARN', args: Array.from(arguments).map(String).join(' ')});
        };
        console.error = function() {
          origError.apply(console, arguments);
          window.consoleMessages = window.consoleMessages || [];
          window.consoleMessages.push({level: 'ERROR', args: Array.from(arguments).map(String).join(' ')});
        };
        window.onerror = function(msg, src, line, col, err) {
          window.consoleMessages = window.consoleMessages || [];
          window.consoleMessages.push({level: 'UNCAUGHT', args: msg + ' at ' + src + ':' + line});
        };
        window.consoleMessages = [];
        // Log VAS SDK availability after a delay.
        setTimeout(function() {
          window.consoleMessages.push({level: 'INFO', args: 'VAS=' + (typeof window.VAS) + ' scripts=' + document.scripts.length});
          var scripts = Array.from(document.scripts).map(function(s) { return s.src || '(inline)'; });
          window.consoleMessages.push({level: 'INFO', args: 'scripts: ' + scripts.join(', ')});
        }, 3000);
      })();
    ''');
  }

  /// Retrieve captured console messages for debugging.
  Future<List<Map<String, String>>> _getConsoleLogs() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'JSON.stringify(window.consoleMessages || [])',
      );
      if (result is String) {
        final List<dynamic> list = jsonDecode(result);
        return list.map<Map<String, String>>((e) => {
          'level': (e['level'] ?? '').toString(),
          'args': (e['args'] ?? '').toString(),
        }).toList();
      }
    } catch (e) {
      debugPrint('[PaymentWebView] Failed to get console logs: $e');
    }
    return [];
  }

  /// Start polling the backend for payment status once the page has loaded.
  void _startPollingIfReady() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStatus());
  }

  int _pollCount = 0;

  Future<void> _pollStatus() async {
    if (_isProcessing) return;
    _pollCount++;
    try {
      final response = await passengerApi.getPaymentStatus(widget.transactionId);
      if (!mounted) return;

      final payment = response['payment'];
      final status = (payment?['status'] ?? '').toString().toUpperCase();
      debugPrint('[PaymentWebView] Poll #$_pollCount status=$status tx=${widget.transactionId}');

      if (_paidStatuses.contains(status)) {
        _pollTimer?.cancel();
        _finish(true);
      } else if (_failedStatuses.contains(status)) {
        _pollTimer?.cancel();
        _finish(false, message: 'Payment was not approved.');
      } else if (_pollCount >= 60) {
        // 60 polls × 3s = 3 minutes. Fetch console logs for diagnosis.
        _pollTimer?.cancel();
        final logs = await _getConsoleLogs();
        debugPrint('[PaymentWebView] Timeout. Console logs: $logs');
        _finish(false, message: 'Payment timed out. Please try again.');
      }
    } catch (e) {
      debugPrint('[PaymentWebView] Poll error: $e');
      // Polling errors are transient; keep trying.
    }
  }

  Future<void> _finish(bool success, {String? message}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final title = success
        ? L10n.t(context, 'paymentSuccessful')
        : L10n.t(context, 'paymentFailed');
    final body = message ??
        (success
            ? L10n.t(context, 'paymentSuccessfulMessage')
                .replaceAll('{amount}', '${widget.amount.toStringAsFixed(0)} ${widget.currency}')
            : L10n.t(context, 'paymentFailedMessage')
                .replaceAll('{error}', 'Payment was not completed'));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error_outline,
          color: success ? AppColors.success : AppColors.error,
          size: 48,
        ),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(success);
            },
            child: Text(L10n.t(context, 'done')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'securePayment')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _pollTimer?.cancel();
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(L10n.t(context, 'cancelPayment')),
                content: Text(L10n.t(context, 'cancelPaymentMessage')),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _startPollingIfReady();
                    },
                    child: Text(L10n.t(context, 'continuePayment')),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop(false);
                    },
                    child: Text(
                      L10n.t(context, 'cancel'),
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

          if (_isLoading && !_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.accent),
                        const SizedBox(height: 16),
                        Text(
                          L10n.t(context, 'verifyingPayment'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_error != null && !_isProcessing)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          L10n.t(context, 'connectionError'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _controller.loadRequest(Uri.parse(widget.checkoutUrl));
                          },
                          child: Text(L10n.t(context, 'retry')),
                        ),
                      ],
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
