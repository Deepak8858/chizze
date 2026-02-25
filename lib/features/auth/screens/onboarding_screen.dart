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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _restaurantNameController.dispose();
    _restaurantAddressController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final locationService = ref.read(locationServiceProvider);
      final position = await locationService.getCurrentPosition();
      _latitude = position.latitude;
      _longitude = position.longitude;

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
          final addressStr = parts.join(', ');
          _addressController.text = addressStr;
          _city = p.locality ?? p.administrativeArea;
          // Also pre-fill restaurant address if empty
          if (_restaurantAddressController.text.isEmpty) {
            _restaurantAddressController.text = addressStr;
          }
        }
      } catch (_) {}
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isLoadingLocation = false);
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

    setState(() => _isSaving = true);

    try {
      // Request permissions FIRST (before marking onboarding as complete)
      final permSvc = ref.read(permissionServiceProvider);
      if (role == 'delivery_partner') {
        await permSvc.requestDeliveryPermissions();
      } else {
        await permSvc.requestEssentialPermissions();
      }

      if (!mounted) return;

      final authNotifier = ref.read(authProvider.notifier);
      await authNotifier.completeOnboarding(
        name: name,
        email: _emailController.text.trim(),
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

      // GoRouter's refreshListenable will auto-redirect to the correct dashboard
      // when isNewUser changes to false (set by completeOnboarding).
    } catch (e) {
      if (mounted) _showError('Failed to save: $e');
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

  Widget _buildLocationCard() {
    return GlassCard(
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
                      Icon(Icons.my_location_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Detect',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.primary)),
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
