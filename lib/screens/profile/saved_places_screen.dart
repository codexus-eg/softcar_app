import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import 'place_editor_screen.dart';

/// Dedicated saved-places manager opened from the Settings tab. Home and Work
/// are pinned sections (each holds a single place — saving a new one replaces
/// the old), while every other place is listed below as tappable tiles. Each
/// place can be edited on the map picker or deleted here.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  Future<void> _openEditor({
    String placeType = 'OTHER',
    SavedPlace? place,
  }) async {
    final auth = context.read<AuthService>();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlaceEditorScreen(place: place, placeType: placeType),
      ),
    );
    if (changed == true && mounted) {
      await auth.refreshProfile();
    }
  }

  Future<void> _delete(SavedPlace place) async {
    final auth = context.read<AuthService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'removePlaceConfirm')),
        content: Text(place.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'deletePlace')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await auth.deletePlace(place.id);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    if (mounted) await auth.refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'savedPlacesTitle'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 52,
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

    final places = auth.profile.savedPlaces;
    final home = _firstOf(places, 'HOME');
    final work = _firstOf(places, 'WORK');
    final others = places.where((p) => p.placeType == 'OTHER').toList();
    final spotsLeft = 10 - places.length;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'savedPlacesTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            L10n.t(context, 'savedPlacesSub'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(context, 'placesLimit'),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          _PlaceSection(
            title: L10n.t(context, 'homePlace'),
            icon: Icons.home_rounded,
            color: AppColors.accent,
            place: home,
            onAdd: () => _openEditor(placeType: 'HOME'),
            onEdit: (p) => _openEditor(place: p, placeType: p.placeType),
            onDelete: _delete,
          ),
          const SizedBox(height: 12),
          _PlaceSection(
            title: L10n.t(context, 'workPlace'),
            icon: Icons.work_outline_rounded,
            color: AppColors.accent,
            place: work,
            onAdd: () => _openEditor(placeType: 'WORK'),
            onEdit: (p) => _openEditor(place: p, placeType: p.placeType),
            onDelete: _delete,
          ),
          const SizedBox(height: 20),
          Text(
            L10n.t(context, 'placeOther'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          if (others.isEmpty && spotsLeft <= 0)
            _emptyMessage(context)
          else
            _card(
              context,
              Column(
                children: [
                  for (final p in others) ...[
                    _otherTile(context, p),
                    const Divider(height: 1, indent: 56),
                  ],
                  if (spotsLeft > 0)
                    ListTile(
                      onTap: () => _openEditor(placeType: 'OTHER'),
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: AppColors.accent,
                        ),
                      ),
                      title: Text(
                        L10n.t(context, 'addAnotherPlace'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
          if (others.isEmpty && spotsLeft > 0) ...[
            const SizedBox(height: 8),
            _card(
              context,
              ListTile(
                onTap: () => _openEditor(placeType: 'OTHER'),
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                title: Text(
                  L10n.t(context, 'addAnotherPlace'),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  SavedPlace? _firstOf(List<SavedPlace> places, String type) {
    for (final p in places) {
      if (p.placeType == type) return p;
    }
    return null;
  }

  Widget _emptyMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDarkElevated
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        L10n.t(context, 'placesLimit'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDarkElevated
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _otherTile(BuildContext context, SavedPlace place) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.place_outlined, size: 18, color: AppColors.accent),
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
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () => _delete(place),
          ),
          IconButton(
            tooltip: L10n.t(context, 'editSavedPlace'),
            icon: const Icon(Icons.edit_outlined, size: 19),
            onPressed: () =>
                _openEditor(place: place, placeType: place.placeType),
          ),
        ],
      ),
    );
  }
}

/// Home / Work pinned card: filled when a place exists, otherwise a dashed
/// "add" target so the passenger always knows where to attach them.
class _PlaceSection extends StatelessWidget {
  const _PlaceSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.place,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final IconData icon;
  final Color color;
  final SavedPlace? place;
  final VoidCallback onAdd;
  final ValueChanged<SavedPlace> onEdit;
  final ValueChanged<SavedPlace> onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surface;

    if (place == null) {
      return Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (place!.address != null && place!.address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    place!.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: L10n.t(context, 'editSavedPlace'),
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: () => onEdit(place!),
              ),
              IconButton(
                tooltip: L10n.t(context, 'deletePlace'),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 19, color: AppColors.error),
                onPressed: () => onDelete(place!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}