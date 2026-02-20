/// Chizze — Appwrite Database Setup Script
///
/// Creates database, collections, attributes, indexes, and permissions
/// for the entire Chizze food delivery app.
///
/// Usage:
///   cd tools/appwrite_setup
///   dart pub get
///   dart run bin/setup.dart <YOUR_APPWRITE_API_KEY>
///
/// Get your API key from:
///   Appwrite Console → Project → Settings → API Keys → Create API Key
///   (grant all Database permissions)

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/enums.dart' as enums;

// ─── Configuration ───────────────────────────────────────────────────────────
const String endpoint = 'https://sgp.cloud.appwrite.io/v1';
const String projectId = '6993347c0006ead7404d';
const String databaseId = 'chizze_db';
const String databaseName = 'Chizze Database';

// ─── Main ────────────────────────────────────────────────────────────────────
void main(List<String> args) async {
  if (args.isEmpty) {
    print('❌ Usage: dart run bin/setup.dart <APPWRITE_API_KEY>');
    print('');
    print('   Get your API key from:');
    print('   Appwrite Console → Project → Settings → API Keys');
    print('   Grant all Database permissions.');
    return;
  }

  final apiKey = args[0];
  final client =
      Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);

  final databases = Databases(client);

  print('');
  print('╔══════════════════════════════════════════════╗');
  print('║       🍕 CHIZZE — Appwrite DB Setup         ║');
  print('╚══════════════════════════════════════════════╝');
  print('');

  try {
    // 1. Create database
    await _createDatabase(databases);

    // 2. Create all collections
    await _createUsersCollection(databases);
    await _createAddressesCollection(databases);
    await _createRestaurantsCollection(databases);
    await _createMenuCategoriesCollection(databases);
    await _createMenuItemsCollection(databases);
    await _createOrdersCollection(databases);
    await _createCouponsCollection(databases);
    await _createNotificationsCollection(databases);
    await _createDeliveryRequestsCollection(databases);
    await _createRiderLocationsCollection(databases);
    await _createReviewsCollection(databases);
    await _createPaymentsCollection(databases);

    print('');
    print('═══════════════════════════════════════════════');
    print('✅ All 12 collections created successfully!');
    print('═══════════════════════════════════════════════');
    print('');
    print('📋 Collections summary:');
    print('   users, addresses, restaurants, menu_categories,');
    print('   menu_items, orders, coupons, notifications,');
    print('   delivery_requests, rider_locations, reviews, payments');
    print('');
    print('🔗 Database ID: $databaseId');
    print('   Update realtime_service.dart → RealtimeChannels.databaseId');
    print('');
  } catch (e) {
    print('❌ Error: $e');
  }
}

// ─── Helper ──────────────────────────────────────────────────────────────────
/// Delay between API calls to avoid rate limiting
Future<void> _pause() => Future.delayed(const Duration(milliseconds: 300));

/// Safe attribute creation — skips if attribute already exists
Future<void> _safeAttr(Future<void> Function() fn) async {
  try {
    await fn();
    await _pause();
  } catch (e) {
    if (e.toString().contains('already exists')) {
      // Attribute already exists, skip
    } else {
      print('   ⚠️ Attribute warning: $e');
    }
  }
}

/// Safe index creation
Future<void> _safeIndex(Future<void> Function() fn) async {
  try {
    await fn();
    await _pause();
  } catch (e) {
    if (e.toString().contains('already exists')) {
      // Index already exists, skip
    } else {
      print('   ⚠️ Index warning: $e');
    }
  }
}

// ─── Database ────────────────────────────────────────────────────────────────
Future<void> _createDatabase(Databases db) async {
  print('📦 Creating database: $databaseName ...');
  try {
    await db.create(databaseId: databaseId, name: databaseName);
    print('   ✅ Database created');
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Database already exists, continuing...');
    } else {
      rethrow;
    }
  }
}

