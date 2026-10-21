part of 'screens.dart';

String billFrequencyLabel(BillFrequency frequency) => switch (frequency) {
  BillFrequency.once => 'Once',
  BillFrequency.weekly => 'Weekly',
  BillFrequency.monthly => 'Monthly',
  BillFrequency.yearly => 'Yearly',
};

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
      final pending = [
        for (final bill in app.ledger.bills)
          if (bill.nextDue(app.ledger) case final String due) (bill, due),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      final inactive = app.ledger.bills.where(
        (b) => b.nextDue(app.ledger) == null,
      );
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
            if (app.ledger.bills.isEmpty)
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
            if (inactive.isNotEmpty)
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final bill in inactive)
                      GroupRow(
                        bill.name,
                        last: bill == inactive.last,
                        subtitle: bill.enabled
                            ? 'Paid · no more due dates'
                            : 'Paused',
                        icon: CupertinoIcons.calendar,
                        onTap: () => pushPocket<void>(
                          context,
                          BillEditorPage(app: app, bill: bill),
                        ),
                      ),
                  ],
                ),
              ),
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
  late String start = widget.bill?.startDate ?? dayKey(widget.app.clock());
  late BillFrequency frequency =
      widget.bill?.frequency ?? BillFrequency.monthly;
  late bool enabled = widget.bill?.enabled ?? true,
      remind = widget.bill?.remind ?? false;
  bool permissionBusy = false;
  String? error;
  bool get hasHistory => widget.app.ledger.entries.any((e) => e.billId == id);
  @override
  void dispose() {
    name.dispose();
    amount.dispose();
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
      final bill = Bill.fromJson(
        Bill(
          id: id,
          name: name.text.trim(),
          centavos: parseMoney(amount.text),
          startDate: start,
          frequency: frequency,
          enabled: enabled,
          remind: remind,
        ).toJson(),
      );
      final saved = await widget.app.setBill(bill);
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
                          : () => setState(() => frequency = option),
                      last: option == BillFrequency.values.last,
                    ),
                ],
              ),
            ),
            if (hasHistory) ...[
              const SizedBox(height: 12),
              Text(
                'Payment history is kept. To change the recurrence, pause this bill and create a new one.',
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
              onPressed: app.busy || permissionBusy ? null : save,
            ),
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

  Future<void> record() async {
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
      Navigator.pop(context);
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
