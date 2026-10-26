import 'package:flutter/services.dart';

import '../domain/ledger.dart';
import 'coordinated_store.dart';

class ReminderState {
  const ReminderState({
    this.enabled = false,
    this.minuteOfDay,
    this.permitted = true,
    this.nextAtMilliseconds,
  });
  final bool enabled, permitted;
  final int? minuteOfDay, nextAtMilliseconds;
  factory ReminderState.fromMap(Map<dynamic, dynamic>? value) {
    final minute = value?['minuteOfDay'];
    return ReminderState(
      enabled: value?['enabled'] == true,
      permitted: value?['permitted'] == true,
      minuteOfDay: minute is int && minute >= 0 && minute < 1440
          ? minute
          : null,
      nextAtMilliseconds: value?['nextAtMilliseconds'] is int
          ? value!['nextAtMilliseconds'] as int
          : null,
    );
  }
}

class NativeBridge {
  const NativeBridge();
  static const channel = MethodChannel('dev.giann.pocket_entry/native');
  Future<String> privatePath() async =>
      (await channel.invokeMethod<String>('privatePath'))!;
  Future<Map<dynamic, dynamic>?> initialEntry() =>
      channel.invokeMapMethod<dynamic, dynamic>('initialEntry');
  Future<ReminderState> reminderState() async => ReminderState.fromMap(
    await channel.invokeMapMethod<dynamic, dynamic>('reminderState'),
  );
  Future<ReminderState> setReminder({
    required bool enabled,
    int? minuteOfDay,
  }) async => ReminderState.fromMap(
    await channel.invokeMapMethod<dynamic, dynamic>('setReminder', {
      'enabled': enabled,
      'minuteOfDay': minuteOfDay,
    }),
  );
  Future<bool> requestBillReminderPermission() async =>
      await channel.invokeMethod<bool>('requestBillReminderPermission') ??
      false;
  Future<bool> requestReminderPermission() async =>
      await channel.invokeMethod<bool>('requestReminderPermission') ?? false;
  Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('openNotificationSettings');
  Future<void> sync(
    Ledger ledger, {
    String? revision,
    bool foreground = true,
  }) async {
    final selected = ledger.quickCategories;
    final billReminders = <Map<String, dynamic>>[
      for (final bill in ledger.bills)
        if (bill.enabled && bill.remind && bill.nextDue(ledger) != null)
          {
            'id': bill.id,
            'startDate': bill.startDate,
            'frequency': bill.frequency.name,
            'paidDates': ledger.billPaidDates(bill.id).toList()..sort(),
          },
    ];
    final payload = <String, dynamic>{
      'ledgerRevision': ?revision,
      'billReminders': billReminders,
      'theme': ledger.preferences.effectiveTheme,
      'visualStyle': ledger.preferences.visualStyle.name,
      'privatePreview': ledger.preferences.privatePreview,
      'balanceWidgetVisible': ledger.preferences.balanceWidgetVisible,
      'balanceCentavos': ledger.activeWalletBalance,
      'activeWalletCount': ledger.availableWallets.length,
      'wideCategories': [
        for (final category in selected)
          {
            'id': category.id,
            'name': category.name,
            'icon': category.icon,
            'kind': category.isIncome ? 'income' : 'expense',
          },
      ],
      'wallets':
          [
                ...ledger.availableWallets.where(
                  (w) => ledger.calculate(w).balance != 0,
                ),
                ...ledger.availableWallets.where(
                  (w) => ledger.calculate(w).balance == 0,
                ),
              ]
              .map(
                (w) => {
                  'id': w.id,
                  'name': w.label,
                  'balanceCentavos': ledger.calculate(w).balance,
                },
              )
              .toList(),
      'categories': selected
          .map((c) => {'id': c.id, 'name': c.name, 'icon': c.icon})
          .toList(),
    };
    if (revision == null) {
      await channel.invokeMethod<void>('syncAppearance', payload);
    } else {
      await CoordinatedLedgerStore.channel.invokeMethod<void>(
        'syncSnapshot',
        payload,
      );
      if (foreground) {
        await channel.invokeMethod<void>('setPrivatePreview', {
          'enabled': ledger.preferences.privatePreview,
        });
      }
    }
  }

  Future<bool> export(String text, String name) async =>
      await channel.invokeMethod<bool>('exportBackup', {
        'text': text,
        'name': name,
      }) ??
      false;
  Future<String?> pickBackup() => channel.invokeMethod<String>('pickBackup');
  Future<bool> pinWidget({
    bool compact = false,
    bool balance = false,
    bool incomeExpense = false,
    bool walletOverview = false,
    bool wideBalance = false,
  }) async =>
      await channel.invokeMethod<bool>('pinWidget', {
        'compact': compact,
        'balance': balance,
        'incomeExpense': incomeExpense,
        'walletOverview': walletOverview,
        'wideBalance': wideBalance,
      }) ??
      false;
}