// ─── 1. Users Collection ─────────────────────────────────────────────────────
Future<void> _createUsersCollection(Databases db) async {
  const id = 'users';
  print('');
  print('👤 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Users',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'name',
      size: 128,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'phone',
      size: 20,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createEmailAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'email',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createUrlAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'avatar_url',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'role',
      size: 20,
      xrequired: false,
      xdefault: 'customer',
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_veg',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'dark_mode',
      xrequired: false,
      xdefault: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'default_address_id',
      size: 36,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'fcm_token',
      size: 256,
      xrequired: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_phone',
      type: enums.IndexType.unique,
      attributes: ['phone'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_role',
      type: enums.IndexType.key,
      attributes: ['role'],
    ),
  );

  print('   ✅ users (9 attributes, 2 indexes)');
}

// ─── 2. Addresses Collection ─────────────────────────────────────────────────
Future<void> _createAddressesCollection(Databases db) async {
  const id = 'addresses';
  print('📍 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Addresses',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'user_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'label',
      size: 50,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'full_address',
      size: 500,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'landmark',
      size: 200,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'latitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'longitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_default',
      xrequired: false,
      xdefault: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_user',
      type: IndexType.key,
      attributes: ['user_id'],
    ),
  );

  print('   ✅ addresses (7 attributes, 1 index)');
}

// ─── 3. Restaurants Collection ───────────────────────────────────────────────
Future<void> _createRestaurantsCollection(Databases db) async {
  const id = 'restaurants';
  print('🍽️  Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Restaurants',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.team('admin')),
        Permission.update(Role.team('admin')),
      ],
      documentSecurity: false,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'owner_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'name',
      size: 128,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'description',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createUrlAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'cover_image_url',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createUrlAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'logo_url',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'cuisines',
      size: 500,
      xrequired: false,
      array: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'address',
      size: 500,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'latitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'longitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'city',
      size: 100,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'rating',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'total_ratings',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'price_for_two',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'avg_delivery_time_min',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_veg_only',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_online',
      xrequired: false,
      xdefault: true,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_featured',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_promoted',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'opening_time',
      size: 10,
      xrequired: false,
      xdefault: '09:00',
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'closing_time',
      size: 10,
      xrequired: false,
      xdefault: '23:00',
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_owner',
      type: IndexType.key,
      attributes: ['owner_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_city',
      type: IndexType.key,
      attributes: ['city'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_online',
      type: IndexType.key,
      attributes: ['is_online'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_featured',
      type: IndexType.key,
      attributes: ['is_featured'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_rating',
      type: IndexType.key,
      attributes: ['rating'],
      orders: [enums.OrderBy.desc],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_name',
      type: enums.IndexType.fulltext,
      attributes: ['name'],
    ),
  );

  print('   ✅ restaurants (20 attributes, 6 indexes)');
}

// ─── 4. Menu Categories Collection ───────────────────────────────────────────
Future<void> _createMenuCategoriesCollection(Databases db) async {
  const id = 'menu_categories';
  print('📂 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Menu Categories',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      documentSecurity: false,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'name',
      size: 100,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'sort_order',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_active',
      xrequired: false,
      xdefault: true,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_restaurant',
      type: IndexType.key,
      attributes: ['restaurant_id'],
    ),
  );

  print('   ✅ menu_categories (4 attributes, 1 index)');
}

// ─── 5. Menu Items Collection ────────────────────────────────────────────────
Future<void> _createMenuItemsCollection(Databases db) async {
  const id = 'menu_items';
  print('🍔 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Menu Items',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      documentSecurity: false,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'category_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'name',
      size: 200,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'description',
      size: 1000,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'price',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createUrlAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'image_url',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_veg',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_available',
      xrequired: false,
      xdefault: true,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_bestseller',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_must_try',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'spice_level',
      elements: ['mild', 'medium', 'spicy', 'extra_spicy'],
      xrequired: false,
      xdefault: 'mild',
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'preparation_time_min',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'customizations',
      size: 5000,
      xrequired: false,
    ),
  ); // JSON string
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'calories',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'allergens',
      size: 200,
      xrequired: false,
      array: true,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'sort_order',
      xrequired: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_restaurant',
      type: IndexType.key,
      attributes: ['restaurant_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_category',
      type: IndexType.key,
      attributes: ['category_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_veg',
      type: IndexType.key,
      attributes: ['is_veg'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_name',
      type: IndexType.fulltext,
      attributes: ['name'],
    ),
  );

  print('   ✅ menu_items (16 attributes, 4 indexes)');
}

