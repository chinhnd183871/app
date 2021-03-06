import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:flutter/cupertino.dart';
import 'package:who_app/api/user_preferences.dart';
import 'package:who_app/components/themed_text.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:package_info/package_info.dart';
import 'package:who_app/api/notifications.dart';
import 'package:who_app/pages/main_pages/routes.dart';
import 'package:who_app/constants.dart';
import 'package:who_app/generated/l10n.dart';

import 'package:who_app/api/content/content_loading.dart';

PackageInfo _packageInfo;

PackageInfo get packageInfo => _packageInfo;

void main() async {
  await mainImpl(routes: Routes.map);
}

void mainImpl({@required Map<String, WidgetBuilder> routes}) async {
  // Asyncronous code that runs before the splash screen is hidden goes before
  // runApp()
  if (!kIsWeb) {
    // Initialises binding so we can use the framework before calling runApp
    WidgetsFlutterBinding.ensureInitialized();
    _packageInfo = await PackageInfo.fromPlatform();
  }

  final bool onboardingComplete =
      await UserPreferences().getOnboardingCompleted();

  // Comment the above lines out and uncomment this to force onboarding in development
  // final bool onboardingComplete = false;

  // Set `enableInDevMode` to true to see reports while in debug mode
  // This is only to be used for confirming that reports are being
  // submitted as expected. It is not intended to be used for everyday
  // development.
  // Crashlytics.instance.enableInDevMode = true;

  FlutterError.onError = _onFlutterError;

  await runZonedGuarded<Future<void>>(
    () async {
      runApp(MyApp(showOnboarding: !onboardingComplete, routes: routes));
    },
    _onError,
  );
}

Future<void> _onFlutterError(FlutterErrorDetails details) async {
  if (await UserPreferences().getOnboardingCompleted()) {
    // Pass all uncaught errors from the framework to Crashlytics.
    await Crashlytics.instance.recordFlutterError(details);
  }
}

Future<void> _onError(Object error, StackTrace stack) async {
  if (await UserPreferences().getOnboardingCompleted()) {
    await Crashlytics.instance.recordError(error, stack);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key key, @required this.showOnboarding, @required this.routes})
      : super(key: key);
  final bool showOnboarding;
  final Map<String, WidgetBuilder> routes;

  static FirebaseAnalytics analytics = FirebaseAnalytics();
  static FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: analytics);

  @override
  _MyAppState createState() => _MyAppState(analytics, observer);
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final Notifications _notifications = Notifications();

  _MyAppState(this.analytics, this.observer);

  final FirebaseAnalytics analytics;
  final FirebaseAnalyticsObserver observer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _notifications.configure();
    _notifications.updateFirebaseToken();
    _precacheContent();
  }

  // TODO: Issue #902 This is not essential for basic operation but we should implement
  // Fires if notification settings change.
  // Modify user opt-in if they do.
  // _firebaseMessaging.onIosSettingsRegistered
  //     .listen((IosNotificationSettings settings) {
  // });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: GlobalWidgetsLocalizations(
        getLocale(),
      ).textDirection,
      child: MaterialApp(
        title: "WHO COVID-19",
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          S.delegate
        ],
        routes: widget.routes,
        // FIXME Issue #1012 - disabled supported languages for P0
        //supportedLocales: S.delegate.supportedLocales,
        initialRoute: widget.showOnboarding ? '/onboarding' : '/home',

        /// allows routing to work without a [Navigator.defaultRouteName] route
        builder: (context, child) => child,
        navigatorObservers: <NavigatorObserver>[observer],
        theme: ThemeData(
          brightness: Brightness.light,
          primaryColor: Constants.primaryDarkColor,
          textTheme: TextTheme(),
          cupertinoOverrideTheme: CupertinoThemeData(
            brightness: Brightness.light,
            primaryColor: Constants.primaryDarkColor,
            textTheme: CupertinoTextThemeData(
              textStyle: ThemedText.styleForVariant(TypographyVariant.body),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        _precacheContent();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Pre-cache commonly loaded content.
  /// Called on on app lauch and return to foreground.
  void _precacheContent() async {
    if (await UserPreferences().getTermsOfServiceCompleted()) {
      // ignore: unawaited_futures
      ContentLoading().preCacheContent(getLocale());
    }
  }

  /// Construct the Locale from the Intl locale string.
  /// This allows us to get the Locale outside of the main build context.
  Locale getLocale() {
    var parts = Intl.getCurrentLocale().split('_');
    return Locale(parts[0], parts[1]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
