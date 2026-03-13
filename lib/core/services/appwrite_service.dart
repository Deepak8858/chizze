import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/environment.dart';

/// Appwrite Client — singleton across the app
final appwriteClientProvider = Provider<Client>((ref) {
  final client = Client()
      .setEndpoint(Environment.appwritePublicEndpoint)
      .setProject(Environment.appwriteProjectId);
  return client;
});

/// Appwrite Account service
final appwriteAccountProvider = Provider<Account>((ref) {
  return Account(ref.watch(appwriteClientProvider));
});

/// Appwrite Databases service
final appwriteDatabasesProvider = Provider<Databases>((ref) {
  return Databases(ref.watch(appwriteClientProvider));
});

/// Appwrite Storage service
final appwriteStorageProvider = Provider<Storage>((ref) {
  return Storage(ref.watch(appwriteClientProvider));
});

/// Appwrite Realtime service
final appwriteRealtimeProvider = Provider<Realtime>((ref) {
  return Realtime(ref.watch(appwriteClientProvider));
});
