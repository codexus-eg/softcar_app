import 'dart:convert';

/// A single referral reward record shown on the referral screen.
class ReferralReward {
  const ReferralReward({
    required this.id,
    required this.refereeName,
    required this.status,
    this.rewardType,
    this.rewardValue = 0,
    this.rewardLabel,
    this.voucherCode,
    required this.createdAt,
    this.earnedAt,
  });

  final String id;
  final String refereeName;
  final String status;
  final String? rewardType;
  final double rewardValue;
  final String? rewardLabel;
  final String? voucherCode;
  final DateTime createdAt;
  final DateTime? earnedAt;

  bool get earned => status == 'EARNED';

  factory ReferralReward.fromJson(Map<String, dynamic> json) {
    return ReferralReward(
      id: json['id']?.toString() ?? '',
      refereeName: json['refereeName']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      rewardType: json['rewardType']?.toString(),
      rewardValue: (json['rewardValue'] as num?)?.toDouble() ?? 0,
      rewardLabel: json['rewardLabel']?.toString(),
      voucherCode: json['voucherCode']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      earnedAt: json['earnedAt'] == null
          ? null
          : DateTime.tryParse(json['earnedAt'].toString()),
    );
  }
}

/// Everything the referral screen needs, parsed from `GET /api/mobile/referral`.
class ReferralData {
  const ReferralData({
    required this.code,
    required this.shareUrl,
    this.appliedReferrerName,
    required this.enabled,
    required this.rewardType,
    required this.rewardValue,
    required this.refereeRewardEnabled,
    required this.refereeRewardType,
    required this.refereeRewardValue,
    this.termsAr,
    this.termsEn,
    required this.invites,
    required this.pending,
    required this.earned,
    required this.freeTrips,
    required this.discounts,
    required this.totalRewardValue,
    required this.rewards,
  });

  final String code;
  final String shareUrl;
  final String? appliedReferrerName;
  final bool enabled;
  final String rewardType;
  final double rewardValue;
  final bool refereeRewardEnabled;
  final String refereeRewardType;
  final double refereeRewardValue;
  final String? termsAr;
  final String? termsEn;
  final int invites;
  final int pending;
  final int earned;
  final int freeTrips;
  final int discounts;
  final double totalRewardValue;
  final List<ReferralReward> rewards;

  bool get hasCode => code.isNotEmpty;

  String rewardLabelFor(String? languageCode) {
    if (rewardType == 'FREE_TRIP') return '1 رحلة مجانية';
    final suffix = languageCode == 'ar'
        ? (rewardType == 'FIXED_AMOUNT_DISCOUNT'
            ? ' ج.م'
            : '% ')
        : (rewardType == 'FIXED_AMOUNT_DISCOUNT' ? ' EGP' : '% ');
    final unit = suffix;
    return '${rewardValue.toStringAsFixed(rewardValue == rewardValue.roundToDouble() ? 0 : 2)}$unit';
  }

  factory ReferralData.fromJson(Map<String, dynamic> json) {
    final referral = (json['referral'] as Map?) ?? const {};
    final applied = json['applied'] as Map?;
    final settings = (json['settings'] as Map?) ?? const {};
    final stats = (json['stats'] as Map?) ?? const {};
    final rawRewards = (json['rewards'] as List?) ?? const [];

    return ReferralData(
      code: referral['code']?.toString() ?? '',
      shareUrl: referral['shareUrl']?.toString() ?? '',
      appliedReferrerName: applied == null ? null : applied['referrerName']?.toString(),
      enabled: settings['enabled'] == true,
      rewardType: settings['rewardType']?.toString() ?? 'PERCENTAGE_DISCOUNT',
      rewardValue: (settings['rewardValue'] as num?)?.toDouble() ?? 0,
      refereeRewardEnabled: settings['refereeRewardEnabled'] == true,
      refereeRewardType: settings['refereeRewardType']?.toString() ?? 'PERCENTAGE_DISCOUNT',
      refereeRewardValue: (settings['refereeRewardValue'] as num?)?.toDouble() ?? 0,
      termsAr: settings['termsAr']?.toString(),
      termsEn: settings['termsEn']?.toString(),
      invites: (stats['invites'] as num?)?.toInt() ?? 0,
      pending: (stats['pending'] as num?)?.toInt() ?? 0,
      earned: (stats['earned'] as num?)?.toInt() ?? 0,
      freeTrips: (stats['freeTrips'] as num?)?.toInt() ?? 0,
      discounts: (stats['discounts'] as num?)?.toInt() ?? 0,
      totalRewardValue: (stats['totalRewardValue'] as num?)?.toDouble() ?? 0,
      rewards: rawRewards
          .whereType<Map>()
          .map((item) => ReferralReward.fromJson(
              jsonDecode(jsonEncode(item)) as Map<String, dynamic>))
          .toList(),
    );
  }
}