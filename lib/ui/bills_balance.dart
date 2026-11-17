part of 'screens.dart';

String billFrequencyLabel(BillFrequency frequency) => switch (frequency) {
  BillFrequency.once => 'Once',
  BillFrequency.weekly => 'Weekly',
  BillFrequency.monthly => 'Monthly',
  BillFrequency.yearly => 'Yearly',
};

Future<void> showBillSchedule(
  BuildContext context,
  Bill bill,
  Ledger ledger, {
  required DateTime now,
}) => showPocketSheet<void>(
  context: context,
  builder: (_) => _BillScheduleSheet(bill: bill, ledger: ledger, now: now),
);

Future<void> showSafeToSpendDetails(
  BuildContext context,
  AppController app,
  SafeToSpendSummary summary,
) => showPocketSheet<void>(
  context: context,
  builder: (_) => _SafeToSpendSheet(app: app, summary: summary),
);

class SafeToSpendCard extends StatelessWidget {
  const SafeToSpendCard({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final summary = app.ledger.safeToSpend(app.clock());
    final nearest = summary.nearestDueDate;
    final dueSubtitle = summary.duePaymentCount == 0
        ? 'No unpaid bill payments due through ${shortDate(dayKey(summary.throughDate))}.'
        : '${money(summary.dueCentavos)} set aside for ${summary.duePaymentCount} due or overdue ${summary.duePaymentCount == 1 ? 'payment' : 'payments'} · ${nearest == null
              ? ''
              : nearest.compareTo(dayKey(app.clock())) < 0
              ? 'oldest overdue'
              : 'next due'} ${nearest == null ? '' : shortDate(nearest)}';
    final subtitle = summary.activeWalletCount == 0
        ? 'No active wallets · $dueSubtitle'
        : dueSubtitle;
    final cardContent = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.calendar, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Safe to spend',
                  style: textStyle(context, size: 16, weight: FontWeight.w700),
                ),
              ),
              Press(
                key: const ValueKey('safe-to-spend-add-bill'),
                label: 'Add bill',
                onPressed: app.busy
                    ? null
                    : () => pushPocket<void>(context, BillEditorPage(app: app)),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.add, size: 15, color: p.accent),
                    const SizedBox(width: 3),
                    Text(
                      'Add bill',
                      style: textStyle(context, size: 13, color: p.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Semantics(
            key: const ValueKey('safe-to-spend-amount-semantics'),
            label: summary.safeCentavos == null
                ? 'No active wallets'
                : summary.safeCentavos! < 0
                ? 'Shortfall ${money(summary.safeCentavos!.abs())}'
                : money(summary.safeCentavos!),
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  summary.safeCentavos == null
                      ? '—'
                      : money(summary.safeCentavos!),
                  key: const ValueKey('safe-to-spend-amount'),
                  maxLines: 1,
                  style: textStyle(
                    context,
                    size: 28,
                    weight: FontWeight.w700,
                    tabular: true,
                    color: (summary.safeCentavos ?? 0) < 0 ? p.danger : p.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            summary.safeCentavos != null && summary.safeCentavos! < 0
                ? 'Shortfall after scheduled bills · $subtitle'
                : subtitle,
            key: const ValueKey('safe-to-spend-subtitle'),
            style: textStyle(context, size: 12, color: p.secondary),
          ),
          if (summary.duePaymentCount > 0)
            Press(
              key: const ValueKey('safe-to-spend-details'),
              label: 'View safe to spend breakdown',
              onPressed: () => showSafeToSpendDetails(context, app, summary),
              padding: const EdgeInsets.only(top: 6, bottom: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'View breakdown',
                      style: textStyle(context, size: 13, color: p.accent),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14, color: p.accent),
                ],
              ),
            ),
        ],
      ),
    );
    if (p.adventure) {
      return PixelFrame(
        key: const ValueKey('safe-to-spend-card'),
        fillColor: p.surface,
        child: cardContent,
      );
    }
    return Surface(
      key: const ValueKey('safe-to-spend-card'),
      padding: EdgeInsets.zero,
      child: cardContent,
    );
  }
}

