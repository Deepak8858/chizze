import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../shared/widgets/glass_card.dart';

/// Onboarding screen — shown to new users after OTP verification.
/// Captures name and current location / address.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoadingLocation = false;
  bool _isSaving = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _autoDetectLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final locationService = ref.read(locationServiceProvider);
      final position = await locationService.getCurrentPosition();
      _latitude = position.latitude;
      _longitude = position.longitude;

      // Reverse geocode to get address string
      try {
        final placemarks = await geo.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if (p.subLocality?.isNotEmpty == true) p.subLocality!,
            if (p.locality?.isNotEmpty == true) p.locality!,
            if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
            if (p.postalCode?.isNotEmpty == true) p.postalCode!,
          ];
          _addressController.text = parts.join(', ');
        }
      } catch (_) {
        // Geocoding failed — user can type manually
      }
    } catch (_) {
      // Location unavailable — user types manually
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authNotifier = ref.read(authProvider.notifier);
      await authNotifier.completeOnboarding(
        name: name,
        address: _addressController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
      );

      if (!mounted) return;

      // Navigate to the role-appropriate home
      final role = ref.read(authProvider).userRole;
      switch (role) {
        case 'restaurant_owner':
          context.go('/partner/dashboard');
        case 'delivery_partner':
          context.go('/delivery/dashboard');
        default:
          context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final roleLabel = switch (authState.userRole) {
      'restaurant_owner' => 'Restaurant Partner',
      'delivery_partner' => 'Delivery Partner',
      _ => 'Foodie',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.massive),

              // ─── Header ───
              Text(
                'Almost there!',
                style: AppTypography.h1.copyWith(fontSize: 28),
              ).animate().fadeIn().slideX(begin: -0.1),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'Set up your $roleLabel profile',
                style: AppTypography.body2,
              ).animate(delay: 100.ms).fadeIn(),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Name ───
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Name', style: AppTypography.caption),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _nameController,
                      style: AppTypography.body1,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Enter your full name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

              const SizedBox(height: AppSpacing.base),

              // ─── Location / Address ───
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Your Location', style: AppTypography.caption),
                        const Spacer(),
                        if (_isLoadingLocation)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: _autoDetectLocation,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.my_location_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Detect',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _addressController,
                      style: AppTypography.body1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Your address will appear here...',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),

                    if (_latitude != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Continue Button ───
              ChizzeButton(
                label: 'Continue',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _saveProfile,
              ).animate(delay: 400.ms).fadeIn(),

              const SizedBox(height: AppSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}
