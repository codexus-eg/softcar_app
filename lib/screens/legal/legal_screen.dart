import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';

/// Global Terms of Service + Privacy Policy (uber-style), fully localized in
/// English and Arabic. Opened from the register screen's "I agree" checkbox
/// and from profile -> Terms & policies.
class LegalScreen extends StatefulWidget {
  /// If [tab] is 'privacy' the screen opens on the Privacy tab first.
  final String initialTab;
  const LegalScreen({super.key, this.initialTab = 'terms'});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late String _tab = widget.initialTab == 'privacy' ? 'privacy' : 'terms';

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 'terms'
            ? L10n.t(context, 'termsTitle')
            : L10n.t(context, 'privacyTitle')),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: L10n.t(context, 'termsTitle'),
                    selected: _tab == 'terms',
                    onTap: () => setState(() => _tab = 'terms'),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    label: L10n.t(context, 'privacyTitle'),
                    selected: _tab == 'privacy',
                    onTap: () => setState(() => _tab = 'privacy'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              child: _tab == 'terms'
                  ? _TermsContent(isArabic: isArabic)
                  : _PrivacyContent(
                      isArabic: isArabic, isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> paragraphs;
  final String? bullet;
  const _Section({required this.title, required this.paragraphs, this.bullet});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDarkElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.35)),
          const SizedBox(height: 8),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                bullet == null ? p : '•  $p',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: dark ? Colors.white70 : AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms of Service
// ---------------------------------------------------------------------------
class _TermsContent extends StatelessWidget {
  final bool isArabic;
  const _TermsContent({required this.isArabic});

  @override
  Widget build(BuildContext context) {
    final t = isArabic ? _arTerms : _enTerms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LastUpdated(label: t['updated']),
        for (final s in t['sections'] as List) _sectionFromMap(s),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy Policy
// ---------------------------------------------------------------------------
class _PrivacyContent extends StatelessWidget {
  final bool isArabic;
  final bool isDark;
  const _PrivacyContent({required this.isArabic, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final t = isArabic ? _arPrivacy : _enPrivacy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LastUpdated(label: t['updated']),
        for (final s in t['sections'] as List) _sectionFromMap(s),
      ],
    );
  }
}

class _LastUpdated extends StatelessWidget {
  final String label;
  const _LastUpdated({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 2),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary, height: 1.4),
      ),
    );
  }
}

_Section _sectionFromMap(Object? raw) {
  final map = Map<String, dynamic>.from(raw as Map);
  return _Section(
    title: map['title'] as String,
    paragraphs: (map['body'] as List).cast<String>(),
    bullet: map['bullet'] as String?,
  );
}

// ---------------------------------------------------------------------------
// Content maps
// ---------------------------------------------------------------------------
const _enTerms = <String, dynamic>{
  'updated': 'Last updated: 10 August 2026',
  'sections': [
    {
      'title': '1. Welcome to SoftCar',
      'body': [
        'These Terms of Service govern your use of the SoftCar mobile application and shuttle booking services provided by SoftCar.',
        'By creating an account, booking a seat, or using any SoftCar service, you agree to these terms. If you do not agree, please do not use the service.',
      ],
    },
    {
      'title': '2. Your account',
      'body': [
        'You must provide accurate and complete information when creating your account, including a valid Egyptian phone number.',
        'You are responsible for keeping your password confidential and for all activity under your account. Contact support immediately if you suspect unauthorised access.',
      ],
    },
    {
      'title': '3. Booking seats',
      'body': [
        'A booking reserves your seat on a scheduled shuttle trip. Prices shown are per seat and do not include taxes and service fees unless stated.',
        'Your seat is held once your booking is confirmed and a ticket code is issued. Boarding requires a valid ticket for the exact trip.',
      ],
    },
    {
      'title': '4. Payments',
      'body': [
        'Tickets may be paid by cash on arrival, by wallet balance, or by card where available.',
        'Wallet top-ups are reviewed by our finance team once proof of payment is uploaded. Wallet funds are non-refundable except where required by law.',
      ],
      'bullet': 'No OTP is ever requested by SoftCar over the phone for payments.',
    },
    {
      'title': '5. Cancellations & refunds',
      'body': [
        'Cancellation rules depend on the trip and how close it is to departure. Refunds, when applicable, are returned to your wallet or original payment method.',
        'No-shows are not eligible for refunds.',
      ],
    },
    {
      'title': '6. Conduct & safety',
      'body': [
        'You agree to behave respectfully towards drivers and fellow passengers, follow safety instructions, and not disrupt the trip.',
        'SoftCar may cancel a booking or suspend an account for abusive, illegal, or unsafe behaviour.',
      ],
    },
    {
      'title': '7. Liability',
      'body': [
        'SoftCar provides transport via licensed operators and drivers. Our liability is limited to the maximum extent permitted by applicable law.',
        'We are not liable for delays caused by traffic, weather, or events outside our reasonable control.',
      ],
    },
    {
      'title': '8. Changes & termination',
      'body': [
        'We may update these terms from time to time. Continued use after changes take effect means you accept the updated terms.',
        'We may suspend or terminate your access at any time for violating these terms.',
      ],
    },
    {
      'title': '9. Contact',
      'body': [
        'Questions about these terms can be sent to support@softcar.app or through the in-app chat.',
      ],
    },
  ],
};

