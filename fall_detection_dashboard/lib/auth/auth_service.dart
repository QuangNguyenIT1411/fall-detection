import 'package:supabase_flutter/supabase_flutter.dart';

class CaregiverIdentity {
  const CaregiverIdentity(this.id, this.email);

  final String id;
  final String? email;
}

abstract interface class AuthService {
  Future<CaregiverIdentity?> restoreSession();
  Stream<CaregiverIdentity?> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  CaregiverIdentity? _identity(User? user) =>
      user == null ? null : CaregiverIdentity(user.id, user.email);

  @override
  Future<CaregiverIdentity?> restoreSession() async =>
      _identity(_client.auth.currentSession?.user);

  @override
  Stream<CaregiverIdentity?> get changes => _client.auth.onAuthStateChange.map(
    (event) => _identity(event.session?.user),
  );

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
