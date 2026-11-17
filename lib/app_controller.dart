import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';

import 'data/native_bridge.dart';
import 'data/storage.dart';
import 'data/coordinated_store.dart';
import 'domain/adventure.dart';
import 'domain/ledger.dart';
import 'domain/transfer_preview.dart';

part 'app_features.dart';

class AppController extends ChangeNotifier {
  AppController({required this.store, this.bridge, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final LedgerStore store;
  final NativeBridge? bridge;
  final DateTime Function() clock;
  Ledger ledger = Ledger.empty();
  Draft? draft;
  bool busy = false;
  bool _refreshPending = false;
  String? notice;
  String? storageError;
  String? draftError;
  Future<void> _draftQueue = Future.value();
  String? _pendingDraft;
  bool _writingDraft = false;
  String? _feedback;
  int _feedbackSequence = 0;
  String? get feedback => _feedback;
  int get feedbackId => _feedbackSequence;
  set feedback(String? value) {
    _feedback = value;
    _feedbackSequence++;
  }

  bool feedbackUndo = false;
  bool entryVisible = false;
  bool repeatOpening = false;
  String? celebratedLoanId;
  AdventureRewardEvent? adventureReward;
  int _adventureRewardSequence = 0;
  void publish() => notifyListeners();

  void showAdventureReward(AdventureRewardKind kind, {AdventureBadge? badge}) {
    if (ledger.preferences.visualStyle != VisualStyle.adventure) return;
    adventureReward = AdventureRewardEvent(
      id: ++_adventureRewardSequence,
      kind: kind,
      badge: badge,
    );
    notifyListeners();
  }

  void clearAdventureReward(int id) {
    if (adventureReward?.id == id) {
      adventureReward = null;
      notifyListeners();
    }
  }

  Future<void> _hapticIfEnabled() async {
    if (!ledger.preferences.haptics) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // A committed ledger action must not fail when the platform has no haptics.
    }
  }

  Future<void> initialize() async {
    final result = await store.load();
    ledger = result.ledger;
    notice = result.notice;
    try {
      draft = await store.loadDraft();
      final saved = draft == null ? null : ledger.entry(draft!.id);
      if (saved != null && !saved.deleted && _draftMatches(saved, draft!)) {
        draft = null;
        await store.clearDraft();
      } else if (draft?.editingId != null && (saved == null || saved.deleted)) {
        draft = null;
        await store.clearDraft();
        notice = 'An unfinished edit is no longer available. Review History.';
      }
    } on LedgerException catch (e) {
      notice = e.message;
    }
    _normalizeRepeatDraftReferences();
    if (draft?.kind == EntryKind.income &&
        draft?.editingId == null &&
        draft?.repeatEntry != true &&
        !ledger
            .categoriesFor(EntryKind.income)
            .any((c) => c.id == draft!.categoryId)) {
      draft!.categoryId = ledger
          .categoriesFor(EntryKind.income)
          .firstOrNull
          ?.id;
      updateDraft();
    }
    await recordAllowances();
    await _sync();
    notifyListeners();
  }

  bool _draftMatches(Entry e, Draft d) {
    try {
      return e.centavos == parseMoney(d.amount) &&
          e.kind == d.kind &&
          e.date == d.date &&
          e.note == d.note &&
          e.categoryId ==
              (d.kind == EntryKind.transfer ? null : d.categoryId) &&
          (d.kind != EntryKind.transfer ||
              e.wallet == d.from && e.toWallet == d.to);
    } catch (_) {
      return false;
    }
  }

  Future<void> _sync() async {
    try {
      await bridge?.sync(
        ledger,
        revision: store is CoordinatedLedgerStore
            ? (store as CoordinatedLedgerStore).revision
            : null,
      );
    } catch (_) {
      notice ??= 'Your records are saved. Widgets or reminders could not refresh; reopen the app to retry.';
    }
  }

  Future<void> refreshFromStorage() async {
    if (store is! CoordinatedLedgerStore) return;
    if (busy) {
      _refreshPending = true;
      return;
    }
    busy = true;
    _refreshPending = false;
    notifyListeners();
    try {
      final loaded = await store.load();
      if (loaded.ledger.encode() != ledger.encode()) {
        feedback = null;
        feedbackUndo = false;
        adventureReward = null;
      }
      ledger = loaded.ledger;
      _normalizeRepeatDraftReferences();
      notice ??= loaded.notice;
      await _sync();
    } catch (_) {
      storageError = 'Updated records could not be opened. Your unfinished entry is kept; reopen the app to retry.';
    } finally {
      busy = false;
      notifyListeners();
      _drainRefresh();
    }
  }

  void _drainRefresh() {
    if (_refreshPending && !busy) {
      _refreshPending = false;
      refreshFromStorage();
    }
  }

  Future<void> reconcileOnResume() async {
    await refreshFromStorage();
    await recordAllowances();
    await _sync();
  }

  Future<void> _conflict() async {
    feedback = null;
    feedbackUndo = false;
    try {
      ledger = (await store.load()).ledger;
      adventureReward = null;
      _normalizeRepeatDraftReferences();
      await _sync();
    } catch (_) {
      /* A failed read never authorizes replacing unreadable files. */
    }
    storageError = 'Records changed in the background. Review and try again. Your unfinished entry is kept.';
  }

  void startDraft({String? categoryId, Entry? editing}) {
    if (draft != null && draft!.dirty && editing == null) return;
    final requestedCategory = categoryId == null
        ? null
        : [
            ...ledger.categoriesFor(EntryKind.expense),
            ...ledger.categoriesFor(EntryKind.income),
          ].where((c) => c.id == categoryId).firstOrNull;
    draft = editing == null
        ? Draft(
            kind: requestedCategory?.isIncome == true
                ? EntryKind.income
                : EntryKind.expense,
            categoryId: requestedCategory != null ? categoryId : null,
            date: dayKey(clock()),
          )
        : Draft.fromEntry(editing);
    if (categoryId != null && draft!.categoryId == null) {
      notice = 'That category changed. Choose an available category.';
    }
    updateDraft();
  }

  Entry? repeatableEntry(String sourceId) {
    final source = ledger.entry(sourceId);
    if (source == null ||
        source.deleted ||
        source.adjustment != null ||
        source.kind == EntryKind.transfer) {
      return null;
    }
    return source;
  }

  bool startRepeatDraft(String sourceId) {
    if (busy || draft?.dirty == true) return false;
    final source = repeatableEntry(sourceId);
    if (source == null) return false;
    final category = _repeatCategory(
      source.kind,
      source.categoryId,
      requireStored: true,
    );
    final wallet = ledger.availableWallets
        .where((candidate) => candidate == source.wallet)
        .firstOrNull;
    draft = Draft(
      amount: moneyInput(source.centavos),
      kind: source.kind,
      date: dayKey(clock().toLocal()),
      categoryId: category?.id,
      note: source.note,
      repeatEntry: true,
      repeatCategoryExplicit: false,
      preferredWallet: wallet,
    );
    updateDraft();
    notifyListeners();
    return true;
  }

  Category? _repeatCategory(
    EntryKind kind,
    String? categoryId, {
    bool requireStored = false,
  }) {
    if (kind == EntryKind.transfer || categoryId == null) return null;
    final stored = ledger.category(categoryId);
    if ((requireStored && stored == null) ||
        (stored != null &&
            (stored.archived ||
                stored.isIncome != (kind == EntryKind.income)))) {
      return null;
    }
    return ledger
        .categoriesFor(kind)
        .where((candidate) => candidate.id == categoryId)
        .firstOrNull;
  }

  void _normalizeRepeatDraftReferences() {
    final current = draft;
    if (current == null || !current.repeatEntry) return;
    final categoryId = _repeatCategory(
      current.kind,
      current.categoryId,
      requireStored: !current.repeatCategoryExplicit,
    )?.id;
    final wallet = ledger.availableWallets
        .where((candidate) => candidate == current.preferredWallet)
        .firstOrNull;
    if (current.categoryId != categoryId || current.preferredWallet != wallet) {
      current.categoryId = categoryId;
      current.preferredWallet = wallet;
      updateDraft();
    }
  }

  void changeDraftKind(EntryKind kind) {
    if (draft == null || draft!.kind == kind) return;
    draft!.kind = kind;
    if (draft!.repeatEntry) {
      draft!.categoryId = _repeatCategory(
        kind,
        draft!.categoryId,
        requireStored: !draft!.repeatCategoryExplicit,
      )?.id;
      if (draft!.categoryId == null) draft!.repeatCategoryExplicit = false;
    } else {
      draft!.categoryId = kind == EntryKind.income
          ? ledger.categoriesFor(kind).firstOrNull?.id
          : null;
    }
  }

  void updateDraft() {
    if (draft == null) return;
    _pendingDraft = jsonEncode(draft!.toJson());
    if (_writingDraft) return;
    _writingDraft = true;
    _draftQueue = _flushDrafts();
  }

  Future<void> _flushDrafts() async {
    // Write promptly, then keep only the newest pending snapshot while the disk
    // is busy. There is no timer window and save/discard still await the drain.
    while (_pendingDraft != null) {
      final snapshot = _pendingDraft!;
      _pendingDraft = null;
      try {
        await store.saveDraft(snapshot);
        draftError = null;
      } catch (_) {
        draftError = 'The unfinished entry could not be stored. Keep this screen open and try saving again.';
        notifyListeners();
      }
    }
    _writingDraft = false;
  }

  Future<void> discardDraft() async {
    await _draftQueue;
    await store.clearDraft();
    draft = null;
    notifyListeners();
  }

  Future<bool> commit(
    Ledger Function(Ledger) change, {
    String? message,
    bool undo = false,
  }) async {
    if (busy) return false;
    busy = true;
    storageError = null;
    notifyListeners();
    try {
      final next = change(ledger);
      await store.save(next);
      ledger = next;
      if (message != null) {
        feedback = message;
        feedbackUndo = undo;
      }
      await _sync();
      return true;
    } on LedgerChangedException {
      await _conflict();
      return false;
    } on LedgerException catch (e) {
      storageError = e.message;
      return false;
    } catch (_) {
      storageError = 'Could not save to this device. Your previous data is safe. Free some space and try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
      _drainRefresh();
    }
  }

  Future<bool> saveDraft(Wallet wallet) async {
    if (busy || draft == null) return false;
    _normalizeRepeatDraftReferences();
    final current = draft!;
    Entry next;
    Category? selected;
    try {
      if (current.repeatEntry &&
          (current.editingId != null || ledger.entry(current.id) != null)) {
        throw const LedgerException(
          'Repeating an entry must create a new record. Start a fresh repeat.',
        );
      }
      final cents = parseMoney(current.amount);
      if (current.repeatEntry && current.kind != EntryKind.transfer) {
        final selectedWallet = ledger.wallet(current.preferredWallet);
        if (selectedWallet?.archived != false || selectedWallet != wallet) {
          throw const LedgerException(
            'Choose an active wallet for this repeated entry.',
          );
        }
      }
      final before = current.editingId == null
          ? null
          : ledger.entry(current.editingId!);
      if (before?.adjustment != null) {
        throw const LedgerException(
          'Use a new balance check to change an adjustment.',
        );
      }
      selected = ledger
          .categoriesFor(current.kind)
          .where((c) => c.id == current.categoryId)
          .firstOrNull;
      // A legacy record with a cross-type category can be edited without
      // silently recategorizing its history. A type/category change must match.
      final retained =
          before != null &&
          before.kind == current.kind &&
          before.categoryId == current.categoryId;
      if (current.kind != EntryKind.transfer && selected == null && !retained) {
        throw const LedgerException('Choose a category before saving.');
      }
      final now = clock().millisecondsSinceEpoch;
      next = Entry(
        id: current.id,
        kind: current.kind,
        centavos: cents,
        date: current.date,
        wallet: current.kind == EntryKind.transfer ? current.from : wallet,
        toWallet: current.kind == EntryKind.transfer ? current.to : null,
        categoryId: current.kind == EntryKind.transfer
            ? null
            : current.categoryId,
        note: current.note.trim(),
        createdAt: before?.createdAt ?? now,
        updatedAt: max(now, before?.updatedAt ?? 0),
        scheduleId: before?.scheduleId,
        occurrenceDate: before?.occurrenceDate,
        billId: before?.billId,
        billDueDate: before?.billDueDate,
      );
    } on LedgerException catch (e) {
      storageError = e.message;
      notifyListeners();
      return false;
    }
    // commit marks busy synchronously, so a second tap cannot reach another write.
    final unlocksFirstEntry =
        current.editingId == null &&
        next.adjustment == null &&
        next.billId == null &&
        next.loanId == null &&
        !AdventureBadges.has(ledger, AdventureBadge.firstEntry);
    final result = await commit(
      (l) {
        var prepared = l;
        if (selected != null && l.category(selected.id) == null) {
          if (l.categories.length >= 100) {
            throw const LedgerException(
              'Keep up to 100 categories. Use an existing category before adding another.',
            );
          }
          prepared = l.copy(categories: [...l.categories, selected]);
        }
        if (current.kind == EntryKind.transfer) {
          final preview = previewTransfer(
            l,
            source: current.from,
            destination: current.to,
            amount: current.amount,
            editingId: current.editingId,
          );
          if (preview.error != null) {
            throw LedgerException(preview.error!);
          }
        }
        return prepared
            .put(next, editing: current.editingId != null)
            .copy(preferences: l.preferences.copy(welcomed: true));
      },
      message: current.editingId != null
          ? 'Entry updated'
          : current.kind == EntryKind.transfer
          ? '${money(next.centavos)} transfer recorded'
          : '${money(next.centavos)} ${entryAction(current.kind).toLowerCase()} ${ledger.wallet(wallet)?.label ?? wallet.label}',
      undo: true,
    );
    if (result) {
      draft = null;
      await _draftQueue;
      try {
        await store.clearDraft();
      } catch (_) {
        /* The committed ID prevents a replay after restart. */
      }
      showAdventureReward(
        AdventureRewardKind.saved,
        badge: unlocksFirstEntry ? AdventureBadge.firstEntry : null,
      );
      await _hapticIfEnabled();
      notifyListeners();
    }
    return result;
  }

  Future<bool> undo() async {
    final result = await commit(
      (l) => l.undo(clock().millisecondsSinceEpoch),
      message: 'Change undone',
    );
    if (result) {
      celebratedLoanId = null;
      adventureReward = null;
      publish();
    }
    return result;
  }

  void clearLoanCelebration(String id) {
    if (celebratedLoanId == id) {
      celebratedLoanId = null;
      notifyListeners();
    }
  }

  Future<bool> delete(Entry e) => commit(
    (l) => l.delete(e.id, clock().millisecondsSinceEpoch),
    message: 'Entry moved to Recently deleted',
    undo: true,
  );
  Future<bool> restoreDeleted(Entry e) => commit(
    (l) => l.restoreDeleted(e.id, clock().millisecondsSinceEpoch),
    message: 'Entry restored',
    undo: true,
  );
  Future<bool> preferences(Preferences value) async {
    final previousStyle = ledger.preferences.visualStyle;
    final result = await commit((l) {
      final needsSchool =
          value.widgetCategories.contains(schoolSuppliesCategory.id) &&
          l.category(schoolSuppliesCategory.id) == null;
      if (needsSchool && l.categories.length >= 100) {
        throw const LedgerException(
          'Keep up to 100 categories. Use an existing category before adding another.',
        );
      }
      return l.copy(
        categories: [...l.categories, if (needsSchool) schoolSuppliesCategory],
        preferences: value,
      );
    });
    if (result && previousStyle != value.visualStyle) {
      final event = adventureReward;
      if (event != null) clearAdventureReward(event.id);
    }
    return result;
  }

  Future<bool> setBudget(String month, int cents) => commit(
    (l) => l.copy(budgets: {...l.budgets, month: cents}),
    message: 'Monthly budget updated',
  );
  Future<bool> setOpening(Wallet wallet, int cents) => commit(
    (l) => l.copy(openings: {...l.openings, wallet: cents}),
    message: 'Opening balance updated',
  );

  Future<bool> setWallet(Wallet value) => commit((l) {
    Wallet.fromJson(value.toJson());
    if (value.archived &&
        l.allowance?.enabled == true &&
        l.allowance!.wallet == value) {
      throw const LedgerException(
        'Move or disable the allowance schedule before archiving this wallet.',
      );
    }
    final wallets = [
      for (final w in l.wallets)
        if (w == value) value else w,
      if (l.wallet(value) == null) value,
    ];
    if (wallets.map((w) => w.label.toLowerCase()).toSet().length !=
        wallets.length) {
      throw const LedgerException(
        'Use a distinct wallet name so every choice is clear.',
      );
    }
    if (wallets.length > 20) {
      throw const LedgerException(
        'Keep up to twenty wallets, including archived and removed wallets.',
      );
    }
    final pins = l.preferences.quickWallets
        .where((id) => wallets.any((w) => w.id == id && !w.archived))
        .toList();
    return l.copy(
      wallets: wallets,
      openings: {...l.openings, if (l.wallet(value) == null) value: 0},
      preferences: l.preferences.copy(quickWallets: pins),
    );
  }, message: 'Wallet updated');

  Future<bool> removeWallet(
    Wallet wallet, {
    bool pauseAllowance = false,
  }) => commit((l) {
    final current = l.wallet(wallet);
    if (current == null || current.archived) {
      throw const LedgerException(
        'This wallet is already hidden. Restore it from Hidden wallets.',
      );
    }
    final usesAllowance = l.allowance?.wallet == wallet && l.allowance!.enabled;
    if (usesAllowance && !pauseAllowance) {
      throw const LedgerException(
        'Choose whether to pause this wallet’s allowance before removing it.',
      );
    }
    return l.copy(
      wallets: [
        for (final w in l.wallets)
          w == wallet
              ? w.copy(archived: true, removed: !l.hasWalletHistory(w))
              : w,
      ],
      preferences: l.preferences.copy(
        quickWallets: l.preferences.quickWallets
            .where((id) => id != wallet.id)
            .toList(),
      ),
      allowance: usesAllowance
          ? l.allowance!.copy(enabled: false)
          : l.allowance,
    );
  }, message: 'Wallet hidden · restore in Hidden wallets');

  Future<bool> restoreWallet(Wallet wallet) {
    final current = ledger.wallet(wallet);
    if (current == null) return Future.value(false);
    return setWallet(current.copy(archived: false, removed: false));
  }

  Future<bool> setQuickWallets(List<String> selected) {
    // Copy the caller's list before the asynchronous commit. Only appearance
    // preferences change; choosing buttons never records a financial entry.
    final ids = List<String>.unmodifiable(selected);
    return commit((l) {
      if (ids.length > 20 ||
          ids.toSet().length != ids.length ||
          ids.any((id) => !l.availableWallets.any((w) => w.id == id))) {
        throw const LedgerException('Choose each active wallet at most once.');
      }
      return l.copy(preferences: l.preferences.copy(quickWallets: ids));
    });
  }

  Future<bool> recordAllowances() async {
    if (busy) return false;
    AllowanceCatchUp result;
    try {
      result = catchUpAllowance(ledger, clock());
    } on LedgerException catch (e) {
      storageError = e.message;
      notice = 'Allowance was not recorded: ${e.message}';
      notifyListeners();
      return false;
    }
    if (identical(result.ledger, ledger)) return true;
    final saved = await commit(
      (_) => result.ledger,
      message: result.count > 0
          ? '${result.count} allowance ${result.count == 1 ? 'entry' : 'entries'} recorded'
          : null,
      undo: result.count > 0,
    );
    if (saved && result.paused) notice = 'Allowance paused after a gap over 31 days. Review its start date; historical receipts were not assumed.';
    if (!saved) notice = 'Allowance could not be recorded. Reopen the app to retry; existing records are unchanged.';
    return saved;
  }

  Future<bool> setAllowance({
    required int centavos,
    required Wallet wallet,
    required List<int> days,
    required String startDate,
    required bool enabled,
  }) => commit((l) {
    final today = dayKey(clock());
    if (startDate.compareTo(today) < 0) {
      throw const LedgerException(
        'Start today or later. Add older receipts manually.',
      );
    }
    if (l.wallet(wallet)?.archived != false) {
      throw const LedgerException('Choose an active wallet.');
    }
    final old = l.allowance;
    // Settle an enabled old rule first. Its replacement takes effect tomorrow.
    final settled = old?.enabled == true
        ? catchUpAllowance(l, clock()).ledger
        : l;
    final candidateCursor = old?.enabled == true ? today : previousDay(today);
    final cursor = [
      candidateCursor,
      if (old != null) old.processedThrough,
      if (settled.allowance != null) settled.allowance!.processedThrough,
    ].reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final rule = AllowanceSchedule(
      id: old?.id ?? newId(),
      centavos: centavos,
      wallet: wallet,
      days: days,
      startDate: startDate,
      enabled: enabled,
      processedThrough: cursor,
    );
    AllowanceSchedule.fromJson(rule.toJson());
    return catchUpAllowance(settled.copy(allowance: rule), clock()).ledger;
  }, message: 'Allowance schedule saved');
  Future<bool> category(Category value) => commit((l) {
    final categories = [
      for (final c in l.categories)
        if (c.id == value.id) value else c,
      if (l.category(value.id) == null) value,
    ];
    if (!categories.any((c) => !c.archived)) {
      throw const LedgerException('Keep at least one available category.');
    }
    if (categories.length > 100) {
      throw const LedgerException('You can keep up to 100 categories.');
    }
    final ids = l.preferences.widgetCategories
        .where((id) => categories.any((c) => c.id == id && !c.archived))
        .toList();
    return l.copy(
      categories: categories,
      preferences: l.preferences.copy(widgetCategories: ids),
    );
  }, message: 'Category updated');
  Future<bool> restore(RestorePreview preview) async {
    if (busy) return false;
    if (ledger.encode() != preview.base) {
      storageError = 'Your ledger changed after the preview. Choose the backup again to review a fresh restore.';
      notifyListeners();
      return false;
    }
    busy = true;
    storageError = null;
    notifyListeners();
    try {
      await store.saveRestoreRecovery(ledger);
      await store.save(preview.ledger);
      ledger = preview.ledger;
      adventureReward = null;
      feedback =
          '${preview.added} entries restored · ${preview.skipped} already present';
      feedbackUndo = false;
      await _sync();
      return true;
    } on LedgerChangedException {
      await _conflict();
      return false;
    } catch (_) {
      storageError = 'Restore could not be saved. Your current data is unchanged; try again after freeing space.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
      _drainRefresh();
    }
  }

  Future<bool> recoverBeforeRestore() async {
    try {
      final recovery = await store.loadRestoreRecovery();
      if (recovery == null) {
        storageError = 'No restore recovery copy is available yet.';
        notifyListeners();
        return false;
      }
      return await commit((_) => recovery, message: 'Earlier ledger recovered');
    } catch (_) {
      storageError = 'The local recovery copy could not be opened. Try your exported backup.';
      notifyListeners();
      return false;
    }
  }

  void clearFeedback([int? expectedId]) {
    if (expectedId != null && expectedId != _feedbackSequence) return;
    if (_feedback == null && !feedbackUndo) return;
    _feedback = null;
    _feedbackSequence++;
    feedbackUndo = false;
    notifyListeners();
  }
}
