import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../profile/providers/address_provider.dart';
import '../../profile/providers/user_profile_provider.dart';

/// Onboarding screen — shown to new users after OTP verification.
/// Displays role-specific forms for customer, restaurant owner, or delivery partner.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // Common fields
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // Restaurant-specific
  final _restaurantNameController = TextEditingController();
  final _restaurantAddressController = TextEditingController();
  String _selectedCuisine = '';

  // Delivery-specific
  String _selectedVehicle = 'bike';
  final _vehicleNumberController = TextEditingController();

  bool _isLoadingLocation = false;
  bool _isSaving = false;
  double? _latitude;
  double? _longitude;
  String? _city;
  String? _locationError;

  static const _cuisineTypes = [
    'Indian',
    'Chinese',
    'Italian',
    'Mexican',
    'Thai',
    'Japanese',
    'Continental',
    'Fast Food',
    'Desserts',
    'Beverages',
    'Multi-Cuisine',
  ];

  static const _vehicleTypes = [
    'bike',
    'bicycle',
    'scooter',
    'car',
  ];

  @override
  void initState() {
    super.initState();
    _autoDetectLocation();
    // Pre-populate phone from the Appwrite account if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final phone = ref.read(authProvider).user?.phone ?? '';
      if (phone.isNotEmpty && _phoneController.text.isEmpty) {
        _phoneController.text = phone;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _restaurantNameController.dispose();
    _restaurantAddressController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectLocation() async {
    final locationService = ref.read(locationServiceProvider);

    // Instant path: if warm-up (from login screen) already captured a position,
    // show it immediately with zero perceived latency.
    final cached = locationService.lastPosition;
    if (cached != null && _latitude == null) {
      _applyPosition(cached.latitude, cached.longitude);
    }

    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    final position = await locationService.getFastCurrentPosition();
    if (!mounted) return;

    if (position == null) {
      // Real failure — tell the user exactly why and how to fix it.
      final status = await locationService.permissionStatus();
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _locationError = switch (status) {
          LocationPermissionStatus.serviceDisabled =>
            'Location services are off. Turn on Location in your phone settings, then tap "Detect" again.',
          LocationPermissionStatus.permanentlyDenied =>
            'Location permission was permanently denied. Open Settings → Apps → Chizze → Permissions and allow Location, then tap "Detect" again.',
          LocationPermissionStatus.denied =>
            'We need location access to set up your account. Please tap "Detect" again and allow location.',
          LocationPermissionStatus.granted =>
            'Could not get your GPS fix. Please step near a window or outdoors and tap "Detect" again.',
        };
      });
      return;
    }

    _applyPosition(position.latitude, position.longitude);
    setState(() => _isLoadingLocation = false);

    // Reverse-geocode async — coords are already saved; if this fails, user
    // can type the address. Never blocks onboarding.
    unawaited(_fillAddressFromCoords(position.latitude, position.longitude));
  }

  void _applyPosition(double lat, double lng) {
    if (!mounted) return;
    setState(() {
      _latitude = lat;
      _longitude = lng;
      _locationError = null;
    });
  }

  Future<void> _fillAddressFromCoords(double lat, double lng) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng);
      if (!mounted || placemarks.isEmpty) return;
      final p = placemarks.first;
      final parts = <String>[
        if (p.subLocality?.isNotEmpty == true) p.subLocality!,
        if (p.locality?.isNotEmpty == true) p.locality!,
        if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
        if (p.postalCode?.isNotEmpty == true) p.postalCode!,
      ];
      final addressStr = parts.join(', ');
      if (addressStr.isEmpty) return;
      setState(() {
        if (_addressController.text.isEmpty) {
          _addressController.text = addressStr;
        }
        _city = p.locality ?? p.administrativeArea;
        if (_restaurantAddressController.text.isEmpty) {
          _restaurantAddressController.text = addressStr;
        }
      });
    } catch (_) {
      // Geocoding is best-effort; the user can type the address.
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final role = ref.read(authProvider).userRole;

    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }

    if (role == 'restaurant_owner') {
      if (_restaurantNameController.text.trim().isEmpty) {
        _showError('Please enter your restaurant name');
        return;
      }
      if (_selectedCuisine.isEmpty) {
        _showError('Please select a cuisine type');
        return;
      }
    }

    if (role == 'delivery_partner') {
      if (_vehicleNumberController.text.trim().isEmpty) {
        _showError('Please enter your vehicle number');
        return;
      }
    }

    // Customers must provide phone number and current location
    if (role == 'customer') {
      if (_phoneController.text.trim().isEmpty) {
        _showError('Please enter your phone number');
        return;
      }
      if (_latitude == null || _longitude == null) {
        _showError(
          'Your current location is required to continue. '
          'Please tap "Detect My Location" and allow location access.',
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Location permission was resolved during _autoDetectLocation; request
      // notification permission here (non-blocking if denied).
      final permSvc = ref.read(permissionServiceProvider);
      unawaited(permSvc.ensureNotificationPermission());

      if (!mounted) return;

      final authNotifier = ref.read(authProvider.notifier);
      await authNotifier.completeOnboarding(
        name: name,
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        city: _city,
        latitude: _latitude,
        longitude: _longitude,
        // Restaurant-specific
        restaurantName: _restaurantNameController.text.trim(),
        restaurantAddress: _restaurantAddressController.text.trim(),
        cuisineType: _selectedCuisine,
        // Delivery-specific
        vehicleType: _selectedVehicle,
        vehicleNumber: _vehicleNumberController.text.trim(),
      );

      // Force profile and addresses re-fetch so the just-saved data appears
      ref.invalidate(userProfileProvider);
      ref.invalidate(addressProvider);

      // GoRouter's refreshListenable will auto-redirect to the correct dashboard
      // when isNewUser changes to false (set by completeOnboarding).
    } catch (e) {
      if (mounted) {
        // Strip the "Exception: " prefix that Dart adds when rethrowing.
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        if (msg.isEmpty) msg = 'Failed to save profile. Please try again.';
        _showError(msg);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.userRole;
    final roleLabel = switch (role) {
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

              // ─── Common: Name ───
              _buildNameCard(),

              const SizedBox(height: AppSpacing.base),

              // ─── Common: Email (optional) ───
              _buildEmailCard(),

              const SizedBox(height: AppSpacing.base),

              // ─── Role-specific fields ───
              if (role == 'restaurant_owner') ...[
                _buildRestaurantNameCard(),
                const SizedBox(height: AppSpacing.base),
                _buildCuisineCard(),
                const SizedBox(height: AppSpacing.base),
                _buildRestaurantAddressCard(),
              ] else if (role == 'delivery_partner') ...[
                _buildVehicleTypeCard(),
                const SizedBox(height: AppSpacing.base),
                _buildVehicleNumberCard(),
              ] else ...[
                _buildPhoneCard(),
                const SizedBox(height: AppSpacing.base),
                _buildLocationCard(),
              ],

              const SizedBox(height: AppSpacing.xxl),

              // ─── Continue Button ───
              ChizzeButton(
                label: 'Continue',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _saveProfile,
              ).animate(delay: 500.ms).fadeIn(),

              const SizedBox(height: AppSpacing.base),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Common Widgets ───

  Widget _buildNameCard() {
    return GlassCard(
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
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildEmailCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email (optional)', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _emailController,
            style: AppTypography.body1,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'your@email.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
    ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildPhoneCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Phone Number', style: AppTypography.caption),
              Text(
                ' *',
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _phoneController,
            style: AppTypography.body1,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+91 9876543210',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
        ],
      ),
    ).animate(delay: 275.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildLocationCard() {
    final hasLocation = _latitude != null && _longitude != null;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your Location', style: AppTypography.caption),
              Text(
                ' *',
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
              const Spacer(),
              if (hasLocation)
                Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.success),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Show error banner if detection failed
          if (_locationError != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationError!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Detect button — prominent when no location, subtle when detected
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoadingLocation ? null : _autoDetectLocation,
              icon: _isLoadingLocation
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      hasLocation
                          ? Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      size: 18,
                    ),
              label: Text(
                _isLoadingLocation
                    ? 'Detecting…'
                    : hasLocation
                        ? 'Location detected — tap to refresh'
                        : 'Detect My Location (Required)',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    hasLocation ? AppColors.success : AppColors.primary,
                side: BorderSide(
                  color: hasLocation
                      ? AppColors.success
                      : _locationError != null
                          ? AppColors.error
                          : AppColors.primary,
                ),
              ),
            ),
          ),

          if (hasLocation) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _addressController,
              style: AppTypography.body1,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Your address (auto-filled from GPS)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
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
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1);
  }

  // ─── Restaurant-specific Widgets ───

  Widget _buildRestaurantNameCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restaurant Name', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _restaurantNameController,
            style: AppTypography.body1,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Enter restaurant name',
              prefixIcon: Icon(Icons.store_rounded),
            ),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildCuisineCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuisine Type', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cuisineTypes.map((cuisine) {
              final selected = _selectedCuisine == cuisine;
              return ChoiceChip(
                label: Text(cuisine),
                selected: selected,
                selectedColor: AppColors.primary.withAlpha(50),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  setState(() => _selectedCuisine = cuisine);
                },
              );
            }).toList(),
          ),
        ],
      ),
    ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildRestaurantAddressCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Restaurant Address', style: AppTypography.caption),
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
                      Icon(Icons.my_location_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Use my location',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _restaurantAddressController,
            style: AppTypography.body1,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Restaurant address...',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          if (_latitude != null && _longitude != null) ...[
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
    ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1);
  }

  // ─── Delivery-specific Widgets ───

  Widget _buildVehicleTypeCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vehicle Type', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _vehicleTypes.map((vehicle) {
              final selected = _selectedVehicle == vehicle;
              final icon = switch (vehicle) {
                'bike' => Icons.two_wheeler_rounded,
                'bicycle' => Icons.pedal_bike_rounded,
                'scooter' => Icons.electric_scooter_rounded,
                'car' => Icons.directions_car_rounded,
                _ => Icons.local_shipping_rounded,
              };
              return ChoiceChip(
                avatar: Icon(icon,
                    size: 18,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary),
                label: Text(vehicle[0].toUpperCase() + vehicle.substring(1)),
                selected: selected,
                selectedColor: AppColors.primary.withAlpha(50),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  setState(() => _selectedVehicle = vehicle);
                },
              );
            }).toList(),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildVehicleNumberCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vehicle Number', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _vehicleNumberController,
            style: AppTypography.body1,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g., KA01AB1234',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
        ],
      ),
    ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.1);
  }
}
