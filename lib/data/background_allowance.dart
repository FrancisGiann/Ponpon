import '../domain/ledger.dart';
import 'coordinated_store.dart';
import 'native_bridge.dart';

/// The same domain processor as foreground catch-up, against a fresh snapshot.
/// Conflicts re-read the schedule and wallet, never merge a stale whole ledger.
Future<bool> processBackgroundAllowance(
  CoordinatedLedgerStore store, {
  NativeBridge bridge = const NativeBridge(),
  DateTime Function()? clock,
}) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final loaded = await store.load();
      // Recovery needs the user's review, never an unattended overwrite.
      if (loaded.notice != null) return false;
      final result = catchUpAllowance(loaded.ledger, (clock ?? DateTime.now)());
      if (!identical(result.ledger, loaded.ledger)) {
        await store.save(result.ledger);
      }
      await bridge.sync(
        result.ledger,
        revision: store.revision,
        foreground: false,
      );
      return true;
    } on LedgerChangedException {
      continue;
    } catch (_) {
      // No partial domain result is committed. JobScheduler can retry and the
      // app's launch/resume processor remains the fallback.
      return false;
    }
  }
  return false;
}
