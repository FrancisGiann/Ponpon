import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'data/native_bridge.dart';
import 'data/coordinated_store.dart';
import 'data/background_allowance.dart';
import 'domain/ledger.dart';
import 'ui/design.dart';
import 'ui/entry_page.dart';
import 'ui/screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

/// Short-lived data-only engine launched by Android JobScheduler.
@pragma('vm:entry-point')
Future<void> allowanceBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    final directory = await CoordinatedLedgerStore.privateDirectory();
    success = await processBackgroundAllowance(
      CoordinatedLedgerStore(directory),
    );
  } catch (_) {
    /* Foreground catch-up remains available. */
  }
  await const MethodChannel('dev.giann.pocket_entry/allowance_job')
      .invokeMethod<void>('complete', {'success': success});
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});
  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  final bridge = const NativeBridge();
  AppController? app;
  CoordinatedLedgerStore? store;
  String? error;
  Map<dynamic, dynamic>? initialEntry;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      store ??= CoordinatedLedgerStore(Directory(await bridge.privatePath()));
      final controller = AppController(store: store!, bridge: bridge);
      await controller.initialize();
      final entry = await bridge.initialEntry();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        app = controller;
        initialEntry = entry;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Your saved ledger could not be opened. Your files are preserved. Retry, or restore a Ponpon backup.';
          loading = false;
        });
      }
    }
  }

  Future<void> restore(BuildContext dialogContext) async {
    try {
      final chosen = await bridge.pickBackup();
      if (chosen == null || !mounted || !dialogContext.mounted) return;
      final imported = Ledger.decode(chosen);
      final ledger = imported.copy(
        preferences: imported.preferences.copy(balanceWidgetVisible: false),
        allowance: imported.allowance?.copy(enabled: false),
        bills: imported.bills.map((b) => b.copy(remind: false)).toList(),
      );
      final approved = await confirm(
        dialogContext,
        title: 'Restore saved records?',
        message:
            'This valid backup contains ${ledger.active.length} entries. Allowance schedules will stay paused for your review. Unreadable local files will be preserved privately.',
        action: 'Restore backup',
      );
      if (!approved) return;
      await store!.recover(ledger);
      await load();
    } on LedgerException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not restore that backup. Your files are preserved; try another file.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (app != null) {
      return PocketApp(controller: app!, initialEntry: initialEntry);
    }
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: Color(0xFF5B315D),
        scaffoldBackgroundColor: Color(0xFFF6F4F1),
      ),
      home: Builder(
        builder: (ctx) => CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: loading
                  ? const CupertinoActivityIndicator()
                  : QuietMessage(
                      'Let’s recover your records',
                      error ?? '',
                      icon: CupertinoIcons.tray,
                      action: Column(
                        children: [
                          PrimaryButton('Retry opening', onPressed: load),
                          const SizedBox(height: 12),
                          Press(
                            onPressed: () => restore(ctx),
                            child: const Text('Restore a backup'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    app?.dispose();
    super.dispose();
  }
}

class PocketApp extends StatefulWidget {
  const PocketApp({
    super.key,
    required this.controller,
    this.initialEntry,
    this.initialTab = 0,
    this.testHome,
  });
  final AppController controller;
  final Map<dynamic, dynamic>? initialEntry;
  final int initialTab;
  final Widget? testHome;
  @override
  State<PocketApp> createState() => _PocketAppState();
}

class _PocketAppState extends State<PocketApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  bool quickOpening = false;
  AppController get app => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (app.store is CoordinatedLedgerStore) {
      (app.store as CoordinatedLedgerStore).onChanged(app.refreshFromStorage);
    }
    if (app.bridge != null) {
      NativeBridge.channel.setMethodCallHandler((call) async {
        if (call.method == 'quickEntry' && call.arguments is Map) {
          await quickEntry(Map<dynamic, dynamic>.from(call.arguments as Map));
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialEntry != null) quickEntry(widget.initialEntry!);
    });
  }

  Future<void> quickEntry(Map<dynamic, dynamic> request) async {
    if (!mounted || navigator.currentState == null) return;
    if (request['bills'] == true) {
      if (app.entryVisible || quickOpening || app.busy) {
        app.feedback = 'Finish the current action before opening bills.';
        app.feedbackUndo = false;
        app.publish();
        return;
      }
      quickOpening = true;
      try {
        await pushPocket<void>(navigator.currentContext!, BillsPage(app: app));
      } finally {
        quickOpening = false;
      }
      return;
    }
    final id = request['categoryId'] is String
        ? request['categoryId'] as String
        : null;
    if (app.entryVisible || quickOpening || app.busy) {
      if (app.draft?.dirty == true) {
        app.feedback = 'An entry is in progress. Finish it first.';
        app.feedbackUndo = false;
        app.publish();
      } else if (app.draft != null &&
          app.ledger.category(id)?.archived == false) {
        app.draft!.categoryId = id;
        app.updateDraft();
        app.publish();
      }
      return;
    }
    app.startDraft(categoryId: id);
    quickOpening = true;
    final ctx = navigator.currentContext!;
    await navigator.currentState!.push<void>(
      PocketEntryRoute<void>(
        page: EntryPage(controller: app),
        reduced: MotionScope.of(ctx),
        settings: const RouteSettings(name: 'quick-entry'),
      ),
    );
    quickOpening = false;
    app.publish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      app.updateDraft();
    }
    if (state == AppLifecycleState.resumed) {
      app.reconcileOnResume().catchError((Object _) {
        app.storageError = 'Allowance could not be recorded. Reopen the app to retry; existing records are safe.';
        app.publish();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (app.store is CoordinatedLedgerStore) {
      (app.store as CoordinatedLedgerStore).onChanged(null);
    }
    if (app.bridge != null) NativeBridge.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final theme = app.ledger.preferences.effectiveTheme;
      final brightness = theme == 'dark'
          ? Brightness.dark
          : theme == 'light'
          ? Brightness.light
          : MediaQuery.platformBrightnessOf(context);
      final p = Palette(
        brightness == Brightness.dark,
        app.ledger.preferences.visualStyle,
      );
      return CupertinoApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        title: 'Ponpon',
        theme: CupertinoThemeData(
          brightness: brightness,
          primaryColor: p.accent,
          primaryContrastingColor: p.onAccent,
          scaffoldBackgroundColor: p.background,
          barBackgroundColor: p.surface,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              color: p.ink,
            ),
            navTitleTextStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
            actionTextStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              color: p.accent,
            ),
          ),
        ),
        builder: (context, child) {
          final reduced =
              app.ledger.preferences.reduceMotion ||
              MediaQuery.disableAnimationsOf(context);
          return VisualStyleScope(
            style: app.ledger.preferences.visualStyle,
            child: MotionScope(
              reduced: reduced,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: const Color(0x00000000),
                    systemNavigationBarColor: p.background,
                    statusBarIconBrightness: brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                    systemNavigationBarIconBrightness:
                        brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                  ),
                  child: Stack(
                    children: [
                      child!,
                      FeedbackBanner(app: app),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        home:
            widget.testHome ??
            (app.ledger.preferences.welcomed || widget.initialEntry != null
                ? HomeShell(app: app, initialTab: widget.initialTab)
                : WelcomePage(app: app)),
      );
    },
  );
}

class FeedbackBanner extends StatefulWidget {
  const FeedbackBanner({super.key, required this.app});
  final AppController app;
  @override
  State<FeedbackBanner> createState() => _FeedbackBannerState();
}

class _FeedbackBannerState extends State<FeedbackBanner> {
  Timer? timer;
  String? last;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(changed);
    changed();
  }

  void changed() {
    if (last == widget.app.feedback) return;
    last = widget.app.feedback;
    timer?.cancel();
    if (last != null) {
      timer = Timer(const Duration(seconds: 7), () {
        if (mounted) widget.app.clearFeedback();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.app.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.app.feedback == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 90,
      child: Semantics(
        liveRegion: true,
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(p.cardRadius),
            border: p.border,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: .12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: p.green,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.app.feedback!,
                  style: textStyle(context, size: 14),
                ),
              ),
              if (widget.app.feedbackUndo)
                Press(
                  onPressed: widget.app.busy
                      ? null
                      : () async {
                          if (widget.app.busy || !widget.app.feedbackUndo) {
                            return;
                          }
                          final success = await widget.app.undo();
                          if (success) widget.app.feedbackUndo = false;
                        },
                  child: Text(
                    'Undo',
                    style: textStyle(
                      context,
                      size: 14,
                      weight: FontWeight.w600,
                      color: p.accent,
                    ),
                  ),
                )
              else
                Press(
                  label: 'Dismiss feedback',
                  onPressed: widget.app.clearFeedback,
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    CupertinoIcons.xmark,
                    color: p.secondary,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
