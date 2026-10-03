import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';
import 'package:chameleonultragui/gui/component/watch_navigation.dart';
import 'package:chameleonultragui/helpers/watch.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
    );
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    notifyListeners();
  }

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator = null;
      progress = null;
    }
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    communicator = null;
    progress = null;
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;

  // Whether the round-watch navigation menu overlay is currently shown.
  bool _watchMenuOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
    // On a round watch, go fullscreen (hide system bars) for an immersive look.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && isRoundWatchScreen(context)) {
        try {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } catch (_) {}
      }
    });
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    final watchMode = isRoundWatchScreen(context);

    Widget page; // Set Page
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 7) {
      // If not connected, and not on home, tools, settings or dev page, go to home page
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const HomePage();
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case 1:
        page = const SlotManagerPage();
        break;
      case 2:
        page = const SavedCardsPage();
        break;
      case 3:
        page = const ReadCardPage();
        break;
      case 4:
        page = const WriteCardPage();
        break;
      case 5:
        page = const ToolsPage();
        break;
      case 6:
        page = const SettingsMainPage();
        break;
      case 7:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: watchMode
          ? _applyWatchTheme(ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: widget.sharedPreferencesProvider.getThemeColor()),
              brightness: Brightness.light,
              appBarTheme: AppBarTheme(
                  systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: ColorScheme.fromSeed(
                              seedColor:
                                  widget.sharedPreferencesProvider.getThemeColor(),
                              brightness: Brightness.light)
                          .surface,
                      statusBarBrightness: Brightness.light,
                      statusBarIconBrightness: Brightness.dark)),
            ).useCustomSystemFont(Brightness.light))
          : ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: widget.sharedPreferencesProvider.getThemeColor()),
              brightness: Brightness.light,
              appBarTheme: AppBarTheme(
                  systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: ColorScheme.fromSeed(
                              seedColor:
                                  widget.sharedPreferencesProvider.getThemeColor(),
                              brightness: Brightness.light)
                          .surface,
                      statusBarBrightness: Brightness.light,
                      statusBarIconBrightness: Brightness.dark)),
            ).useCustomSystemFont(Brightness.light),
      darkTheme: watchMode
          ? _applyWatchTheme(ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: widget.sharedPreferencesProvider.getThemeColor(),
                  brightness: Brightness.dark),
              brightness: Brightness.dark,
              appBarTheme: AppBarTheme(
                  systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: ColorScheme.fromSeed(
                              seedColor:
                                  widget.sharedPreferencesProvider.getThemeColor(),
                              brightness: Brightness.dark)
                          .surface,
                      statusBarBrightness: Brightness.dark,
                      statusBarIconBrightness: Brightness.light)),
            ).useCustomSystemFont(Brightness.dark))
          : ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: widget.sharedPreferencesProvider.getThemeColor(),
                  brightness: Brightness.dark),
              brightness: Brightness.dark,
              appBarTheme: AppBarTheme(
                  systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: ColorScheme.fromSeed(
                              seedColor:
                                  widget.sharedPreferencesProvider.getThemeColor(),
                              brightness: Brightness.dark)
                          .surface,
                      statusBarBrightness: Brightness.dark,
                      statusBarIconBrightness: Brightness.light)),
            ).useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: Builder(
        builder: (context) {
          if (!isRoundWatchScreen(context)) {
            return LayoutBuilder(
              builder: (context, constraints) => _buildMainScaffold(
                  context, appState, page, watchMode: false),
            );
          }

          // Round watch: lay the existing phone UI out at the reference design
          // size, then scale the rendered result back down and clip it to the
          // round display so nothing spills into the bezel.
          final real = MediaQuery.of(context).size;
          final scale = watchScaleFactor(real);
          final design = Size(real.width * scale, real.height * scale);
          return ClipOval(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: design),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: design.width,
                    height: design.height,
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildMainScaffold(
                          context, appState, page, watchMode: true),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the main Scaffold shell.
  ///
  /// On regular screens the left `NavigationRail` sidebar is shown as before.
  /// On a round watch the sidebar is replaced by a bottom-centre circular menu
  /// button plus a full-screen round navigation menu.
  Widget _buildMainScaffold(
    BuildContext context,
    ChameleonGUIState appState,
    Widget page, {
    required bool watchMode,
  }) {
    if (!watchMode) {
      return SafeArea(
        left: false,
        right: false,
        top: false,
        bottom: true,
        child: Scaffold(
            body: Row(
              children: [
                (!appState.connector!.isDFU || !appState.connector!.connected)
                    ? SafeArea(
                        child: NavigationRail(
                          key: appState.navigationRailKey,
                          // Sidebar
                          extended: appState.sharedPreferencesProvider
                              .getSideBarExpanded(),
                          destinations: [
                            // Sidebar Items
                            NavigationRailDestination(
                              icon: const Icon(Icons.home),
                              label: Text(
                                  AppLocalizations.of(context)!.home), // Home
                            ),
                            NavigationRailDestination(
                              disabled: !appState.connector!.connected,
                              icon: const Icon(Icons.widgets),
                              label: Text(
                                  AppLocalizations.of(context)!.slot_manager),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.auto_awesome_motion),
                              label: Text(
                                  AppLocalizations.of(context)!.saved_cards),
                            ),
                            NavigationRailDestination(
                              disabled: !appState.connector!.connected,
                              icon: const Icon(Icons.sensors),
                              label: Text(
                                  AppLocalizations.of(context)!.read_card),
                            ),
                            NavigationRailDestination(
                              disabled: !appState.connector!.connected,
                              icon: const Icon(Icons.system_update_alt),
                              label: Text(
                                  AppLocalizations.of(context)!.write_card),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.handyman),
                              label:
                                  Text(AppLocalizations.of(context)!.tools),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.settings),
                              label: Text(
                                  AppLocalizations.of(context)!.settings),
                            ),
                            if (appState.devMode)
                              NavigationRailDestination(
                                icon: const Icon(Icons.bug_report),
                                label: Text(
                                    '🐞 ${AppLocalizations.of(context)!.debug} 🐞'),
                              ),
                          ],
                          selectedIndex: selectedIndex,
                          onDestinationSelected: (value) {
                            setState(() {
                              selectedIndex = value;
                            });
                          },
                        ),
                      )
                    : const SizedBox(),
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: page,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: const BottomProgressBar()),
      );
    }

    // Round-watch shell: full-screen page + circular menu button + menu overlay.
    return SafeArea(
      left: false,
      right: false,
      top: false,
      bottom: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: page,
              ),
            ),
            if (_watchMenuOpen)
              Positioned.fill(
                child: WatchNavigationMenu(
                  selectedIndex: selectedIndex,
                  connected: appState.connector!.connected,
                  devMode: appState.devMode,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                      _watchMenuOpen = false;
                    });
                  },
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WatchMenuButton(
                  menuOpen: _watchMenuOpen,
                  onPressed: () =>
                      setState(() => _watchMenuOpen = !_watchMenuOpen),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const BottomProgressBar(),
      ),
    );
  }

  /// Applies watch-friendly tweaks to the theme: a more compact app bar and
  /// round dialog corners so overlays look native on the round display.
  ThemeData _applyWatchTheme(ThemeData theme) {
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        toolbarHeight: 44,
        centerTitle: true,
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(36),
        ),
      ),
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}
