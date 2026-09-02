import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/shuttle.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/passenger_location_service.dart';

/// Full, editable passenger profile: photo, personal info (name, email,
/// phone, gender, date of birth, emergency contact), referral code and
/// saved Home / Work places. Every field persists against the live backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _emergency = TextEditingController();
  UserGender? _gender;
  DateTime? _dob;
  bool _saving = false;
  bool _loaded = false;

  final _referralController = TextEditingController();
  bool _applyingReferral = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _emergency.dispose();
    _referralController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    if (!_loaded && auth.isLoggedIn) {
      _loaded = true;
      _seed(auth.profile);
      Future.microtask(auth.refreshProfile).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _seed(UserProfile profile) {
    _name.text = profile.name;
    _phone.text = profile.phone ?? '';
    _email.text = profile.email ?? '';
    _emergency.text = profile.emergencyPhone ?? '';
    _gender = profile.gender;
    _dob = profile.dateOfBirth;
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final name = _name.text.trim();
    final emergency = _emergency.text.trim();
    final email = _email.text.trim();
    final emailOk =
        email.isEmpty ||
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        RegExp(r'^01[0125][0-9]{8}$').hasMatch(email);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'nameRequired'))),
      );
      return;
    }
    if (!emailOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'emailInvalid'))),
      );
      return;
    }
    setState(() => _saving = true);
    final err = await auth.updateProfile(
      name: name,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: email.isEmpty ? null : email,
      gender: _gender,
      dateOfBirth: _dob,
      emergencyPhone: emergency.isEmpty ? null : emergency,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? L10n.t(context, 'saved')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: L10n.t(context, 'dateOfBirth'),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _applyReferral() async {
    final auth = context.read<AuthService>();
    final code = _referralController.text.trim();
    if (code.isEmpty) return;
    setState(() => _applyingReferral = true);
    final err = await auth.applyReferral(code);
    if (!mounted) return;
    setState(() => _applyingReferral = false);
    if (err == null) {
      _referralController.clear();
      await auth.refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'referralApplied')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final profile = auth.isLoggedIn ? auth.profile : const UserProfile();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'profile'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 56,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.t(context, 'signInForProfile'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/auth'),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(L10n.t(context, 'login')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surface;
    final genderColor =
        GenderColor.forGender(profile.gender, fallback: AppColors.accent);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _AvatarHeader(profile: profile),
          const SizedBox(height: 20),

          _SectionTitle(L10n.t(context, 'personalInfo')),
          _card(
            surface,
            Column(
              children: [
                _field(
                  controller: _name,
                  icon: Icons.badge_outlined,
                  label: L10n.t(context, 'fullName'),
                  textInputAction: TextInputAction.next,
                ),
                _divider(),
                _field(
                  controller: _phone,
                  icon: Icons.phone_outlined,
                  label: L10n.t(context, 'phoneNumberHint'),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                _divider(),
                _field(
                  controller: _email,
                  icon: Icons.mail_outline_rounded,
                  label: L10n.t(context, 'emailAddress'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                _divider(),
                _field(
                  controller: _emergency,
                  icon: Icons.healing_outlined,
                  label: L10n.t(context, 'emergencyContact'),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                ),
                _divider(),
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded, size: 20),
                  title: Text(
                    L10n.t(context, 'gender'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: SegmentedButton<UserGender>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.accent,
                      selectedForegroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: UserGender.male,
                        label: Text(L10n.t(context, 'male')),
                        icon: const Icon(Icons.male_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: UserGender.female,
                        label: Text(L10n.t(context, 'female')),
                        icon: const Icon(Icons.female_rounded, size: 15),
                      ),
                    ],
                    selected: _gender == null
                        ? const <UserGender>{}
                        : {_gender!},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (s) =>
                        setState(() => _gender = s.isEmpty ? null : s.first),
                  ),
                ),
                _divider(),
                ListTile(
                  leading: const Icon(Icons.cake_outlined, size: 20),
                  title: Text(
                    L10n.t(context, 'dateOfBirth'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: TextButton.icon(
                    onPressed: _pickDob,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: Text(
                      _dob == null
                          ? L10n.t(context, 'notSet')
                          : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving ? L10n.t(context, 'saving') : L10n.t(context, 'save'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 24),

          _SectionTitle(L10n.t(context, 'savedPlacesTitle')),
          Text(
            L10n.t(context, 'savedPlacesSub'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _card(surface, _SavedPlacesList(places: profile.savedPlaces)),
          const SizedBox(height: 24),

          _SectionTitle(L10n.t(context, 'referralCode')),
          _card(
            surface,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        L10n.t(context, 'referralYourCode'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () async {
                          final code = profile.referralCode;
                          if (code == null || code.isEmpty) return;
                          await Clipboard.setData(ClipboardData(text: code));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(L10n.t(context, 'copied')),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: [
                            const Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.t(
                                context,
                                profile.referralCode == null ||
                                        profile.referralCode!.isEmpty
                                    ? 'referralEmpty'
                                    : 'copy',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    profile.referralCode == null ||
                            profile.referralCode!.isEmpty
                        ? '—'
                        : profile.referralCode!,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: genderColor,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _referralController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: L10n.t(context, 'referralCode'),
                            prefixIcon: const Icon(Icons.card_giftcard_rounded,
                                size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _applyingReferral
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : FilledButton(
                              onPressed: _applyReferral,
                              child: Text(L10n.t(context, 'referralApply')),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Color surface, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 52);

  Widget _field({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          icon: Icon(icon, size: 20),
          labelText: label,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final imageUrl = profile.image;

    return Row(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: 0.14),
            image: imageUrl != null && imageUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(
                        'https://softcarshuttle.com$imageUrl'),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: imageUrl == null || imageUrl.isEmpty
              ? Icon(Icons.person_rounded, size: 44, color: AppColors.accent)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.name.isEmpty ? '—' : profile.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                profile.phone ?? profile.email ?? 'SoftCar-Fleet',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (profile.gender != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        profile.gender == UserGender.female
                            ? L10n.t(context, 'female')
                            : L10n.t(context, 'male'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedPlacesList extends StatelessWidget {
  const _SavedPlacesList({required this.places});

  final List<SavedPlace> places;

  @override
  Widget build(BuildContext context) {
    final home = places.where((p) => p.isHome).firstOrNull;
    final work = places.where((p) => p.isWork).firstOrNull;
    final others = places.where((p) => !p.isHome && !p.isWork).toList();

    return Column(
      children: [
        _placeTile(
          context,
          place: home,
          icon: Icons.home_rounded,
          emptyLabel: L10n.t(context, 'addHome'),
          emptyType: 'HOME',
        ),
        Divider(height: 1, indent: 52),
        _placeTile(
          context,
          place: work,
          icon: Icons.work_outline_rounded,
          emptyLabel: L10n.t(context, 'addWork'),
          emptyType: 'WORK',
        ),
        for (final p in others) ...[
          Divider(height: 1, indent: 52),
          _placeTile(context, place: p, icon: Icons.star_outline_rounded),
        ],
        if (others.isEmpty) ...[
          Divider(height: 1, indent: 52),
          ListTile(
            onTap: () => _editPlace(context, placeType: 'OTHER'),
            leading: const Icon(Icons.add_rounded, size: 20),
            title: Text(
              L10n.t(context, 'addPlace'),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }

  Widget _placeTile(
    BuildContext context, {
    required SavedPlace? place,
    required IconData icon,
    String? emptyLabel,
    String? emptyType,
  }) {
    if (place == null) {
      return ListTile(
        onTap: () => _editPlace(context, placeType: emptyType ?? 'OTHER'),
        leading: Icon(icon, size: 20, color: AppColors.textTertiary),
        title: Text(
          emptyLabel ?? L10n.t(context, 'addPlace'),
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: AppColors.accent),
      ),
      title: Text(
        place.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: place.address == null || place.address!.isEmpty
          ? null
          : Text(
              place.address!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: L10n.t(context, 'deletePlace'),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              final ctx = context;
              final ok = await showDialog<bool>(
                context: ctx,
                builder: (ctx) => AlertDialog(
                  title: Text(L10n.t(ctx, 'removePlaceConfirm')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(L10n.t(ctx, 'cancel')),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(L10n.t(ctx, 'deletePlace')),
                    ),
                  ],
                ),
              );
              if (ok != true || !ctx.mounted) return;
              await ctx.read<AuthService>().deletePlace(place.id);
            },
          ),
          IconButton(
            tooltip: L10n.t(context, 'editSavedPlace'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                _editPlace(context, placeType: place.placeType, place: place),
          ),
        ],
      ),
    );
  }

  void _editPlace(
    BuildContext context, {
    required String placeType,
    SavedPlace? place,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _PlaceScreen(place: place, placeType: placeType),
          ),
        )
        .then((_) {
          final ctx = context;
          if (ctx.mounted && ctx.read<AuthService>().isLoggedIn) {
            // Refresh the profile so the saved-places list reflects any
            // changes made on the add/edit screen.
            ctx.read<AuthService>().refreshProfile();
          }
        });
  }
}

class _PlaceScreen extends StatefulWidget {
  const _PlaceScreen({required this.place, required this.placeType});

  final SavedPlace? place;
  final String placeType;

  @override
  State<_PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<_PlaceScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  LatLng? _coords;
  bool _locating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.place?.name ?? '');
    _address = TextEditingController(text: widget.place?.address ?? '');
    if (widget.place != null) {
      _coords = LatLng(widget.place!.lat, widget.place!.lng);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    if (!await PassengerLocationService.instance.ensurePermission()) {
      if (mounted) setState(() => _locating = false);
      return;
    }
    try {
      final fix = await PassengerLocationService.instance.getSingleFix();
      if (mounted && fix != null) {
        setState(() {
          _coords = fix;
          _locating = false;
        });
      } else if (mounted) {
        setState(() => _locating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'savedPlaceRequired'))),
      );
      return;
    }
    setState(() => _saving = true);
    String? err;
    if (widget.place != null) {
      err = await auth.updatePlace(widget.place!.id, {
        'name': name,
        'address': _address.text.trim(),
        if (_coords != null)
          'lat': _coords!.latitude,
        if (_coords != null)
          'lng': _coords!.longitude,
      });
    } else {
      err = await auth.savePlace(
        label: name,
        name: name,
        address: _address.text.trim(),
        lat: _coords?.latitude ?? 0,
        lng: _coords?.longitude ?? 0,
        placeType: widget.placeType,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.place != null
        ? L10n.t(context, 'editSavedPlace')
        : widget.placeType == 'HOME'
        ? L10n.t(context, 'homePlace')
        : widget.placeType == 'WORK'
        ? L10n.t(context, 'workPlace')
        : L10n.t(context, 'addPlace');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            autofocus: widget.place == null,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: L10n.t(context, 'savedPlaceName'),
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: L10n.t(context, 'savedPlaceAddress'),
              hintText: L10n.t(context, 'savedPlaceHint'),
              prefixIcon: const Icon(Icons.alt_route_rounded),
            ),
          ),
          const SizedBox(height: 12),
          if (_coords != null)
            Text(
              '${_coords!.latitude.toStringAsFixed(5)}, ${_coords!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(L10n.t(context, 'savedPlaceUseCurrent')),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving ? L10n.t(context, 'saving') : L10n.t(context, 'save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}