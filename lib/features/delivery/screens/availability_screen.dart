import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/delivery_provider.dart';

/// Availability / working‑hours preference screen.
///
/// Backend only supports a binary `is_online` toggle, so this is a
/// client‑side preference UI with schedule presets. The actual availability
/// will still be controlled by the online/offline toggle on the dashboard.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  // Day‑of‑week toggles (Mon=0 … Sun=6)
  final List<bool> _activeDays = List.filled(7, true);

  // Working‑hours range
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);

  // Quick preset
  String _selectedPreset = 'full_time';

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _kActiveDays = 'avail_active_days';
  static const _kStartHour = 'avail_start_hour';
  static const _kStartMinute = 'avail_start_minute';
  static const _kEndHour = 'avail_end_hour';
  static const _kEndMinute = 'avail_end_minute';
  static const _kPreset = 'avail_preset';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getStringList(_kActiveDays);
    if (days != null && days.length == 7) {
      for (int i = 0; i < 7; i++) {
        _activeDays[i] = days[i] == '1';
      }
    }
    final sh = prefs.getInt(_kStartHour);
    final sm = prefs.getInt(_kStartMinute);
    final eh = prefs.getInt(_kEndHour);
    final em = prefs.getInt(_kEndMinute);
    if (sh != null && sm != null) {
      _startTime = TimeOfDay(hour: sh, minute: sm);
    }
    if (eh != null && em != null) {
      _endTime = TimeOfDay(hour: eh, minute: em);
    }
    _selectedPreset = prefs.getString(_kPreset) ?? 'full_time';
    if (mounted) setState(() {});
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kActiveDays,
      _activeDays.map((b) => b ? '1' : '0').toList(),
    );
    await prefs.setInt(_kStartHour, _startTime.hour);
    await prefs.setInt(_kStartMinute, _startTime.minute);
    await prefs.setInt(_kEndHour, _endTime.hour);
    await prefs.setInt(_kEndMinute, _endTime.minute);
    await prefs.setString(_kPreset, _selectedPreset);
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(deliveryProvider).partner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Availability')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Current Status ───
            GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: partner.isOnline
                          ? AppColors.success
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.isOnline ? 'You\'re Online' : 'You\'re Offline',
                          style: AppTypography.h3.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          partner.isOnline
                              ? 'Toggle your status from the dashboard'
                              : 'Go online from the dashboard to receive orders',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Schedule Presets ───
            Text(
              'Schedule Preset',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _PresetChip(
                  label: 'Full Time',
                  selected: _selectedPreset == 'full_time',
                  onTap: () => _applyPreset('full_time'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _PresetChip(
                  label: 'Part Time',
                  selected: _selectedPreset == 'part_time',
                  onTap: () => _applyPreset('part_time'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _PresetChip(
                  label: 'Weekends',
                  selected: _selectedPreset == 'weekends',
                  onTap: () => _applyPreset('weekends'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _PresetChip(
                  label: 'Custom',
                  selected: _selectedPreset == 'custom',
                  onTap: () => _applyPreset('custom'),
                ),
              ],
            ).animate(delay: 200.ms).fadeIn(),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Working Days ───
            Text(
              'Working Days',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                return GestureDetector(
                  onTap: () => setState(() {
                    _activeDays[i] = !_activeDays[i];
                    _selectedPreset = 'custom';
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _activeDays[i]
                          ? AppColors.primary
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _activeDays[i]
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dayLabels[i],
                      style: AppTypography.overline.copyWith(
                        color: _activeDays[i]
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              }),
            ).animate(delay: 300.ms).fadeIn(),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Working Hours ───
            Text(
              'Working Hours',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _TimePickerTile(
                    label: 'Start',
                    time: _startTime,
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (t != null) setState(() => _startTime = t);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _TimePickerTile(
                    label: 'End',
                    time: _endTime,
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (t != null) setState(() => _endTime = t);
                    },
                  ),
                ),
              ],
            ).animate(delay: 400.ms).fadeIn(),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Save Button ───
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                onPressed: () async {
                  await _savePreferences();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Schedule preferences saved'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Save Preferences',
                  style: AppTypography.button.copyWith(color: Colors.white),
                ),
              ),
            ).animate(delay: 500.ms).fadeIn(),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Note ───
            GlassCard(
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: AppColors.info),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Schedule preferences are saved locally. '
                      'Use the online/offline toggle on the dashboard '
                      'to control your availability in real-time.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate(delay: 600.ms).fadeIn(),
          ],
        ),
      ),
    );
  }

  void _applyPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'full_time':
          for (int i = 0; i < 7; i++) _activeDays[i] = true;
          _startTime = const TimeOfDay(hour: 9, minute: 0);
          _endTime = const TimeOfDay(hour: 22, minute: 0);
        case 'part_time':
          for (int i = 0; i < 7; i++) _activeDays[i] = true;
          _startTime = const TimeOfDay(hour: 11, minute: 0);
          _endTime = const TimeOfDay(hour: 15, minute: 0);
        case 'weekends':
          for (int i = 0; i < 5; i++) _activeDays[i] = false;
          _activeDays[5] = true; // Sat
          _activeDays[6] = true; // Sun
          _startTime = const TimeOfDay(hour: 10, minute: 0);
          _endTime = const TimeOfDay(hour: 22, minute: 0);
        case 'custom':
          break; // no-op
      }
    });
  }
}

// ─── Helper widgets ─────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.overline.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.overline.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time.format(context),
              style: AppTypography.h3.copyWith(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
