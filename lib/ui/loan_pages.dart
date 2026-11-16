part of 'screens.dart';

class LoansPage extends StatelessWidget {
  const LoansPage({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final ledger = app.ledger;
    final active = [...ledger.activeLoans]
      ..sort(
        (a, b) => a.borrower.toLowerCase().compareTo(b.borrower.toLowerCase()),
      );
    final outstanding = active
        .where((loan) => !loan.completed(ledger))
        .toList();
    final completed = active.where((loan) => loan.completed(ledger)).toList();
    final p = Palette.of(context);
    return ListView(
      key: const ValueKey('loans-scroll'),
      padding: EdgeInsets.zero,
      children: [
        PageHeading(
          'Loans',
          subtitle: 'Money owed to you',
          trailing: Press(
            label: 'Add loan',
            onPressed: app.busy
                ? null
                : () => pushPocket<void>(
                    context,
                    LoanEditorPage(app: app),
                    modal: true,
                  ),
            padding: const EdgeInsets.all(10),
            child: Icon(CupertinoIcons.plus, color: p.accent, size: 22),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Projected balance',
                  style: textStyle(context, size: 14, color: p.secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  money(ledger.loanProjectionBalance),
                  style: textStyle(
                    context,
                    size: 30,
                    weight: FontWeight.w700,
                    tabular: true,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${money(ledger.activeWalletBalance)} in wallets + ${money(ledger.outstandingLoanPrincipal)} owed to you',
                  style: textStyle(context, size: 12, color: p.secondary),
                ),
              ],
            ),
          ),
        ),
        if (outstanding.isEmpty && completed.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: QuietMessage(
              'No loans yet',
              'Track money someone owes you and record repayments as they arrive.',
            ),
          ),
        if (outstanding.isNotEmpty) ...[
          _LoanSectionTitle('${outstanding.length} outstanding'),
          for (final loan in outstanding)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _LoanRow(
                loan: loan,
                ledger: ledger,
                onTap: () => pushPocket<void>(
                  context,
                  LoanDetailPage(app: app, id: loan.id),
                ),
              ),
            ),
        ],
        if (completed.isNotEmpty) ...[
          _LoanSectionTitle('Completed'),
          for (final loan in completed)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _LoanRow(
                loan: loan,
                ledger: ledger,
                onTap: () => pushPocket<void>(
                  context,
                  LoanDetailPage(app: app, id: loan.id),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LoanSectionTitle extends StatelessWidget {
  const _LoanSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
    child: Text(
      title,
      style: textStyle(context, size: 17, weight: FontWeight.w600),
    ),
  );
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({
    required this.loan,
    required this.ledger,
    required this.onTap,
  });
  final Loan loan;
  final Ledger ledger;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final remaining = loan.remainingCentavos(ledger);
    final progress = loan.paidCentavos(ledger) / loan.principalCentavos;
    final p = Palette.of(context);
    return Surface(
      padding: EdgeInsets.zero,
      child: Press(
        onPressed: onTap,
        label: '${loan.borrower}, ${money(remaining)} remaining',
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loan.borrower,
                    style: textStyle(
                      context,
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  loan.completed(ledger) ? 'Paid' : money(remaining),
                  style: textStyle(
                    context,
                    size: 15,
                    weight: FontWeight.w600,
                    color: loan.completed(ledger) ? p.green : p.ink,
                    tabular: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${money(loan.paidCentavos(ledger))} paid of ${money(loan.principalCentavos)}',
              style: textStyle(context, size: 13, color: p.secondary),
            ),
            const SizedBox(height: 12),
            _LoanProgress(value: progress),
          ],
        ),
      ),
    );
  }
}

class _LoanProgress extends StatelessWidget {
  const _LoanProgress({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: p.tint),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0).toDouble(),
                child: ColoredBox(color: p.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoanEditorPage extends StatefulWidget {
  const LoanEditorPage({super.key, required this.app, this.loan});
  final AppController app;
  final Loan? loan;
  @override
  State<LoanEditorPage> createState() => _LoanEditorPageState();
}

class _LoanEditorPageState extends State<LoanEditorPage> {
  late final borrower = TextEditingController(
    text: widget.loan?.borrower ?? '',
  );
  late final principal = TextEditingController(
    text: widget.loan == null ? '' : moneyInput(widget.loan!.principalCentavos),
  );
  late final alreadyRepaid = TextEditingController(
    text: widget.loan == null
        ? '0.00'
        : widget.loan!.funded
        ? ''
        : moneyInput(widget.loan!.alreadyRepaidCentavos),
  );
  late final note = TextEditingController(text: widget.loan?.note ?? '');
  late String date = widget.loan?.date ?? dayKey(widget.app.clock());
  late String? dueDate = widget.loan?.dueDate;
  late bool existing = widget.loan?.funded == false;
  Wallet? fundingWallet;
  String? error;
  bool submitting = false;

  @override
  void dispose() {
    borrower.dispose();
    principal.dispose();
    alreadyRepaid.dispose();
    note.dispose();
    super.dispose();
  }

  Future<String?> _pickDate(
    String current,
    String title, {
    bool optional = false,
  }) async {
    var selected = localDay(current);
    final value = await showPocketSheet<String>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: title,
        height: 390,
        action: Press(
          label: 'Apply selected date',
          onPressed: () => Navigator.pop(ctx, dayKey(selected)),
          child: Text(
            'Done',
            style: textStyle(ctx, color: Palette.of(ctx).accent),
          ),
        ),
        child: Column(
          children: [
            if (optional)
              GroupRow('No due date', onTap: () => Navigator.pop(ctx, '')),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selected,
                minimumDate: DateTime(1900),
                maximumDate: DateTime(2200, 12, 31),
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );
    return value;
  }

  Future<void> save() async {
    if (submitting || widget.app.busy) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final name = borrower.text.trim();
      final amount = parseMoney(principal.text);
      final initialPaid = existing
          ? parseMoney(alreadyRepaid.text, allowZero: true)
          : 0;
      final loan = widget.loan;
      bool success;
      if (loan == null) {
        success = await widget.app.addLoan(
          borrower: name,
          principalCentavos: amount,
          date: date,
          dueDate: dueDate,
          note: note.text,
          alreadyExisting: existing,
          alreadyRepaidCentavos: initialPaid,
          fundingWallet: fundingWallet,
        );
      } else {
        success = await widget.app.updateLoan(
          loan,
          loan.copy(
            borrower: name,
            principalCentavos: amount,
            date: date,
            dueDate: dueDate,
            note: note.text.trim(),
            updatedAt: widget.app.clock().millisecondsSinceEpoch,
          ),
        );
      }
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
      } else {
        setState(
          () => error = widget.app.storageError ?? 'Loan could not be saved.',
        );
      }
    } on LedgerException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final wallets = widget.app.ledger.availableWallets;
    final fundedOriginalLocked = loan?.funded == true;
    return PocketPage(
      loan == null ? 'Add loan' : 'Edit loan',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Borrower',
            style: textStyle(
              context,
              size: 14,
              color: Palette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 8),
          PocketTextField(
            controller: borrower,
            placeholder: 'Name',
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 18),
          Text(
            'Original amount',
            style: textStyle(
              context,
              size: 14,
              color: Palette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 8),
          if (fundedOriginalLocked)
            Surface(
              child: Text(
                money(loan!.principalCentavos),
                style: textStyle(context, size: 20, weight: FontWeight.w600),
              ),
            )
          else
            PocketTextField(
              controller: principal,
              placeholder: '0.00',
              money: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          if (loan == null) ...[
            const SizedBox(height: 20),
            Text(
              'Loan source',
              style: textStyle(
                context,
                size: 14,
                color: Palette.of(context).secondary,
              ),
            ),
            const SizedBox(height: 8),
            CupertinoSlidingSegmentedControl<bool>(
              groupValue: existing,
              children: const {
                false: Text('New loan'),
                true: Text('Already existed'),
              },
              onValueChanged: (value) =>
                  setState(() => existing = value ?? false),
            ),
            const SizedBox(height: 8),
            Text(
              existing
                  ? 'Record the amount already repaid. Wallet balances will not change.'
                  : 'Choose where the money leaves your wallets.',
              style: textStyle(
                context,
                size: 12,
                color: Palette.of(context).secondary,
              ),
            ),
            if (existing) ...[
              const SizedBox(height: 10),
              PocketTextField(
                controller: alreadyRepaid,
                placeholder: 'Already repaid',
                money: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ] else if (wallets.isNotEmpty) ...[
              const SizedBox(height: 10),
              GroupRow(
                'Funding wallet',
                subtitle: fundingWallet?.label ?? wallets.first.label,
                icon: walletIcon(fundingWallet?.icon ?? wallets.first.icon),
                onTap: () async {
                  final chosen = await chooseWallet(
                    context,
                    wallets,
                    title: 'Funding wallet',
                  );
                  if (chosen != null && mounted) {
                    setState(() => fundingWallet = chosen);
                  }
                },
              ),
            ],
          ],
          const SizedBox(height: 18),
          GroupRow(
            'Loan date',
            subtitle: shortDate(date),
            icon: CupertinoIcons.calendar,
            onTap: () async {
              final value = await _pickDate(date, 'Loan date');
              if (value != null && mounted) setState(() => date = value);
            },
          ),
          const SizedBox(height: 8),
          GroupRow(
            'Due date',
            subtitle: dueDate == null ? 'Optional' : shortDate(dueDate!),
            icon: CupertinoIcons.calendar,
            onTap: () async {
              final value = await _pickDate(
                dueDate ?? date,
                'Due date',
                optional: true,
              );
              if (value != null && mounted) {
                setState(() => dueDate = value.isEmpty ? null : value);
              }
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Note',
            style: textStyle(
              context,
              size: 14,
              color: Palette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 8),
          PocketTextField(
            controller: note,
            placeholder: 'Optional details',
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          PrimaryButton('Save loan', onPressed: submitting ? null : save),
          ErrorLine(error ?? widget.app.storageError),
        ],
      ),
    );
  }
}

class LoanPaymentPage extends StatefulWidget {
  const LoanPaymentPage({
    super.key,
    required this.app,
    required this.loan,
    this.entry,
  });
  final AppController app;
  final Loan loan;
  final Entry? entry;
  @override
  State<LoanPaymentPage> createState() => _LoanPaymentPageState();
}

class _LoanPaymentPageState extends State<LoanPaymentPage> {
  late final amount = TextEditingController(
    text: widget.entry == null ? '' : moneyInput(widget.entry!.centavos),
  );
  late final note = TextEditingController(text: widget.entry?.note ?? '');
  late String date = widget.entry?.date ?? dayKey(widget.app.clock());
  late Wallet? wallet = widget.entry == null
      ? null
      : widget.app.ledger.wallet(widget.entry!.wallet);
  String? error;
  bool submitting = false;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<String?> pickDate() async {
    var selected = localDay(date);
    return showPocketSheet<String>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'Repayment date',
        height: 390,
        action: Press(
          label: 'Apply selected date',
          onPressed: () => Navigator.pop(ctx, dayKey(selected)),
          child: Text(
            'Done',
            style: textStyle(ctx, color: Palette.of(ctx).accent),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: selected,
          minimumDate: DateTime(1900),
          maximumDate: DateTime(2200, 12, 31),
          onDateTimeChanged: (value) => selected = value,
        ),
      ),
    );
  }

  Future<void> save() async {
    if (submitting || widget.app.busy || wallet == null) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final cents = parseMoney(amount.text);
      final success = widget.entry == null
          ? await widget.app.recordLoanRepayment(
              reviewed: widget.loan,
              centavos: cents,
              date: date,
              wallet: wallet!,
              note: note.text,
            )
          : await widget.app.correctLoanRepayment(
              previous: widget.entry!,
              centavos: cents,
              date: date,
              wallet: wallet!,
              note: note.text,
            );
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
      } else {
        setState(
          () => error =
              widget.app.storageError ?? 'Repayment could not be saved.',
        );
      }
    } on LedgerException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = widget.app.ledger.availableWallets;
    return PocketPage(
      widget.entry == null ? 'Record repayment' : 'Correct repayment',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.loan.borrower,
            style: textStyle(context, size: 22, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${money(widget.loan.remainingCentavos(widget.app.ledger))} remaining',
            style: textStyle(
              context,
              size: 14,
              color: Palette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 20),
          PocketTextField(
            controller: amount,
            placeholder: 'Amount',
            money: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          GroupRow(
            'Date received',
            subtitle: shortDate(date),
            icon: CupertinoIcons.calendar,
            onTap: () async {
              final value = await pickDate();
              if (value != null && mounted) setState(() => date = value);
            },
          ),
          const SizedBox(height: 8),
          GroupRow(
            'Received in',
            subtitle: wallet?.label ?? 'Choose a wallet',
            icon: walletIcon(wallet?.icon ?? 'wallet'),
            onTap: () async {
              final value = await chooseWallet(
                context,
                wallets,
                title: 'Received in',
              );
              if (value != null && mounted) setState(() => wallet = value);
            },
          ),
          const SizedBox(height: 16),
          PocketTextField(
            controller: note,
            placeholder: 'Note (optional)',
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            'Save repayment',
            onPressed: submitting || wallet == null ? null : save,
          ),
          ErrorLine(error ?? widget.app.storageError),
        ],
      ),
    );
  }
}

class LoanDetailPage extends StatefulWidget {
  const LoanDetailPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  Future<void> edit(Loan loan) async {
    await pushPocket<void>(
      context,
      LoanEditorPage(app: widget.app, loan: loan),
      modal: true,
    );
  }

  Future<void> remove(Loan loan) async {
    final approved = await confirm(
      context,
      title: 'Remove this loan?',
      message: 'The loan and all linked wallet movements and repayments will be removed together. You can undo this change.',
      action: 'Remove loan',
      destructive: true,
    );
    if (!approved || !mounted) return;
    final success = await widget.app.removeLoan(loan.id);
    if (success && mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.app.clearLoanCelebration(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final ledger = widget.app.ledger;
      final loan = ledger.loan(widget.id);
      if (loan == null || loan.deleted) {
        return const PocketPage(
          'Loan',
          child: QuietMessage('Loan unavailable', 'This loan was removed.'),
        );
      }
      final remaining = loan.remainingCentavos(ledger);
      final paid = loan.paidCentavos(ledger);
      final allActivity =
          ledger.entries.where((entry) => entry.loanId == loan.id).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      final finalCelebration = widget.app.celebratedLoanId == loan.id;
      final p = Palette.of(context);
      return PocketPage(
        loan.borrower,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (finalCelebration) ...[
              Center(
                child: _BillCelebration(
                  completed: true,
                  reducedMotion: MotionScope.of(context),
                ),
              ),
              Text(
                'Loan paid in full',
                textAlign: TextAlign.center,
                style: textStyle(
                  context,
                  size: 20,
                  weight: FontWeight.w700,
                  color: p.green,
                ),
              ),
              const SizedBox(height: 18),
            ],
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paid',
                    style: textStyle(context, size: 13, color: p.secondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    money(paid),
                    style: textStyle(
                      context,
                      size: 32,
                      weight: FontWeight.w700,
                      tabular: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${money(remaining)} remaining · ${money(loan.principalCentavos)} original',
                    style: textStyle(context, size: 14, color: p.secondary),
                  ),
                  const SizedBox(height: 14),
                  _LoanProgress(value: paid / loan.principalCentavos),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  EntryFact('Loan date', shortDate(loan.date)),
                  if (loan.dueDate != null)
                    EntryFact('Due date', shortDate(loan.dueDate!)),
                  EntryFact(
                    'Loan type',
                    loan.funded
                        ? 'New loan · wallet funded'
                        : 'Existing loan · balance carried in',
                  ),
                  EntryFact(
                    'Note',
                    loan.note.isEmpty ? 'No note added' : loan.note,
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!loan.completed(ledger)) ...[
              PrimaryButton(
                'Record repayment',
                icon: CupertinoIcons.arrow_down_circle,
                onPressed: widget.app.busy
                    ? null
                    : () => pushPocket<void>(
                        context,
                        LoanPaymentPage(app: widget.app, loan: loan),
                        modal: true,
                      ),
              ),
              const SizedBox(height: 10),
            ],
            SecondaryButton(
              'Edit loan',
              icon: CupertinoIcons.pencil,
              onPressed: widget.app.busy ? null : () => edit(loan),
            ),
            const SizedBox(height: 10),
            Press(
              onPressed: widget.app.busy ? null : () => remove(loan),
              child: Text(
                'Remove loan',
                textAlign: TextAlign.center,
                style: textStyle(context, color: p.danger),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Activity',
              style: textStyle(context, size: 18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (allActivity.isEmpty)
              Surface(
                child: Text(
                  'No wallet activity. This loan was already in progress when you added it.',
                  style: textStyle(context, size: 14, color: p.secondary),
                ),
              ),
            for (final entry in allActivity) ...[
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    EntryRow(entry: entry, ledger: ledger),
                    if (entry.deleted &&
                        entry.loanAction == LoanAction.repayment)
                      Press(
                        onPressed: widget.app.busy
                            ? null
                            : () => widget.app.restoreLoanRepayment(entry),
                        child: Text(
                          'Restore repayment',
                          style: textStyle(context, color: p.accent),
                        ),
                      ),
                    if (!entry.deleted &&
                        entry.loanAction == LoanAction.repayment)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                'Correct',
                                onPressed: widget.app.busy
                                    ? null
                                    : () => pushPocket<void>(
                                        context,
                                        LoanPaymentPage(
                                          app: widget.app,
                                          loan: loan,
                                          entry: entry,
                                        ),
                                        modal: true,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SecondaryButton(
                                'Remove',
                                onPressed: widget.app.busy
                                    ? null
                                    : () async {
                                        final yes = await confirm(
                                          context,
                                          title: 'Remove repayment?',
                                          message: 'This restores the amount due and reverses the wallet credit.',
                                          action: 'Remove',
                                        );
                                        if (yes) {
                                          await widget.app.removeLoanRepayment(
                                            entry,
                                          );
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            ErrorLine(widget.app.storageError),
          ],
        ),
      );
    },
  );
}