class _SafeToSpendSheet extends StatelessWidget {
  const _SafeToSpendSheet({required this.app, required this.summary});
  final AppController app;
  final SafeToSpendSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Safe to spend',
      subtitle: 'Bills due through ${shortDate(dayKey(summary.throughDate))}',
      height: 660,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Surface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    summary.safeCentavos == null
                        ? 'No active wallets'
                        : summary.safeCentavos! < 0
                        ? 'Shortfall ${money(summary.safeCentavos!.abs())}'
                        : money(summary.safeCentavos!),
                    key: const ValueKey('safe-to-spend-sheet-amount'),
                    style: textStyle(
                      context,
                      size: 26,
                      weight: FontWeight.w700,
                      tabular: true,
                      color: (summary.safeCentavos ?? 0) < 0 ? p.danger : p.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${money(summary.walletBalanceCentavos)} active wallet balance · ${money(summary.dueCentavos)} scheduled',
                    style: textStyle(context, size: 12, color: p.secondary),
                  ),
                ],
              ),
            ),
          ),
          if (summary.duePaymentCount == 0)
            Expanded(
              child: Center(
                child: Text(
                  'No unpaid bill payments in this date range.',
                  style: textStyle(context, size: 14, color: p.secondary),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                key: const ValueKey('safe-to-spend-breakdown'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                itemCount: summary.duePaymentCount,
                itemBuilder: (context, index) {
                  final due = summary.occurrenceAt(index);
                  final overdue =
                      due.dueDate.compareTo(dayKey(app.clock())) < 0;
                  return GroupRow(
                    due.bill.name,
                    subtitle:
                        '${overdue ? 'Overdue' : 'Due'} ${shortDate(due.dueDate)}',
                    trailing: Text(
                      money(due.centavos),
                      style: textStyle(
                        context,
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SecondaryButton(
              'View all bills',
              icon: CupertinoIcons.calendar,
              onPressed: () {
                Navigator.pop(context);
                pushPocket<void>(context, BillsPage(app: app));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BillInstallmentProgress extends StatelessWidget {
  const BillInstallmentProgress({
    super.key,
    required this.bill,
    required this.ledger,
    this.onTap,
  });
  final Bill bill;
  final Ledger ledger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = bill.paymentCount;
    if (count == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    final paid = bill.paidInstallments(ledger).clamp(0, count);
    final value = (paid / count).clamp(0.0, 1.0).toDouble();
    final remaining = bill.remainingCentavos(ledger);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$paid/$count installments paid · ${money(remaining)} remaining',
                style: textStyle(context, size: 13, color: p.secondary),
              ),
            ),
            if (onTap != null)
              Icon(CupertinoIcons.chevron_right, color: p.secondary, size: 14),
          ],
        ),
        const SizedBox(height: 7),
        Semantics(
          label: '$paid of $count installments paid',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  SizedBox(
                    key: ValueKey('bill-progress-track-${bill.id}'),
                    width: constraints.maxWidth,
                    height: 8,
                    child: ColoredBox(color: p.line),
                  ),
                  SizedBox(
                    key: ValueKey('bill-progress-fill-${bill.id}'),
                    width: constraints.maxWidth * value,
                    height: 8,
                    child: ColoredBox(color: p.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return Press(
      label:
          'View payment schedule, $paid of $count installments paid, ${money(remaining)} remaining',
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: content,
    );
  }
}

class _BillScheduleSheet extends StatelessWidget {
  const _BillScheduleSheet({
    required this.bill,
    required this.ledger,
    required this.now,
  });
  final Bill bill;
  final Ledger ledger;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final count = bill.paymentCount ?? 0;
    final paidDates = ledger.billPaidDates(bill.id);
    final nextDue = bill.nextDue(ledger);
    final paidCount = bill.paidInstallments(ledger);
    return SheetFrame(
      title: 'Payment schedule',
      subtitle:
          '$paidCount of $count paid · ${money(bill.remainingCentavos(ledger))} remaining',
      height: 600,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        itemCount: count + (bill.paymentCount == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (bill.paymentCount != null && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BillInstallmentProgress(bill: bill, ledger: ledger),
            );
          }
          if (bill.paymentCount != null) index--;
          final due = bill.occurrence(index);
          if (due == null) return const SizedBox.shrink();
          final isPaid = paidDates.contains(due);
          final status = isPaid
              ? 'Paid'
              : due == nextDue
              ? 'Next due'
              : due.compareTo(dayKey(now)) < 0
              ? 'Overdue'
              : 'Upcoming';
          final p = Palette.of(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isPaid
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: isPaid ? p.green : p.secondary,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Payment ${index + 1}',
                      style: textStyle(context, weight: FontWeight.w600),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(shortDate(due), style: textStyle(context, size: 13)),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: textStyle(
                          context,
                          size: 12,
                          color: isPaid ? p.green : p.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class BalanceCheckPage extends StatefulWidget {
  const BalanceCheckPage({super.key, required this.app, required this.wallet});
  final AppController app;
  final Wallet wallet;
  @override
  State<BalanceCheckPage> createState() => _BalanceCheckState();
}

class _BalanceCheckState extends State<BalanceCheckPage> {
  final actual = TextEditingController();
  BalanceCheck? review;
  String? error;
  bool reviewing = false;
  @override
  void dispose() {
    actual.dispose();
    super.dispose();
  }

  void compare() {
    try {
      final value = widget.app.checkBalance(
        widget.wallet,
        parseMoney(actual.text, signed: true, allowZero: true),
      );
      setState(() {
        review = value;
        error = null;
      });
    } on LedgerException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> record() async {
    final check = review;
    if (check == null || widget.app.busy || reviewing) return;
    setState(() => reviewing = true);
    final bool approved;
    try {
      approved = await confirm(
        context,
        title: 'Record a balance adjustment?',
        message:
            '${widget.wallet.label}: ${money(check.expected)} tracked, ${money(check.actual)} actual. '
            'Record ${money(check.difference)} as a separate adjustment. Your opening balance and past entries stay unchanged.',
        action: 'Record adjustment',
      );
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
    if (!approved || !mounted) return;
    final saved = await widget.app.confirmBalanceCheck(check, confirmed: true);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        error = widget.app.storageError;
        review = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context);
      final check = review;
      return PocketPage(
        'Check balance',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.wallet.label,
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'Tracked balance ${money(widget.app.ledger.calculate(widget.wallet).balance)}',
              style: textStyle(context, color: p.secondary),
            ),
            const SizedBox(height: 20),
            Text('Actual balance', style: formLabelStyle(context)),
            const SizedBox(height: 6),
            Text(
              'Compare with the same tracked balance shown in your wallets, including all recorded entries.',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
            const SizedBox(height: 8),
            PocketTextField(
              key: const ValueKey('balance-check-actual'),
              controller: actual,
              money: true,
              placeholder: 'Amount in PHP',
              maxLength: 13,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onChanged: (_) => setState(() {
                review = null;
                error = null;
              }),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              'Compare balance',
              onPressed: widget.app.busy ? null : compare,
            ),
            if (check != null) ...[
              const SizedBox(height: 24),
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    EntryFact('Tracked', money(check.expected)),
                    EntryFact('Actual', money(check.actual)),
                    EntryFact(
                      'Difference',
                      money(check.difference),
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (check.difference == 0)
                const QuietMessage(
                  'Your balance matches',
                  'No adjustment is needed.',
                )
              else ...[
                Text(
                  'An adjustment is a separate record, not income or spending. You can undo it after saving.',
                  style: textStyle(context, size: 14, color: p.secondary),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  'Review adjustment',
                  onPressed: widget.app.busy || reviewing ? null : record,
                ),
              ],
            ],
            const SizedBox(height: 12),
            ErrorLine(error),
          ],
        ),
      );
    },
  );
}

class BillsPage extends StatelessWidget {
  const BillsPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final p = Palette.of(context);
      final liveBills = app.ledger.bills
          .where((bill) => !bill.deleted)
          .toList();
      final pending = [
        for (final bill in liveBills)
          if (bill.nextDue(app.ledger) case final String due) (bill, due),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      final inactive = liveBills.where((b) => b.nextDue(app.ledger) == null);
      String inactiveSubtitle(Bill bill) {
        if (!bill.enabled) return 'Paused';
        final count = bill.paymentCount;
        if (count != null && bill.paidInstallments(app.ledger) >= count) {
          return 'All installments paid · $count/$count';
        }
        return 'Paid · no more due dates';
      }

      return PocketPage(
        'Upcoming bills',
        trailing: Press(
          label: 'Add bill',
          onPressed: app.busy
              ? null
              : () => pushPocket<void>(context, BillEditorPage(app: app)),
          child: const Icon(CupertinoIcons.add),
        ),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'A little ahead.',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'Reminders never record a payment. Choose a wallet when you have paid.',
              style: textStyle(context, size: 15, color: p.secondary),
            ),
            const SizedBox(height: 20),
            if (liveBills.isEmpty)
              const QuietMessage(
                'No bills yet',
                'Add a due date and choose how often it repeats.',
              ),
            for (final (bill, due) in pending) ...[
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.name,
                      style: textStyle(
                        context,
                        size: 20,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      money(bill.centavos),
                      style: textStyle(
                        context,
                        size: 24,
                        weight: FontWeight.w600,
                        tabular: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${due.compareTo(dayKey(app.clock())) < 0 ? 'Overdue' : 'Due'} ${shortDate(due)} · ${billFrequencyLabel(bill.frequency)}',
                      style: textStyle(context, size: 14, color: p.secondary),
                    ),
                    if (bill.paymentCount != null) ...[
                      const SizedBox(height: 6),
                      BillInstallmentProgress(
                        bill: bill,
                        ledger: app.ledger,
                        onTap: () => showBillSchedule(
                          context,
                          bill,
                          app.ledger,
                          now: app.clock(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    PrimaryButton(
                      'Record payment',
                      onPressed: app.busy
                          ? null
                          : () => pushPocket<void>(
                              context,
                              BillPaymentPage(
                                app: app,
                                bill: bill,
                                dueDate: due,
                              ),
                            ),
                    ),
                    Press(
                      onPressed: app.busy
                          ? null
                          : () => pushPocket<void>(
                              context,
                              BillEditorPage(app: app, bill: bill),
                            ),
                      child: const Text('Edit bill'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            for (final bill in inactive) ...[
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    GroupRow(
                      bill.name,
                      subtitle: inactiveSubtitle(bill),
                      icon: CupertinoIcons.calendar,
                      trailing: Press(
                        label: 'Edit ${bill.name}',
                        padding: const EdgeInsets.all(10),
                        onPressed: app.busy
                            ? null
                            : () => pushPocket<void>(
                                context,
                                BillEditorPage(app: app, bill: bill),
                              ),
                        child: Icon(
                          CupertinoIcons.pencil,
                          color: p.secondary,
                          size: 18,
                        ),
                      ),
                      onTap: bill.paymentCount == null
                          ? () => pushPocket<void>(
                              context,
                              BillEditorPage(app: app, bill: bill),
                            )
                          : () => showBillSchedule(
                              context,
                              bill,
                              app.ledger,
                              now: app.clock(),
                            ),
                    ),
                    if (bill.paymentCount != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                        child: BillInstallmentProgress(
                          bill: bill,
                          ledger: app.ledger,
                          onTap: () => showBillSchedule(
                            context,
                            bill,
                            app.ledger,
                            now: app.clock(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            SecondaryButton(
              'Add a bill',
              icon: CupertinoIcons.add,
              onPressed: app.busy
                  ? null
                  : () => pushPocket<void>(context, BillEditorPage(app: app)),
            ),
          ],
        ),
      );
    },
  );
}

class BillEditorPage extends StatefulWidget {
  const BillEditorPage({super.key, required this.app, this.bill});
  final AppController app;
  final Bill? bill;
  @override
  State<BillEditorPage> createState() => _BillEditorState();
}

class _BillEditorState extends State<BillEditorPage> {
  late final id = widget.bill?.id ?? newId();
  late final name = TextEditingController(text: widget.bill?.name ?? '');
  late final amount = TextEditingController(
    text: widget.bill == null ? '' : moneyInput(widget.bill!.centavos),
  );
  late final paymentCount = TextEditingController(
    text: widget.bill?.paymentCount?.toString() ?? '',
  );
  late String start = widget.bill?.startDate ?? dayKey(widget.app.clock());
  late BillFrequency frequency =
      widget.bill?.frequency ?? BillFrequency.monthly;
  late bool enabled = widget.bill?.enabled ?? true,
      remind = widget.bill?.remind ?? false;
  bool permissionBusy = false;
  bool deletionBusy = false;
  String? error;
  bool get hasHistory => widget.app.ledger.entries.any((e) => e.billId == id);
  String? get countPreviewDate {
    final count = int.tryParse(paymentCount.text.trim());
    if (count == null || count < 1 || count > maxBillPayments) return null;
    return Bill(
      id: id,
      name: 'Plan preview',
      centavos: 1,
      startDate: start,
      frequency: frequency,
      paymentCount: count,
    ).lastDueDate;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    paymentCount.dispose();
    super.dispose();
  }

  Future<void> date() async {
    var selected = localDay(start);
    await showPocketSheet<void>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'First due date',
        height: 350,
        action: Press(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          minimumDate: DateTime(1900),
          maximumDate: DateTime(2200, 12, 31),
          initialDateTime: selected,
          onDateTimeChanged: (value) => selected = value,
        ),
      ),
    );
    if (mounted) setState(() => start = dayKey(selected));
  }

  Future<void> reminders(bool value) async {
    if (!value) {
      setState(() => remind = false);
      return;
    }
    setState(() => permissionBusy = true);
    try {
      final allowed =
          await widget.app.bridge?.requestBillReminderPermission() ?? false;
      if (mounted) {
        setState(() {
          remind = allowed;
          error = allowed ? null : 'Allow Ponpon bill notifications in Android settings to enable reminders.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Bill reminders are available in the Android app.',
        );
      }
    } finally {
      if (mounted) setState(() => permissionBusy = false);
    }
  }

  Future<void> save() async {
    try {
      final rawCount = paymentCount.text.trim();
      final count = rawCount.isEmpty ? null : int.tryParse(rawCount);
      if (rawCount.isNotEmpty && count == null) {
        throw const LedgerException('Enter a whole number of payments.');
      }
      final bill = Bill.fromJson(
        Bill(
          id: id,
          name: name.text.trim(),
          centavos: parseMoney(amount.text),
          startDate: start,
          frequency: frequency,
          paymentCount: count,
          enabled: enabled,
          remind: remind,
        ).toJson(),
      );
      final saved = await widget.app.setBill(bill, reviewed: widget.bill);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => error = widget.app.storageError);
      }
    } on LedgerException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> deleteBill() async {
    final reviewed = widget.bill;
    if (reviewed == null || widget.app.busy || deletionBusy) return;
    final ledger = widget.app.ledger;
    final current = ledger.bill(reviewed.id);
    if (current == null || !sameBill(current, reviewed)) {
      setState(() => error = 'This bill changed. Reopen it before deleting.');
      return;
    }
    final payments = ledger.entries
        .where((entry) => entry.billId == current.id && !entry.deleted)
        .toList();
    final credits = <Wallet, int>{};
    for (final payment in payments) {
      credits.update(
        payment.wallet,
        (amount) => amount + payment.centavos,
        ifAbsent: () => payment.centavos,
      );
    }
    final creditLines = credits.entries
        .map((item) => '${item.key.label}: +${money(item.value)}')
        .join('\n');
    final message = payments.isEmpty
        ? 'This bill has no active recorded payments. Its payment history will stay in the backup and the deletion can be undone.'
        : 'This will reverse ${payments.length} active ${payments.length == 1 ? 'payment' : 'payments'} and credit the tracked wallet balances:\n$creditLines\n\nThe linked history is kept and the whole deletion can be undone.';
    setState(() => deletionBusy = true);
    final approved = await confirm(
      context,
      title: 'Delete this bill?',
      message: message,
      action: 'Delete bill and reverse payments',
      destructive: true,
    );
    if (!mounted) return;
    setState(() => deletionBusy = false);
    if (!approved) return;
    final deleted = await widget.app.deleteBill(current, payments);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      setState(() => error = widget.app.storageError);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final p = Palette.of(context), app = widget.app;
      return PocketPage(
        widget.bill == null ? 'Add bill' : 'Edit bill',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Bill name', style: formLabelStyle(context)),
            const SizedBox(height: 8),
            PocketTextField(
              key: const ValueKey('bill-name'),
              controller: name,
              maxLength: 60,
              placeholder: 'For example, Internet',
            ),
            const SizedBox(height: 20),
            Text('Amount in PHP', style: formLabelStyle(context)),
            const SizedBox(height: 8),
            PocketTextField(
              key: const ValueKey('bill-amount'),
              controller: amount,
              money: true,
              maxLength: 12,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              placeholder: '0.00',
            ),
            const SizedBox(height: 20),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'First due date',
                    subtitle: shortDate(start),
                    icon: CupertinoIcons.calendar,
                    onTap: app.busy || hasHistory ? null : date,
                  ),
                  for (final option in BillFrequency.values)
                    GroupRow(
                      billFrequencyLabel(option),
                      selected: frequency == option,
                      onTap: app.busy || hasHistory
                          ? null
                          : () => setState(() {
                              frequency = option;
                              if (option != BillFrequency.weekly &&
                                  option != BillFrequency.monthly) {
                                paymentCount.clear();
                              }
                            }),
                      last: option == BillFrequency.values.last,
                    ),
                ],
              ),
            ),
            if (frequency == BillFrequency.weekly ||
                frequency == BillFrequency.monthly) ...[
              const SizedBox(height: 20),
              Text('Number of payments', style: formLabelStyle(context)),
              const SizedBox(height: 8),
              PocketTextField(
                key: const ValueKey('bill-payment-count'),
                controller: paymentCount,
                maxLength: 5,
                keyboardType: TextInputType.number,
                placeholder: 'Leave blank to repeat until paused',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Text(
                hasHistory
                    ? 'The first due date and frequency stay fixed. Recorded installments must remain within the new count.'
                    : 'The first due date counts as payment 1. Leave blank to repeat until paused.',
                style: textStyle(context, size: 12, color: p.secondary),
              ),
              if (countPreviewDate case final String previewDate) ...[
                const SizedBox(height: 6),
                Text(
                  'Last installment due ${shortDate(previewDate)}',
                  style: textStyle(context, size: 14, color: p.secondary),
                ),
              ],
            ],
            if (hasHistory) ...[
              const SizedBox(height: 12),
              Text(
                'Payment history is kept. The first due date and frequency stay fixed. Adjust the count only if every recorded installment still fits.',
                style: textStyle(context, size: 13, color: p.secondary),
              ),
            ],
            const SizedBox(height: 20),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Active',
                    subtitle: 'Pause without removing payment history.',
                    trailing: PocketSwitch(
                      label: 'Bill active',
                      value: enabled,
                      onChanged: app.busy
                          ? null
                          : (value) => setState(() => enabled = value),
                    ),
                  ),
                  GroupRow(
                    'Remind me',
                    subtitle: 'Around 9 AM on the due date · device local time. Android may delay delivery.',
                    trailing: PocketSwitch(
                      key: const ValueKey('bill-reminder-switch'),
                      label: 'Bill reminder',
                      value: remind,
                      onChanged: app.busy || permissionBusy ? null : reminders,
                    ),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ErrorLine(error),
            PrimaryButton(
              'Save bill',
              onPressed: app.busy || permissionBusy || deletionBusy
                  ? null
                  : save,
            ),
            if (widget.bill != null) ...[
              const SizedBox(height: 12),
              Press(
                key: const ValueKey('bill-delete'),
                label: 'Delete bill and reverse recorded payments',
                onPressed: app.busy || permissionBusy || deletionBusy
                    ? null
                    : deleteBill,
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Center(
                  child: Text(
                    'Delete bill',
                    style: textStyle(
                      context,
                      size: 16,
                      weight: FontWeight.w600,
                      color: p.danger,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class BillPaymentPage extends StatefulWidget {
  const BillPaymentPage({
    super.key,
    required this.app,
    required this.bill,
    required this.dueDate,
  });
  final AppController app;
  final Bill bill;
  final String dueDate;
  @override
  State<BillPaymentPage> createState() => _BillPaymentState();
}

class _BillPaymentState extends State<BillPaymentPage> {
  Wallet? wallet;
  late Category? category = widget.app.ledger.availableCategories
      .where((c) => !c.isIncome && c.id == 'bills')
      .firstOrNull;
  String? error;
  bool reviewing = false;
  bool paymentSaved = false;
  int? recordedCentavos;

  Future<void> record() async {
    if (paymentSaved) {
      final payment = widget.app.ledger.entry(
        widget.bill.paymentId(widget.dueDate),
      );
      if (payment != null && !payment.deleted) return;
      setState(() {
        paymentSaved = false;
        recordedCentavos = null;
      });
    }
    if (widget.app.busy || reviewing) return;
    final selectedWallet = wallet, selectedCategory = category;
    if (selectedWallet == null || selectedCategory == null) {
      setState(() => error = 'Choose a wallet and expense category.');
      return;
    }
    setState(() => reviewing = true);
    final bool approved;
    try {
      approved = await confirm(
        context,
        title: 'Record this payment?',
        message:
            '${widget.bill.name}: ${money(widget.bill.centavos)} paid with ${selectedWallet.label}. '
            'Due ${shortDate(widget.dueDate)}; recorded ${shortDate(dayKey(widget.app.clock()))}. This records the payment only.',
        action: 'Record payment',
      );
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
    if (!approved || !mounted) return;
    final saved = await widget.app.recordBillPayment(
      widget.bill,
      widget.dueDate,
      selectedWallet,
      selectedCategory,
      confirmed: true,
    );
    if (!mounted) return;
    if (saved) {
      final payment = widget.app.ledger.entry(
        widget.bill.paymentId(widget.dueDate),
      );
      setState(() {
        paymentSaved = true;
        recordedCentavos = payment?.centavos ?? widget.bill.centavos;
      });
    } else {
      setState(() => error = widget.app.storageError);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final l = widget.app.ledger;
      final categories = l.availableCategories
          .where((c) => !c.isIncome)
          .toList();
      final payment = l.entry(widget.bill.paymentId(widget.dueDate));
      if (paymentSaved && payment != null && !payment.deleted) {
        final bill = l.bill(widget.bill.id) ?? widget.bill;
        final count = bill.paymentCount;
        final paid = count == null ? 0 : bill.paidInstallments(l);
        final remaining = bill.remainingCentavos(l);
        final nextDue = bill.nextDue(l);
        final completed = count != null && paid >= count;
        return PocketPage(
          completed ? 'Plan complete' : 'Payment saved',
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              Center(
                child: _BillCelebration(
                  completed: completed,
                  reducedMotion: MotionScope.of(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                completed ? 'All installments paid' : 'Payment recorded',
                textAlign: TextAlign.center,
                style: textStyle(context, size: 24, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${bill.name} · ${money(recordedCentavos ?? payment.centavos)}',
                textAlign: TextAlign.center,
                style: textStyle(
                  context,
                  size: 16,
                  color: Palette.of(context).secondary,
                ),
              ),
              if (count != null) ...[
                const SizedBox(height: 12),
                Text(
                  '$paid/$count installments paid · ${money(remaining)} remaining',
                  textAlign: TextAlign.center,
                  style: textStyle(context, size: 14),
                ),
                if (!completed && nextDue != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Next unpaid installment due ${shortDate(nextDue)}',
                    textAlign: TextAlign.center,
                    style: textStyle(
                      context,
                      size: 14,
                      color: Palette.of(context).secondary,
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Due ${shortDate(widget.dueDate)} · recorded ${shortDate(dayKey(widget.app.clock()))}',
                  textAlign: TextAlign.center,
                  style: textStyle(
                    context,
                    size: 14,
                    color: Palette.of(context).secondary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (count != null) ...[
                SecondaryButton(
                  'View payment schedule',
                  icon: CupertinoIcons.calendar,
                  onPressed: () => showBillSchedule(
                    context,
                    bill,
                    l,
                    now: widget.app.clock(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                'Back to bills',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        );
      }
      return PocketPage(
        'Record payment',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.bill.name,
              style: textStyle(context, size: 24, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              money(widget.bill.centavos),
              style: textStyle(
                context,
                size: 30,
                weight: FontWeight.w700,
                tabular: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose the wallet you paid with',
              style: textStyle(context, size: 16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final option in l.availableWallets)
                    GroupRow(
                      option.label,
                      subtitle: wallet == option ? 'Selected' : null,
                      icon: walletIcon(option.icon),
                      selected: wallet == option,
                      last: option == l.availableWallets.last,
                      onTap: widget.app.busy
                          ? null
                          : () => setState(() => wallet = option),
                    ),
                ],
              ),
            ),
            if (l.availableWallets.isEmpty)
              const Text('Restore or add a wallet before recording a payment.'),
            const SizedBox(height: 20),
            Text(
              'Expense category',
              style: textStyle(context, size: 16, weight: FontWeight.w600),
            ),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final option in categories)
                    GroupRow(
                      option.name,
                      subtitle: category?.id == option.id ? 'Selected' : null,
                      icon: categoryIcon(option.icon),
                      selected: category?.id == option.id,
                      last: option == categories.last,
                      onTap: widget.app.busy
                          ? null
                          : () => setState(() => category = option),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ErrorLine(error),
            PrimaryButton(
              'Review payment',
              onPressed: widget.app.busy || reviewing ? null : record,
            ),
          ],
        ),
      );
    },
  );
}

class _BillCelebration extends StatefulWidget {
  const _BillCelebration({
    required this.completed,
    required this.reducedMotion,
  });
  final bool completed, reducedMotion;

  @override
  State<_BillCelebration> createState() => _BillCelebrationState();
}

class _BillCelebrationState extends State<_BillCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.completed ? 1750 : 1350),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) _controller.forward();
  }

  @override
  void didUpdateWidget(_BillCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion && !oldWidget.reducedMotion) {
      _controller.stop();
    } else if (!widget.reducedMotion && oldWidget.reducedMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 188,
    height: 188,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = widget.reducedMotion ? 1.0 : _controller.value;
        final durationMilliseconds = widget.completed ? 1750 : 1350;
        final entryProgress = (progress * durationMilliseconds / 420)
            .clamp(0.0, 1.0)
            .toDouble();
        final finalScale = widget.completed ? 1.03 : 1.0;
        final scale = widget.reducedMotion
            ? 1.0
            : .64 +
                  Curves.easeOutBack.transform(entryProgress) *
                      (finalScale - .64);
        final palette = Palette.of(context);
        return CustomPaint(
          painter: widget.reducedMotion
              ? null
              : _BillBurstPainter(
                  progress: progress,
                  palette: palette,
                  completed: widget.completed,
                ),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Image.asset(
                key: ValueKey(
                  widget.completed
                      ? 'bill-celebration-completed'
                      : 'bill-celebration-paid',
                ),
                widget.completed
                    ? 'assets/celebrations/bill_completed.png'
                    : 'assets/celebrations/bill_paid.png',
                width: 108,
                height: 108,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _BillBurstPainter extends CustomPainter {
  const _BillBurstPainter({
    required this.progress,
    required this.palette,
    required this.completed,
  });
  final double progress;
  final Palette palette;
  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final colors = [palette.accent, palette.green, palette.blue, palette.amber];
    final count = completed ? 28 : 18;
    final center = Offset(size.width / 2, size.height / 2);
    final burst = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0).toDouble();
    for (var index = 0; index < count; index++) {
      final angle =
          math.pi * 2 * index / count -
          math.pi / 2 +
          math.sin(index * 2.17) * .18;
      final radius =
          16 + burst * (completed ? 72 : 62) * (.82 + (index % 5) * .09);
      final x = center.dx + math.cos(angle) * radius;
      final y =
          center.dy +
          math.sin(angle) * radius +
          progress * progress * (index.isEven ? 15 : -7);
      final width = index % 3 == 0 ? 6.0 : 4.0;
      final height = index % 3 == 0 ? 11.0 : 7.0;
      final color = colors[index % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle + progress * 4.2);
      final paint = Paint()..color = color;
      if (index % 4 == 0) {
        canvas.drawCircle(Offset.zero, 2.7, paint);
      } else if (index % 4 == 1) {
        final triangle = Path()
          ..moveTo(0, -5)
          ..lineTo(4, 3)
          ..lineTo(-4, 3)
          ..close();
        canvas.drawPath(triangle, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: width, height: height),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BillBurstPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.completed != completed ||
      oldDelegate.palette.dark != palette.dark ||
      oldDelegate.palette.style != palette.style;
}