const _enPrivacy = <String, dynamic>{
  'updated': 'Last updated: 10 August 2026',
  'sections': [
    {
      'title': '1. What we collect',
      'body': [
        'We collect information you provide directly: name, phone number, optional email, gender (used for seat colouring), password, and photos you upload.',
        'We also collect booking data (trips, seats, tickets), wallet transactions, device and push-notification tokens, and app usage information.',
      ],
    },
    {
      'title': '2. How we use your data',
      'body': [
        'To provide and operate the shuttle booking service, issue tickets, process wallet top-ups, send booking and trip notifications, and offer customer support.',
        'Gender is used only to colour your available seats at boarding and is never sold or shared for marketing.',
      ],
    },
    {
      'title': '3. SMS & OTP',
      'body': [
        'We send a one-time password (OTP) by SMS to verify your phone number when registering, signing in, or resetting your password.',
        'SMS delivery is provided by a third-party messaging provider. Only the verification code is sent; we never share your number with advertisers.',
      ],
    },
    {
      'title': '4. Sharing your data',
      'body': [
        'We share only the minimum necessary with: drivers (your name and seat colour for boarding), payment and SMS providers, and our finance team (for wallet top-up review).',
        'We never sell your personal data.',
      ],
    },
    {
      'title': '5. Photos & uploads',
      'body': [
        'Profile photos and wallet recharge evidence are stored securely and visible only to you and authorised SoftCar staff.',
      ],
    },
    {
      'title': '6. Notifications',
      'body': [
        'With your permission we send push notifications about bookings, trips, and support. You can disable them at any time in Settings.',
      ],
    },
    {
      'title': '7. Security',
      'body': [
        'We use encryption in transit, hashed session tokens, and access controls to protect your data. No system is 100% secure, but we work hard to keep yours safe.',
      ],
    },
    {
      'title': '8. Your rights',
      'body': [
        'You may access, correct, or delete your account data at any time. Deleting your account is permanent and cannot be undone.',
        'You may also opt out of marketing and notification channels in Settings.',
      ],
    },
    {
      'title': '9. Contact',
      'body': [
        'Privacy questions: support@softcar.app.',
      ],
    },
  ],
};

const _arTerms = <String, dynamic>{
  'updated': 'آخر تحديث: 10 أغسطس 2026',
  'sections': [
    {
      'title': '1. مرحبًا بك في سوفت كار',
      'body': [
        'تحكم هذه الشروط في استخدامك لتطبيق سوفت كار وخدمات حجز الشاتل التي تقدمها سوفت كار.',
        'بإنشائك حسابًا أو حجز مقعد أو استخدام أي خدمة من خدمات سوفت كار فأنت توافق على هذه الشروط. إذا لم توافق، فيرجى عدم استخدام الخدمة.',
      ],
    },
    {
      'title': '2. حسابك',
      'body': [
        'يجب عليك تقديم معلومات دقيقة وكاملة عند إنشاء حسابك، بما في ذلك رقم هاتف مصري صالح.',
        'أنت مسؤول عن الحفاظ على سرية كلمة المرور وعن جميع الأنشطة التي تتم من حسابك. تواصل مع الدعم فورًا إذا اشتبهت في وصول غير مصرح به.',
      ],
    },
    {
      'title': '3. حجز المقاعد',
      'body': [
        'الحجز يحجز مقعدك في رحلة شاتل مجدولة. الأسعار المعروضة لكل مقعد ولا تشمل الضرائب ورسوم الخدمة ما لم يُذكر خلاف ذلك.',
        'يُثبَّت مقعدك بمجرد تأكيد الحجز وإصدار رمز التذكرة. يتطلب الصعود تذكرة صالحة للرحلة نفسها.',
      ],
    },
    {
      'title': '4. الدفع',
      'body': [
        'يمكن دفع التذاكر نقدًا عند الوصول أو من رصيد المحفظة أو بالبطاقة حيثما توفرت.',
        'تراجع فريق المالية لدينا عمليات شحن المحفظة بعد تحميل إثبات الدفع. أموال المحفظة غير قابلة للاسترداد إلا حيث يقتضي القانون ذلك.',
      ],
      'bullet': 'لا تطلب سوفت كار أبدًا رمز OTP عبر الهاتف بخصوص عمليات الدفع.',
    },
    {
      'title': '5. الإلغاء والاسترداد',
      'body': [
        'تعتمد قواعد الإلغاء على الرحلة ومدى قرب موعد الانطلاق. تُعاد المبالغ المستحقة إلى محفظتك أو وسيلة الدفع الأصلية.',
        'عدم الحضور لا يؤهل للاسترداد.',
      ],
    },
    {
      'title': '6. السلوك والأمان',
      'body': [
        'توافق على التصرف باحترام تجاه السائقين والركاب واتباع تعليمات السلامة وعدم تعطيل الرحلة.',
        'يجوز لسوفت كار إلغاء الحجز أو تعليق الحساب بسبب السلوك المسيء أو غير القانوني أو غير الآمن.',
      ],
    },
    {
      'title': '7. المسؤولية',
      'body': [
        'توفر سوفت كار النقل عبر مشغلين وسائقين مرخصين. تقتصر مسؤوليتنا على أقصى حد يسمح به القانون.',
        'لسنا مسؤولين عن التأخير الناتج عن حركة المرور أو الطقس أو أحداث خارجة عن سيطرتنا.',
      ],
    },
    {
      'title': '8. التغييرات والإنهاء',
      'body': [
        'قد نحدّث هذه الشروط من وقت لآخر. استمرار استخدامك بعد سريان التغييرات يعني قبولك للشروط المحدثة.',
        'يجوز لنا تعليق أو إنهاء وصولك في أي وقت لمخالفة هذه الشروط.',
      ],
    },
    {
      'title': '9. التواصل',
      'body': [
        'يمكن إرسال الأسئلة حول هذه الشروط إلى support@softcar.app أو عبر الدردشة داخل التطبيق.',
      ],
    },
  ],
};

