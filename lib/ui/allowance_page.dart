part of 'screens.dart';

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class AllowancePage extends StatefulWidget {
  const AllowancePage({super.key, required this.app});
  final AppController app;
  @override
  State<AllowancePage> createState() => _AllowanceState();
}

class _AllowanceState extends State<AllowancePage> {
  late final TextEditingController amount = TextEditingController(
    text: widget.app.ledger.allowance == null
        ? ''
        : moneyInput(widget.app.ledger.allowance!.centavos),
  );
  late Wallet? wallet = widget.app.ledger.wallet(
    widget.app.ledger.allowance?.wallet,
  );
  late Set<int> days = {
    ...?widget.app.ledger.allowance?.days,
    if (widget.app.ledger.allowance == null) ...[1, 2, 3, 4, 5, 6, 7],
  };
  late bool enabled = widget.app.ledger.allowance?.enabled ?? false;
  late String start;
  String? error;
  @override
  void initState() {
    super.initState();
    if (wallet?.archived == true) wallet = null;
    final today = dayKey(widget.app.clock());
    final old = widget.app.ledger.allowance?.startDate;
    start = old != null && old.compareTo(today) > 0 ? old : today;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> chooseStart() async {
    var value = localDay(start);
    final today = localDay(dayKey(widget.app.clock()));
    await showPocketSheet<void>(
      context: context,
      builder: (ctx) => SheetFrame(
        title: 'Start date',
        height: 350,
        action: Press(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          minimumDate: today,
          maximumDate: DateTime(2200, 12, 31),
          initialDateTime: value,
          onDateTimeChanged: (date) => value = date,
        ),
      ),
    );
    if (mounted) setState(() => start = dayKey(value));
  }

  Future<void> save() async {
    try {
      if (wallet == null) {
        throw const LedgerException(
          'Choose the wallet receiving the allowance.',
        );
      }
      final cents = parseMoney(amount.text);
      final today = dayKey(widget.app.clock());
      if (enabled &&
          widget.app.ledger.allowance?.enabled != true &&
          start == today &&
          days.contains(widget.app.clock().weekday)) {
        final ok = await confirm(
          context,
          title: "Record today's allowance?",
          message:
              '${money(cents)} income will be recorded in ${wallet!.label}. Existing manual receipts are not matched. Start tomorrow if you already logged this receipt.',
          action: 'Record and enable',
        );
        if (!ok || !mounted) return;
      }
      final ok = await widget.app.setAllowance(
        centavos: cents,
        wallet: wallet!,
        days: days.toList(),
        startDate: start,
        enabled: enabled,
      );
      if (!mounted) return;
      if (ok) {
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
      final p = Palette.of(context), app = widget.app, s = app.ledger.allowance;
      return PocketPage(
        'Scheduled allowance',
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'A little routine.',
              style: textStyle(context, size: 27, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Record regular income when you open the app. This never reloads a wallet or moves money.',
              style: textStyle(context, size: 14, color: p.secondary),
            ),
            const SizedBox(height: 24),
            Text(
              'Amount per day',
              style: textStyle(context, size: 13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              key: const ValueKey('allowance-amount'),
              controller: amount,
              placeholder: '0.00',
              prefix: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  '₱',
                  style: textStyle(context, size: 24, color: p.secondary),
                ),
              ),
              maxLength: 12,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: textStyle(context, size: 24, tabular: true),
              placeholderStyle: textStyle(
                context,
                size: 24,
                color: p.secondary,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 16),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  GroupRow(
                    'Received in',
                    subtitle: wallet?.label ?? 'Choose a wallet',
                    icon: walletIcon(wallet?.icon ?? 'wallet'),
                    onTap: app.busy
                        ? null
                        : () async {
                            final chosen = await chooseWallet(
                              context,
                              app.ledger.availableWallets,
                              title: 'Allowance received in',
                            );
                            if (chosen != null && mounted) {
                              setState(() => wallet = chosen);
                            }
                          },
                  ),
                  GroupRow(
                    'Start date',
                    subtitle: shortDate(start),
                    icon: CupertinoIcons.calendar,
                    onTap: app.busy ? null : chooseStart,
                  ),
                  GroupRow(
                    'Enabled',
                    subtitle: enabled
                        ? 'Income will be recorded on app opening.'
                        : 'No income will be recorded.',
                    last: true,
                    trailing: PocketSwitch(
                      label: 'Enable scheduled allowance',
                      value: enabled,
                      onChanged: app.busy
                          ? null
                          : (v) => setState(() => enabled = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Eligible days',
              style: textStyle(context, weight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Press(
                  onPressed: () => setState(() => days = {1, 2, 3, 4, 5, 6, 7}),
                  color: p.surface,
                  child: const Text('Every day'),
                ),
                Press(
                  onPressed: () => setState(() => days = {1, 2, 3, 4, 5}),
                  color: p.surface,
                  child: const Text('Weekdays'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 1,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  Press(
                    key: ValueKey('allowance-day-$d'),
                    label:
                        '${weekdayNames[d - 1]}${days.contains(d) ? ', selected' : ''}',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    color: days.contains(d) ? p.tint : p.surface,
                    onPressed: app.busy
                        ? null
                        : () => setState(() {
                            if (days.contains(d)) {
                              days.remove(d);
                            } else {
                              days.add(d);
                            }
                          }),
                    child: Text(
                      weekdayNames[d - 1].substring(0, 1),
                      style: textStyle(
                        context,
                        size: 13,
                        color: p.accent,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (s?.enabled == true &&
                s!.nextOccurrence(dayKey(app.clock())) != null)
              Surface(
                child: Text(
                  'Next projected occurrence: ${shortDate(s.nextOccurrence(dayKey(app.clock()))!)} · ${money(s.centavos)}. This is not yet recorded or included in balances.',
                  style: textStyle(context, size: 14),
                ),
              ),
            const SizedBox(height: 16),
            Surface(
              padding: EdgeInsets.zero,
              child: GroupRow(
                'How this is recorded',
                icon: CupertinoIcons.info_circle,
                last: true,
                subtitle:
                    'On app opening · local dates · once per eligible day',
                onTap: () => showPocketSheet<void>(
                  context: context,
                  builder: (ctx) => SheetFrame(
                    title: 'Your allowance records',
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Text(
                        'Catch-up uses local dates, once per day, up to 31 days. Longer gaps pause for review. Paused days are skipped. Changes to an enabled rule apply tomorrow. Manual receipts are not matched: start tomorrow if today is already logged.',
                        style: textStyle(
                          ctx,
                          size: 16,
                          color: Palette.of(ctx).secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ErrorLine(error),
            PrimaryButton('Save schedule', onPressed: app.busy ? null : save),
          ],
        ),
      );
    },
  );
}
