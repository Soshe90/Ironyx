import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';
import 'package:ironyx/features/auth/domain/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Drives the real Supabase client against a local HTTP server, so the
/// service's own sequencing and error mapping are what is under test — not
/// a fake of it. Nothing leaves the machine.
void main() {
  late HttpServer server;
  late List<String> requests;
  late int rpcStatus;
  late int logoutStatus;
  late sb.SupabaseClient client;
  late SupabaseAuthService service;

  /// An unsigned JWT the client can decode (it never verifies signatures;
  /// the server does). Expiry far in the future so no refresh is attempted.
  String accessToken(String userId) {
    String part(Map<String, Object> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': userId, 'exp': 4102444800, 'role': 'authenticated'})}'
        '.signature';
  }

  setUp(() async {
    requests = [];
    rpcStatus = 204;
    logoutStatus = 204;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      final int status = request.uri.path.endsWith('/rpc/delete_my_account')
          ? rpcStatus
          : request.uri.path.endsWith('/logout')
              ? logoutStatus
              : 404;
      request.response.statusCode = status;
      if (status >= 400) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'message': 'server error'}));
      }
      await request.response.close();
    });

    client = sb.SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'anon-key',
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': accessToken('user-1'),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': 4102444800,
        'refresh_token': 'refresh',
        'user': {
          'id': 'user-1',
          'aud': 'authenticated',
          'email': 'tester@example.com',
          'app_metadata': <String, Object>{},
          'user_metadata': <String, Object>{},
          'created_at': '2026-09-01T00:00:00Z',
        },
      }),
    );
    service = SupabaseAuthService(client);
    expect(service.currentUser?.id, 'user-1');
  });

  tearDown(() async {
    await service.dispose();
    await client.dispose();
    await server.close(force: true);
  });

  test('deleting an account deletes it, then signs out locally', () async {
    await service.deleteAccount();

    expect(requests, [
      'POST /rest/v1/rpc/delete_my_account',
      'POST /auth/v1/logout',
    ]);
    expect(service.currentUser, isNull);
  });

  test(
      'a failed logout call after a successful deletion still reports '
      'success — the account is already gone', () async {
    logoutStatus = 500;

    await service.deleteAccount();

    expect(requests, contains('POST /auth/v1/logout'));
    expect(service.currentUser, isNull);
  });

  test('a failed deletion is reported and leaves the user signed in', () async {
    rpcStatus = 500;

    await expectLater(service.deleteAccount(), throwsA(isA<AuthFailure>()));

    expect(requests, ['POST /rest/v1/rpc/delete_my_account']);
    expect(service.currentUser?.id, 'user-1');
  });
}
