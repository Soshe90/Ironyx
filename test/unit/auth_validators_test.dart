import 'package:fittrack/features/auth/domain/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('accepts ordinary addresses, including plus tags and subdomains', () {
      for (final String value in <String>[
        'a@b.co',
        'mustafa.salih15@gmail.com',
        'user+tag@example.co.uk',
        'someone@mail.sub.example.org',
      ]) {
        expect(AuthValidators.email(value), isNull, reason: value);
      }
    });

    test('trims before validating, so a stray space is not an error', () {
      expect(AuthValidators.email('  user@example.com  '), isNull);
    });

    test('rejects the typos it exists to catch', () {
      for (final String value in <String>[
        '',
        '   ',
        'nobody',
        'no@domain',
        '@example.com',
        'two words@example.com',
      ]) {
        expect(AuthValidators.email(value), isNotNull, reason: '"$value"');
      }
    });

    test('null is treated as empty rather than throwing', () {
      expect(AuthValidators.email(null), 'Enter your email.');
    });
  });

  group('password', () {
    test('accepts anything at or over the minimum length', () {
      expect(AuthValidators.password('a' * AuthValidators.minPasswordLength),
          isNull);
    });

    test('rejects one character short', () {
      expect(
        AuthValidators.password('a' * (AuthValidators.minPasswordLength - 1)),
        isNotNull,
      );
    });

    test('does not trim — a leading space is a real character', () {
      // 8 characters including the space. Trimming here would tell the user
      // their password is fine and then send a different one.
      expect(AuthValidators.password(' 1234567'), isNull);
    });
  });

  group('signInPassword', () {
    test('checks presence only, so an old short password still signs in', () {
      expect(AuthValidators.signInPassword('abc'), isNull);
      expect(AuthValidators.signInPassword(''), isNotNull);
    });
  });

  group('confirmPassword', () {
    test('passes when the two match', () {
      expect(AuthValidators.confirmPassword('hunter22', 'hunter22'), isNull);
    });

    test('fails on a mismatch and on an empty confirmation', () {
      expect(AuthValidators.confirmPassword('hunter22', 'hunter23'), isNotNull);
      expect(AuthValidators.confirmPassword('', 'hunter22'), isNotNull);
    });
  });
}
