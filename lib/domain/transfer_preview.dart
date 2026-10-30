import 'ledger.dart';

/// Balances and validation for replacing or recording a wallet transfer.
///
/// The visible current values always come from the persisted ledger snapshot.
/// For an edit, availability and projections are calculated after removing the
/// edited posting so changing its amount or direction does not count it twice.
class TransferPreview {
  const TransferPreview({
    required this.source,
    required this.destination,
    required this.walletsExist,
    required this.sourceCurrent,
    required this.destinationCurrent,
    required this.sourceAvailable,
    required this.activeTotalCurrent,
    required this.transferAllCentavos,
    required this.transferAllWasCapped,
    required this.centavos,
    required this.sourceAfter,
    required this.destinationAfter,
    required this.activeTotalAfter,
    required this.error,
  });

  final Wallet source;
  final Wallet destination;
  final bool walletsExist;
  final int sourceCurrent;
  final int destinationCurrent;
  final int sourceAvailable;
  final int activeTotalCurrent;
  final int transferAllCentavos;
  final bool transferAllWasCapped;
  final int? centavos;
  final int? sourceAfter;
  final int? destinationAfter;
  final int? activeTotalAfter;
  final String? error;

  bool get canTransfer => centavos != null && error == null;
  bool get canTransferAll =>
      walletsExist && source != destination && sourceAvailable > 0;
}

TransferPreview previewTransfer(
  Ledger ledger, {
  required Wallet source,
  required Wallet destination,
  required String amount,
  String? editingId,
}) {
  final actualSource = ledger.wallet(source);
  final actualDestination = ledger.wallet(destination);
  final resolvedSource = actualSource ?? source;
  final resolvedDestination = actualDestination ?? destination;

  final edited = editingId == null ? null : ledger.entry(editingId);
  final basis = edited == null
      ? ledger
      : ledger.copy(
          entries: ledger.entries
              .where((entry) => entry.id != edited.id)
              .toList(),
        );
  final sourceCurrent = ledger.calculate(source).balance;
  final destinationCurrent = ledger.calculate(destination).balance;
  final sourceAvailable = basis.calculate(source).balance;
  final activeTotalCurrent = ledger.activeWalletBalance;
  final cappedTransferAll = sourceAvailable > maxCentavos;
  final transferAllCentavos = sourceAvailable.clamp(0, maxCentavos).toInt();

  String? error;
  int? cents;
  if (actualSource == null || actualDestination == null) {
    error = 'Choose available wallets before saving.';
  } else if (source == destination) {
    error = 'Choose two different wallets for a transfer.';
  }
  if (error == null && amount.isNotEmpty) {
    try {
      cents = parseMoney(amount);
    } on LedgerException catch (exception) {
      error = exception.message;
    }
  }
  if (error == null && cents != null && cents > sourceAvailable) {
    error =
        'Not enough in ${resolvedSource.label}. Available: ${money(sourceAvailable)}.';
  }

  int? sourceAfter;
  int? destinationAfter;
  int? activeTotalAfter;
  if (cents != null && error == null) {
    sourceAfter = sourceAvailable - cents;
    destinationAfter = basis.calculate(destination).balance + cents;
    activeTotalAfter = basis.activeWalletBalance;
    if (!resolvedSource.archived) activeTotalAfter -= cents;
    if (!resolvedDestination.archived) activeTotalAfter += cents;
  }

  return TransferPreview(
    source: resolvedSource,
    destination: resolvedDestination,
    walletsExist: actualSource != null && actualDestination != null,
    sourceCurrent: sourceCurrent,
    destinationCurrent: destinationCurrent,
    sourceAvailable: sourceAvailable,
    activeTotalCurrent: activeTotalCurrent,
    transferAllCentavos: transferAllCentavos,
    transferAllWasCapped: cappedTransferAll,
    centavos: cents,
    sourceAfter: sourceAfter,
    destinationAfter: destinationAfter,
    activeTotalAfter: activeTotalAfter,
    error: error,
  );
}