// ─── 6. Orders Collection ────────────────────────────────────────────────────
Future<void> _createOrdersCollection(Databases db) async {
  const id = 'orders';
  print('📋 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Orders',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'order_number',
      size: 30,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'customer_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_name',
      size: 128,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_partner_id',
      size: 36,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_partner_name',
      size: 128,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_partner_phone',
      size: 20,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_address_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'items',
      size: 10000,
      xrequired: true,
    ),
  ); // JSON array
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'item_total',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_fee',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'platform_fee',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'gst',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'discount',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'coupon_code',
      size: 30,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'tip',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'grand_total',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'payment_method',
      elements: ['upi', 'card', 'cod', 'wallet', 'netbanking'],
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'payment_status',
      elements: ['pending', 'paid', 'failed', 'refunded'],
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'payment_id',
      size: 100,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'razorpay_order_id',
      size: 100,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'status',
      elements: [
        'placed',
        'confirmed',
        'preparing',
        'ready',
        'pickedUp',
        'outForDelivery',
        'delivered',
        'cancelled',
      ],
      xrequired: true,
      xdefault: 'placed',
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'special_instructions',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivery_instructions',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'estimated_delivery_min',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'placed_at',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'confirmed_at',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'prepared_at',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'picked_up_at',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'delivered_at',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'cancelled_at',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'cancellation_reason',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'cancelled_by',
      size: 36,
      xrequired: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_customer',
      type: IndexType.key,
      attributes: ['customer_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_restaurant',
      type: IndexType.key,
      attributes: ['restaurant_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_status',
      type: IndexType.key,
      attributes: ['status'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_rider',
      type: IndexType.key,
      attributes: ['delivery_partner_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_order_num',
      type: IndexType.unique,
      attributes: ['order_number'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_placed',
      type: IndexType.key,
      attributes: ['placed_at'],
      orders: [OrderType.desc],
    ),
  );

  print('   ✅ orders (33 attributes, 6 indexes)');
}

// ─── 7. Coupons Collection ───────────────────────────────────────────────────
Future<void> _createCouponsCollection(Databases db) async {
  const id = 'coupons';
  print('🎟️  Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Coupons',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.team('admin')),
        Permission.update(Role.team('admin')),
        Permission.delete(Role.team('admin')),
      ],
      documentSecurity: false,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'code',
      size: 30,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'title',
      size: 128,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'description',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'discount_percent',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'max_discount',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'min_order',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'expires_at',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'usage_limit',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'usage_count',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_id',
      size: 36,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_active',
      xrequired: false,
      xdefault: true,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_code',
      type: IndexType.unique,
      attributes: ['code'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_active',
      type: IndexType.key,
      attributes: ['is_active'],
    ),
  );

  print('   ✅ coupons (11 attributes, 2 indexes)');
}

// ─── 8. Notifications Collection ─────────────────────────────────────────────
Future<void> _createNotificationsCollection(Databases db) async {
  const id = 'notifications';
  print('🔔 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Notifications',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'user_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'title',
      size: 200,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'body',
      size: 1000,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'type',
      elements: ['order', 'promo', 'system'],
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_read',
      xrequired: false,
      xdefault: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'data',
      size: 2000,
      xrequired: false,
    ),
  ); // JSON payload

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_user',
      type: IndexType.key,
      attributes: ['user_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_read',
      type: IndexType.key,
      attributes: ['is_read'],
    ),
  );

  print('   ✅ notifications (6 attributes, 2 indexes)');
}

