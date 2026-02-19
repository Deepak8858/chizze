// Quick test to verify Appwrite Cloud connection
// Run: dart run test/appwrite_connection_test.dart

import 'package:appwrite/appwrite.dart';

void main() async {
  print('🔗 Testing Appwrite Cloud connection...\n');

  final client = Client()
      .setProject('6993347c0006ead7404d')
      .setEndpoint('https://sgp.cloud.appwrite.io/v1');

  // Test 1: Ping the server
  print('📡 Test 1: Ping Appwrite Cloud...');
  try {
    await client.ping();
    print('   ✅ Ping successful! Appwrite Cloud is reachable.\n');
  } catch (e) {
    print('   ❌ Ping failed: $e\n');
  }

  // Test 2: Check Health
  print('🏥 Test 2: Check Appwrite Health...');
  try {
    final health = Health(client);
    final result = await health.get();
    print('   ✅ Health check passed!');
    print('   Status: ${result.status}');
    print('   Version: ${result.version}\n');
  } catch (e) {
    print('   ❌ Health check failed: $e\n');
  }

  // Test 3: List Auth providers (anonymous access)
  print('👤 Test 3: Check Account service...');
  try {
    final account = Account(client);
    // This will fail with 401 (not logged in) — that's expected and proves the API works
    await account.get();
    print('   ✅ Already logged in!\n');
  } catch (e) {
    if (e is AppwriteException) {
      if (e.code == 401) {
        print(
          '   ✅ Account service is working! (Got expected 401 - not logged in)\n',
        );
      } else {
        print('   ⚠️  Got response code ${e.code}: ${e.message}\n');
      }
    } else {
      print('   ❌ Account check failed: $e\n');
    }
  }

  // Test 4: Check Database service
  print('📦 Test 4: Check Databases service...');
  try {
    final databases = Databases(client);
    // This will also fail without auth, but proves the endpoint works
    await databases.listDocuments(databaseId: 'test', collectionId: 'test');
  } catch (e) {
    if (e is AppwriteException) {
      print('   ✅ Database service is responding! (Code: ${e.code})');
      print('   Message: ${e.message}\n');
    } else {
      print('   ❌ Database check failed: $e\n');
    }
  }

  // Test 5: Check Storage service
  print('🗂️  Test 5: Check Storage service...');
  try {
    final storage = Storage(client);
    await storage.listFiles(bucketId: 'test');
  } catch (e) {
    if (e is AppwriteException) {
      print('   ✅ Storage service is responding! (Code: ${e.code})');
      print('   Message: ${e.message}\n');
    } else {
      print('   ❌ Storage check failed: $e\n');
    }
  }

  print('═══════════════════════════════════════');
  print('🎉 Appwrite Cloud connection test complete!');
  print('   Endpoint: https://sgp.cloud.appwrite.io/v1');
  print('   Project:  6993347c0006ead7404d');
  print('   Region:   Singapore (SGP)');
  print('═══════════════════════════════════════');
}
