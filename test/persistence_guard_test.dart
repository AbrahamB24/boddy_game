import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/services/settlement_service.dart';

// Block A (user 2026-07-25): progress writes must only SWALLOW a pre-migration
// schema gap and RETHROW real/transient failures, so a dropped save surfaces
// (the "unsaved" indicator) and retries instead of silently losing a boss clear.
void main() {
  group('isMissingSchema — only pre-migration gaps are swallowed', () {
    test('recognises the migration-gap errors', () {
      for (final msg in [
        'PostgrestException(message: column "battles_cleared" does not exist)',
        "Could not find the 'expansions_unlocked' column of 'profiles'",
        'PGRST204 schema cache',
        'error 42703: undefined_column',
        'error 42P01: relation "path_nodes" does not exist',
      ]) {
        expect(SettlementService.isMissingSchema(Exception(msg)), isTrue,
            reason: msg);
      }
    });

    test('does NOT swallow real / transient failures', () {
      for (final msg in [
        'SocketException: Failed host lookup',
        'TimeoutException after 0:00:10',
        'new row violates row-level security policy',
        'Connection closed before full header was received',
      ]) {
        expect(SettlementService.isMissingSchema(Exception(msg)), isFalse,
            reason: msg);
      }
    });
  });
}
