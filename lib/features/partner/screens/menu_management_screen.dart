import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../restaurant/models/menu_item.dart';
import '../providers/menu_management_provider.dart';

/// Menu management screen — categories, items, CRUD
class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuState = ref.watch(menuManagementProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menu Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddCategoryDialog(context, ref),
            tooltip: 'Add Category',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemSheet(context, ref, menuState.categories),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Item'),
      ),
      body: menuState.categories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🍽️', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: AppSpacing.xl),
                  Text('No menu yet', style: AppTypography.h3),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Add categories and items to build your menu',
                    style: AppTypography.body2,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ChizzeButton(
                    label: 'Add First Category',
                    icon: Icons.add_rounded,
                    onPressed: () => _showAddCategoryDialog(context, ref),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                80,
              ),
              itemCount: menuState.categories.length,
              itemBuilder: (context, catIndex) {
                final category = menuState.categories[catIndex];
                final items = menuState.itemsForCategory(category.id);

                return _buildCategorySection(
                  context,
                  ref,
                  category,
                  items,
                  catIndex,
                  menuState,
                );
              },
            ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    WidgetRef ref,
    MenuCategory category,
    List<MenuItem> items,
    int index,
    MenuManagementState menuState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          GlassCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: AppTypography.h3.copyWith(fontSize: 16),
                      ),
                      Text(
                        '${items.length} items',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                // Active toggle
                Switch(
                  value: category.isActive,
                  onChanged: (_) => ref
                      .read(menuManagementProvider.notifier)
                      .toggleCategoryActive(category.id),
                  activeThumbColor: AppColors.primary,
                ),
                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () =>
                      _showEditCategoryDialog(context, ref, category),
                  color: AppColors.textSecondary,
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () {
                    ref
                        .read(menuManagementProvider.notifier)
                        .deleteCategory(category.id);
                  },
                  color: AppColors.error,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Items
          if (!category.isActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                'Category hidden from customers',
                style: AppTypography.caption.copyWith(color: AppColors.warning),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...items.asMap().entries.map((entry) {
              return _buildItemCard(
                context,
                ref,
                entry.value,
                entry.key,
                menuState,
              );
            }),
        ],
      ),
    ).animate(delay: (index * 100).ms).fadeIn();
  }

  Widget _buildItemCard(
    BuildContext context,
    WidgetRef ref,
    MenuItem item,
    int index,
    MenuManagementState menuState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: item.isAvailable
              ? AppColors.surfaceElevated
              : AppColors.surfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // Item image thumbnail
            if (item.imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.surfaceElevated,
                      child: const Icon(Icons.image, size: 20, color: AppColors.textTertiary),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.surfaceElevated,
                      child: const Icon(Icons.broken_image, size: 20, color: AppColors.textTertiary),
                    ),
                  ),
                ),
              ),
            // Veg indicator
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(
                  color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Name + price
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTypography.body2.copyWith(
                            fontWeight: FontWeight.w500,
                            color: item.isAvailable
                                ? Colors.white
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (item.isBestseller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '★',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.primary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    '₹${item.price.toInt()}',
                    style: AppTypography.caption.copyWith(
                      color: item.isAvailable
                          ? AppColors.primary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Availability toggle
            Switch(
              value: item.isAvailable,
              onChanged: (_) => ref
                  .read(menuManagementProvider.notifier)
                  .toggleItemAvailability(item.id),
              activeThumbColor: AppColors.success,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),

            // Edit
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16),
              onPressed: () =>
                  _showEditItemSheet(context, ref, item, menuState.categories),
              color: AppColors.textTertiary,
              visualDensity: VisualDensity.compact,
            ),

            // Delete
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              onPressed: () =>
                  ref.read(menuManagementProvider.notifier).deleteItem(item.id),
              color: AppColors.error,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dialogs & Sheets ───

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.body2.copyWith(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(menuManagementProvider.notifier)
                    .addCategory(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(
    BuildContext context,
    WidgetRef ref,
    MenuCategory category,
  ) {
    final controller = TextEditingController(text: category.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Edit Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.body2.copyWith(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(menuManagementProvider.notifier)
                    .updateCategory(category.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddItemSheet(
    BuildContext context,
    WidgetRef ref,
    List<MenuCategory> categories,
  ) {
    _showItemSheet(context, ref, categories, null);
  }

  void _showEditItemSheet(
    BuildContext context,
    WidgetRef ref,
    MenuItem item,
    List<MenuCategory> categories,
  ) {
    _showItemSheet(context, ref, categories, item);
  }

  void _showItemSheet(
    BuildContext context,
    WidgetRef ref,
    List<MenuCategory> categories,
    MenuItem? existingItem,
  ) {
    final nameController = TextEditingController(
      text: existingItem?.name ?? '',
    );
    final priceController = TextEditingController(
      text: existingItem != null ? '${existingItem.price.toInt()}' : '',
    );
    final descController = TextEditingController(
      text: existingItem?.description ?? '',
    );
    bool isVeg = existingItem?.isVeg ?? false;
    String selectedCategoryId = existingItem?.categoryId ?? categories.first.id;
    File? selectedImageFile;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existingItem != null ? 'Edit Item' : 'Add New Item',
                style: AppTypography.h3,
              ),
              const SizedBox(height: AppSpacing.xl),

              // ─── Image Picker ───
              GestureDetector(
                onTap: () async {
                  final file = await ImageUploadService.pickImage();
                  if (file != null) {
                    setSheetState(() => selectedImageFile = file);
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: AppColors.divider,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: selectedImageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          child: Image.file(
                            selectedImageFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : (existingItem != null &&
                              existingItem.imageUrl.isNotEmpty)
                          ? ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              child: CachedNetworkImage(
                                imageUrl: existingItem.imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_rounded,
                                  size: 36,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Tap to add photo',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              TextField(
                controller: nameController,
                style: AppTypography.body2.copyWith(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Item Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: priceController,
                style: AppTypography.body2.copyWith(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (₹)',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: descController,
                style: AppTypography.body2.copyWith(color: Colors.white),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                  initialValue: selectedCategoryId,
                dropdownColor: AppColors.surfaceElevated,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          c.name,
                          style: AppTypography.body2.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setSheetState(() => selectedCategoryId = val);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text('Veg', style: AppTypography.body2),
                  const SizedBox(width: AppSpacing.sm),
                  Switch(
                    value: isVeg,
                    onChanged: (val) => setSheetState(() => isVeg = val),
                    activeThumbColor: AppColors.veg,
                  ),
                  const Spacer(),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isVeg ? AppColors.veg : AppColors.nonVeg,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isVeg ? AppColors.veg : AppColors.nonVeg,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVeg ? 'Vegetarian' : 'Non-Vegetarian',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              ChizzeButton(
                label: isUploading
                    ? 'Uploading...'
                    : (existingItem != null ? 'Save Changes' : 'Add Item'),
                icon: existingItem != null
                    ? Icons.save_rounded
                    : Icons.add_rounded,
                onPressed: isUploading
                    ? null
                    : () {
                        final name = nameController.text.trim();
                        final price =
                            double.tryParse(priceController.text.trim()) ?? 0;
                        if (name.isEmpty || price <= 0) return;

                        setSheetState(() => isUploading = true);

                        if (existingItem != null) {
                          ref
                              .read(menuManagementProvider.notifier)
                              .updateItem(
                                existingItem.id,
                                name: name,
                                price: price,
                                description: descController.text.trim(),
                                isVeg: isVeg,
                                categoryId: selectedCategoryId,
                                imageFile: selectedImageFile,
                              )
                              .then((_) {
                                if (context.mounted) Navigator.pop(context);
                              });
                        } else {
                          ref
                              .read(menuManagementProvider.notifier)
                              .addItem(
                                name: name,
                                categoryId: selectedCategoryId,
                                price: price,
                                description: descController.text.trim(),
                                isVeg: isVeg,
                                imageFile: selectedImageFile,
                              )
                              .then((_) {
                                if (context.mounted) Navigator.pop(context);
                              });
                        }
                      },
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