const _arPrivacy = <String, dynamic>{
  'updated': 'آخر تحديث: 10 أغسطس 2026',
  'sections': [
    {
      'title': '1. ما الذي نجمعه',
      'body': [
        'نجمع المعلومات التي تقدمها مباشرة: الاسم ورقم الهاتف والبريد الإلكتروني الاختياري والجنس (لتلوين المقاعد) وكلمة المرور والصور التي ترفعها.',
        'نجمع أيضًا بيانات الحجز (الرحلات والمقاعد والتذاكر) ومعاملات المحفظة ورموز الإشعارات الفورية ومعلومات استخدام التطبيق.',
      ],
    },
    {
      'title': '2. كيف نستخدم بياناتك',
      'body': [
        'لتشغيل خدمة حجز الشاتل وإصدار التذاكر ومعالجة شحن المحفظة وإرسال إشعارات الحجز والرحلة وتقديم دعم العملاء.',
        'يُستخدم الجنس فقط لتلوين مقاعدك المتاحة عند الصعود ولا يُباع أو يُشارك لأغراض تسويقية.',
      ],
    },
    {
      'title': '3. الرسائل النصية وOTP',
      'body': [
        'نرسل رمزًا لمرة واحدة (OTP) عبر الرسائل النصية للتحقق من رقم هاتفك عند التسجيل أو تسجيل الدخول أو إعادة تعيين كلمة المرور.',
        'يوفر مزود رسائل طرف ثالث خدمة الإرسال. نرسل رمز التحقق فقط ولا نشارك رقمك مع المعلنين.',
      ],
    },
    {
      'title': '4. مشاركة بياناتك',
      'body': [
        'نشارك الحد الأدنى الضروري فقط مع: السائقين (اسمك ولون مقعدك للصعود) ومزودي الدفع والرسائل وفريق المالية (لمراجعة شحن المحفظة).',
        'لا نبيع بياناتك الشخصية أبدًا.',
      ],
    },
    {
      'title': '5. الصور والملفات',
      'body': [
        'تُخزَّن صور الملف الشخصي وإثباتات شحن المحفظة بأمان ولا يراها إلا أنت وموظفو سوفت كار المصرح لهم.',
      ],
    },
    {
      'title': '6. الإشعارات',
      'body': [
        'بإذنك نرسل إشعارات فورية عن الحجوزات والرحلات والدعم. يمكنك تعطيلها في أي وقت من الإعدادات.',
      ],
    },
    {
      'title': '7. الأمان',
      'body': [
        'نستخدم التشفير أثناء النقل ورموز جلسات مشفرة وضوابط وصول لحماية بياناتك. لا يوجد نظام آمن 100٪ لكننا نعمل بجد للحفاظ على أمانك.',
      ],
    },
    {
      'title': '8. حقوقك',
      'body': [
        'يمكنك الوصول إلى بيانات حسابك أو تصحيحها أو حذفها في أي وقت. حذف الحساب نهائي ولا يمكن التراجع عنه.',
        'يمكنك أيضًا إلغاء الاشتراك في القنوات التسويقية والإشعارات من الإعدادات.',
      ],
    },
    {
      'title': '9. التواصل',
      'body': [
        'استفسارات الخصوصية: support@softcar.app.',
      ],
    },
  ],
};
