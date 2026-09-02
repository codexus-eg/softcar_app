import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../shell/vouchers_tab.dart';

/// Standalone vouchers page (reached from the Settings tab) — renders the
/// same voucher list the old bottom-bar tab showed, with a back button.
class VouchersScreen extends StatelessWidget {
  const VouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'vouchers'))),
      body: const VouchersTab(),
    );
  }
}