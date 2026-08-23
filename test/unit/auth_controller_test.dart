import 'package:fittrack/features/auth/domain/auth_controller.dart';
import 'package:fittrack/features/auth/domain/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';

void main() {
  late FakeAuthService service;
  late ProviderContainer container;

  ProviderContainer containerWith(FakeAuthService fake) {
    final c = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    service = FakeAuthService();
    addTearDown(service.dispose);
    container = containerWith(service);
  });

  test('starts signed out when there is no restored session', () {
    expect(container.read(authControllerProvider), isNull);
  });

  test('starts signed in from a session restored before the first frame', () {
    final restored = FakeAuthService(
      initialUser: const AuthUser(
        id: 'u1',
        email: 'a@b.co',
        isEmailConfirmed: true,
      ),
    );
    addTearDown(restored.dispose);

    // Synchronous on purpose: a cold *offline* launch must resolve the
    // session without awaiting anything, or the app is unusable on a plane.
    expect(
        containerWith(restored).read(authControllerProvider)?.email, 'a@b.co');
  });

  test('sign-up signs the user in when confirmation is not required', () async {
    final outcome = await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@example.com', password: 'hunter22');

    expect(outcome, SignUpOutcome.signedIn);
    expect(container.read(authControllerProvider)?.email, 'new@example.com');
  });

  test('sign-up leaves the user signed out when confirmation is required',
      () async {
    service.requiresEmailConfirmation = true;

    final outcome = await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@example.com', password: 'hunter22');

    expect(outcome, SignUpOutcome.confirmationEmailSent);
    // The account exists, but nobody is signed in. Conflating these two
    // outcomes would strand the user on a screen that thinks they are.
    expect(container.read(authControllerProvider), isNull);
  });

  test('sign-up on an existing email reports it rather than overwriting',
      () async {
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.signUp(email: 'taken@example.com', password: 'hunter22');

    expect(
      () => notifier.signUp(email: 'taken@example.com', password: 'other123'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.emailAlreadyRegistered,
        ),
      ),
    );
  });

  test('sign-in with the wrong password fails and leaves state signed out',
      () async {
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.signUp(email: 'a@b.co', password: 'hunter22');
    await notifier.signOut();

    await expectLater(
      notifier.signIn(email: 'a@b.co', password: 'wrong-one'),
      throwsA(isA<AuthFailure>()
          .having((f) => f.kind, 'kind', AuthFailureKind.wrongCredentials)),
    );
    expect(container.read(authControllerProvider), isNull);
  });

  test('a network failure surfaces as offline, not as a bad password',
      () async {
    service.nextFailure = AuthFailureKind.offline;

    await expectLater(
      container
          .read(authControllerProvider.notifier)
          .signIn(email: 'a@b.co', password: 'hunter22'),
      throwsA(isA<AuthFailure>()
          .having((f) => f.kind, 'kind', AuthFailureKind.offline)),
    );
  });

  test('sign-out clears the session', () async {
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.signUp(email: 'a@b.co', password: 'hunter22');
    expect(container.read(authControllerProvider), isNotNull);

    await notifier.signOut();
    expect(container.read(authControllerProvider), isNull);
  });

  test('an externally dropped session is picked up from the stream', () async {
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.signUp(email: 'a@b.co', password: 'hunter22');

    // An expired refresh token, say — the backend signs us out without the
    // app asking.
    service.emitExternalChange(null);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authControllerProvider), isNull);
  });

  test('every failure kind has its own non-generic message', () {
    // Found the hard way: `email_address_invalid` had no case and fell
    // through to "Something went wrong. Try again.", which tells the user
    // nothing about which field to fix. This guards the whole enum against
    // the same omission.
    final messages = <String>{};
    for (final kind in AuthFailureKind.values) {
      final String message = AuthFailure(kind).message;
      expect(message, isNotEmpty, reason: kind.name);
      if (kind != AuthFailureKind.unknown) {
        expect(
          message,
          isNot(const AuthFailure(AuthFailureKind.unknown).message),
          reason: '${kind.name} falls back to the generic message',
        );
      }
      messages.add(message);
    }
    expect(messages, hasLength(AuthFailureKind.values.length),
        reason: 'two kinds share wording, so one of them is unactionable');
  });

  test('password reset asks the backend to send a link', () async {
    await container
        .read(authControllerProvider.notifier)
        .sendPasswordReset('  Someone@Example.COM ');

    expect(service.passwordResetsSent, ['someone@example.com']);
  });

  group('when the build has no Supabase credentials', () {
    late ProviderContainer disabled;

    setUp(() {
      disabled = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(const DisabledAuthService()),
        ],
      );
      addTearDown(disabled.dispose);
    });

    test('reports itself unavailable so the UI can explain', () {
      expect(disabled.read(authAvailableProvider), isFalse);
      expect(disabled.read(authControllerProvider), isNull);
    });

    test('sign-in fails as notConfigured instead of crashing', () {
      expect(
        () => disabled
            .read(authControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'hunter22'),
        throwsA(isA<AuthFailure>()
            .having((f) => f.kind, 'kind', AuthFailureKind.notConfigured)),
      );
    });

    test('sign-out is a no-op rather than an error', () {
      expect(
          disabled.read(authControllerProvider.notifier).signOut(), completes);
    });
  });
}