// ─── 9. Delivery Requests Collection ─────────────────────────────────────────
Future<void> _createDeliveryRequestsCollection(Databases db) async {
  const id = 'delivery_requests';
  print('🛵 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Delivery Requests',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'order_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'rider_id',
      size: 36,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_name',
      size: 128,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_address',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_latitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_longitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'customer_address',
      size: 500,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'customer_latitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'customer_longitude',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'distance_km',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'estimated_earning',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'status',
      elements: ['pending', 'accepted', 'rejected', 'expired'],
      xrequired: false,
      xdefault: 'pending',
    ),
  );
  await _safeAttr(
    () => db.createDatetimeAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'expires_at',
      xrequired: true,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_rider',
      type: IndexType.key,
      attributes: ['rider_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_order',
      type: IndexType.key,
      attributes: ['order_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_status',
      type: IndexType.key,
      attributes: ['status'],
    ),
  );

  print('   ✅ delivery_requests (13 attributes, 3 indexes)');
}

// ─── 10. Rider Locations Collection ──────────────────────────────────────────
Future<void> _createRiderLocationsCollection(Databases db) async {
  const id = 'rider_locations';
  print('📡 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Rider Locations',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'rider_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'latitude',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'longitude',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'heading',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'speed',
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createBooleanAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'is_online',
      xrequired: false,
      xdefault: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_rider',
      type: IndexType.unique,
      attributes: ['rider_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_online',
      type: IndexType.key,
      attributes: ['is_online'],
    ),
  );

  print('   ✅ rider_locations (6 attributes, 2 indexes)');
}

// ─── 11. Reviews Collection ──────────────────────────────────────────────────
Future<void> _createReviewsCollection(Databases db) async {
  const id = 'reviews';
  print('⭐ Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Reviews',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'user_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'order_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'restaurant_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'rating',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'comment',
      size: 2000,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'reply',
      size: 1000,
      xrequired: false,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_restaurant',
      type: IndexType.key,
      attributes: ['restaurant_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_user',
      type: IndexType.key,
      attributes: ['user_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_order',
      type: IndexType.unique,
      attributes: ['order_id'],
    ),
  );

  print('   ✅ reviews (6 attributes, 3 indexes)');
}

// ─── 12. Payments Collection ─────────────────────────────────────────────────
Future<void> _createPaymentsCollection(Databases db) async {
  const id = 'payments';
  print('💳 Creating collection: $id ...');

  try {
    await db.createCollection(
      databaseId: databaseId,
      collectionId: id,
      name: 'Payments',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
      ],
      documentSecurity: true,
    );
  } catch (e) {
    if (e.toString().contains('already exists')) {
      print('   ⏭️  Collection exists, adding attributes...');
    } else {
      rethrow;
    }
  }

  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'order_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'user_id',
      size: 36,
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'razorpay_order_id',
      size: 100,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'razorpay_payment_id',
      size: 100,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createStringAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'razorpay_signature',
      size: 256,
      xrequired: false,
    ),
  );
  await _safeAttr(
    () => db.createFloatAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'amount',
      xrequired: true,
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'status',
      elements: ['pending', 'success', 'failed', 'refunded'],
      xrequired: true,
      xdefault: 'pending',
    ),
  );
  await _safeAttr(
    () => db.createEnumAttribute(
      databaseId: databaseId,
      collectionId: id,
      key: 'method',
      elements: ['upi', 'card', 'cod', 'wallet', 'netbanking'],
      xrequired: true,
    ),
  );

  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_order',
      type: IndexType.key,
      attributes: ['order_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_user',
      type: IndexType.key,
      attributes: ['user_id'],
    ),
  );
  await _safeIndex(
    () => db.createIndex(
      databaseId: databaseId,
      collectionId: id,
      key: 'idx_status',
      type: IndexType.key,
      attributes: ['status'],
    ),
  );

  print('   ✅ payments (8 attributes, 3 indexes)');
}
