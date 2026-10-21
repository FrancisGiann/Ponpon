import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../domain/ledger.dart';
import 'storage.dart';

/// Another engine committed after this reader's snapshot. Never overwrite it.
class LedgerChangedException implements Exception {
  const LedgerChangedException();
}

/// Android serializes snapshots and compare-and-save across foreground and job
/// engines. Draft and recovery files retain the existing private file format.
class CoordinatedLedgerStore extends FileLedgerStore {
  CoordinatedLedgerStore(super.directory);
  static const channel = MethodChannel('dev.giann.pocket_entry/ledger');
  String? revision;
  bool _loaded = false, _readable = false, _currentValid = false;

  static Future<Directory> privateDirectory() async =>
      Directory((await channel.invokeMethod<String>('privatePath'))!);

  void onChanged(Future<void> Function()? callback) {
    channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'ledgerChanged') await callback();
            },
    );
  }

  @override
  Future<LoadResult> load() async {
    final data = (await channel.invokeMapMethod<String, dynamic>('snapshot'))!;
    revision = data['revision'] as String;
    _loaded = true;
    _readable = false;
    _currentValid = false;
    final decoded = await Isolate.run(() => _decodeSnapshot(data));
    _readable = true;
    _currentValid = decoded.$2;
    return decoded.$1;
  }

  @override
  Future<void> save(Ledger ledger) => _save(ledger, recovery: false);

  /// Only the explicit bootstrap restore flow may replace unreadable records.
  Future<void> recover(Ledger ledger) => _save(ledger, recovery: true);

  Future<void> _save(Ledger ledger, {required bool recovery}) async {
    if (!_loaded) await load();
    if (!_readable && !recovery) {
      throw const LedgerException(
        'Reopen your saved records or restore a valid backup before saving.',
      );
    }
    final encoded = await Isolate.run(() => _encodeLedger(ledger));
    try {
      revision = await channel.invokeMethod<String>('save', {
        'expectedRevision': revision,
        'encoded': encoded,
        'preserveCurrent': _currentValid,
      });
      _readable = _currentValid = true;
    } on PlatformException catch (e) {
      if (e.code == 'conflict') throw const LedgerChangedException();
      rethrow;
    }
  }
}

String _encodeLedger(Ledger ledger) {
  final encoded = ledger.encode();
  Ledger.decode(encoded);
  return encoded;
}

(LoadResult, bool) _decodeSnapshot(Map<String, dynamic> data) {
  Ledger decode(dynamic bytes) =>
      Ledger.decode(utf8.decode((bytes as List).cast<int>()));
  if (data['currentPresent'] != true && data['previousPresent'] != true) {
    return (LoadResult(Ledger.empty()), false);
  }
  try {
    return (LoadResult(decode(data['current'])), true);
  } catch (_) {
    try {
      return (
        LoadResult(
          decode(data['previous']),
          notice: 'Recovered the previous save. Review your most recent entry before adding another.',
        ),
        false,
      );
    } catch (_) {
      throw const LedgerException(
        'Your saved ledger could not be opened. Your files are preserved. Retry or restore a valid backup.',
      );
    }
  }
}
