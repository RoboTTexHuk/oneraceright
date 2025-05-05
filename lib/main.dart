import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart' show AppTrackingTransparency, TrackingStatus;
import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tzd;
import 'package:timezone/timezone.dart' as tzu;
import 'package:http/http.dart' as http;

import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;
import 'package:url_launcher/url_launcher_string.dart';
final FILT = [
  ".*.doubleclick.net/.*",
  ".*.ads.pubmatic.com/.*",
  ".*.googlesyndication.com/.*",
  ".*.google-analytics.com/.*",
  ".*.adservice.google.*/.*",
  ".*.adbrite.com/.*",
  ".*.exponential.com/.*",
  ".*.quantserve.com/.*",
  ".*.scorecardresearch.com/.*",
  ".*.zedo.com/.*",
  ".*.adsafeprotected.com/.*",
  ".*.teads.tv/.*",
  ".*.outbrain.com/.*",
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_msgBgHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tzd.initializeTimeZones();

  runApp(MaterialApp(home: TokenInitPage()));
}

// FCM Background Handler
@pragma('vm:entry-point')
Future<void> _msgBgHandler(RemoteMessage msg) async {
  print("BG Message: ${msg.messageId}");
  print("BG Data: ${msg.data}");
  // Можно вызвать обработку/передачу данных тут при необходимости
}

class TokenInitPage extends StatefulWidget {
  const TokenInitPage({super.key});
  @override
  State<TokenInitPage> createState() => _TokenInitPageState();
}

class _TokenInitPageState extends State<TokenInitPage> {
  String? _token;
  bool _perm = false;

  @override
  void initState() {
    super.initState();

    TokenChannel.listen((token) {
      setState(() => _token = token);
      print('FCM Token updated: $token');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => UniWebPage(token)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class TokenChannel {
  static const MethodChannel _c = MethodChannel('com.example.fcm/token');
  static void listen(Function(String token) onToken) {
    _c.setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String token = call.arguments as String;
        onToken(token);
      }
    });
  }
}

class UniWebPage extends StatefulWidget {
  final String? t;
  const UniWebPage(this.t, {super.key});
  @override
  State<UniWebPage> createState() => _UniWebPageState();
}

class _UniWebPageState extends State<UniWebPage> {
  late InAppWebViewController _c;
  String? _t;
  String? _fcm;
  String? _dev;
  String? _iid;
  String? _plf;
  String? _os;
  String? _ver;
  String? _lang;
  String? _tz;
  bool _push = true;
  bool _loading = false;
  var contentBlockerEnabled = true;
  final List<ContentBlocker> contentBlockers = [];
  String _url = "https://api.oneontherace.autos/";

  @override
  void initState() {
    super.initState();

    for (final adUrlFilter in FILT) {
      contentBlockers.add(ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: adUrlFilter,
          ),
          action: ContentBlockerAction(
            type: ContentBlockerActionType.BLOCK,
          )));
    }

    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        //   ContentBlockerTriggerResourceType.IMAGE,

        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK, selector: ".notification"),
    ));

    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        //   ContentBlockerTriggerResourceType.IMAGE,

        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info"),
    ));
    // apply the "display: none" style to some HTML elements
    contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".*",
        ),
        action: ContentBlockerAction(
            type: ContentBlockerActionType.CSS_DISPLAY_NONE,
            selector: ".banner, .banners, .ads, .ad, .advert")));



    FirebaseMessaging.onBackgroundMessage(_msgBgHandler);
    _initATT();
    _initAppsFlyer();
    _setupChannels();
    _initData();
    _initFCM();

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _loadUrl(msg.data['uri'].toString());
      } else {
        _resetUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _loadUrl(msg.data['uri'].toString());
      } else {
        _resetUrl();
      }
    });
    new Future.delayed(const Duration(seconds: 2), () {
      _initATT();
    });
    Future.delayed(const Duration(seconds: 6), () {
      _sendDataToWeb();

      sendDataRaw();
    });
  }

  void _setupChannels() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> data = Map<String, dynamic>.from(call.arguments);
        if (data["uri"] != null && !data["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => PushWebView(url: data["uri"])),
                (route) => false,
          );
        }
      }
    });
  }

  void _loadUrl(String uri) async {
    if (_c != null) {
      await _c.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri)),
      );
    }
  }

  void _resetUrl() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_c != null) {
        _c.loadUrl(
          urlRequest: URLRequest(url: WebUri(_url)),
        );
      }
    });
  }

  Future<void> _initFCM() async {
    FirebaseMessaging m = FirebaseMessaging.instance;
    NotificationSettings s = await m.requestPermission(alert: true, badge: true, sound: true);
    _fcm = await m.getToken();
  }

  Future<void> _initATT() async {
    final TrackingStatus s = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (s == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
    final uuid = await AppTrackingTransparency.getAdvertisingIdentifier();
    print("UUID: $uuid");
  }

  AppsflyerSdk? _af;
  String _afid = "";
  String _conv = "";

  void _initAppsFlyer() {
    final AppsFlyerOptions opts = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6745261464",
      showDebug: true,
    );
    _af = AppsflyerSdk(opts);
    _af?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _af?.startSDK(
      onSuccess: () => print("AppsFlyer OK"),
      onError: (int code, String msg) => print("AppsFlyer ERR $code $msg"),
    );
    _af?.onInstallConversionData((res) {
      setState(() {
        _conv = res.toString();
        _afid = res['payload']['af_status'].toString();
      });
    });
    _af?.getAppsFlyerUID().then((value) {
      setState(() {
        _afid = value.toString();
      });
    });
  }
  Future<void> sendDataRaw() async {
    print("CONV DATA: $_conv");
    final jsonData = {
      "content": {
        "af_data": "$_conv",
        "af_id": "$_afid",
        "fb_app_name": "Oneraceright",
        "app_name": "Oneraceright",
        "deep": null, // если deep есть — подставьте переменную
        "bundle_identifier": "com.raceright.oneraceright",
        "app_version": "1.0.0",
        "apple_id": "6744022823",
        "fcm_token": widget.t ?? "default_fcm_token",
        "device_id": _dev ?? "default_device_id",
        "instance_id": _iid ?? "default_instance_id",
        "platform": _plf ?? "unknown_platform",
        "os_version": _os ?? "default_os_version",
        "app_version": _ver ?? "default_app_version",
        "language": _lang ?? "en",
        "timezone": _tz ?? "UTC",
        "push_enabled": _push,
        "useruid": "$_afid",
      },
    };

    // Отправка данных на сервер
   // await _sendToServer(jsonData);

    // Конвертируем в строку
    final jsonString = jsonEncode(jsonData);

    await _c.evaluateJavascript(
      source: "sendRawData(${jsonEncode(jsonString)});",
    );
  }
  Future<void> _initData() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _dev = androidInfo.id;
        _plf = "android";
        _os = androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _dev = iosInfo.identifierForVendor;
        _plf = "ios";
        _os = iosInfo.systemVersion;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      _ver = packageInfo.version;
      _lang = Platform.localeName.split('_')[0];
      _tz = tzu.local.name;
      _iid = "d67f89a0-1234-5678-9abc-def012345678";
      if (_c != null) {
        _sendDataToWeb();
      }
    } catch (e) {
      debugPrint("Init error: $e");
    }
  }

  Future<void> _sendDataToWeb() async {
    setState(() => _loading = true);
    try {
      await _c.evaluateJavascript(source: '''
      localStorage.setItem('app_data', JSON.stringify({
        "fcm_token": "${widget.t ?? 'default_fcm_token'}",
        "device_id": "${_dev ?? 'default_device_id'}",
        "app_name": "Jet4Betv1",
        "instance_id": "${_iid ?? 'default_instance_id'}",
        "platform": "${_plf ?? 'unknown_platform'}",
        "os_version": "${_os ?? 'default_os_version'}",
        "app_version": "${_ver ?? 'default_app_version'}",
        "language": "${_lang ?? 'en'}",
        "timezone": "${_tz ?? 'UTC'}",
        "push_enabled": ${_push ? 'true' : 'false'}
      }));
      ''');
      final jsonData = {
        "content": {
          "fcm_token": widget.t ?? "default_fcm_token",
          "device_id": _dev ?? "default_device_id",
          "instance_id": _iid ?? "default_instance_id",
          "platform": _plf ?? "unknown_platform",
          "os_version": _os ?? "default_os_version",
          "app_version": _ver ?? "default_app_version",
          "language": _lang ?? "en",
          "timezone": _tz ?? "UTC",
          "push_enabled": _push,
        }
      };

    } finally {
      setState(() => _loading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              contentBlockers: contentBlockers,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(_url)),
            onWebViewCreated: (controller) {
              _c = controller;
              _c.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS args: $args");
                    return args.reduce((curr, next) => curr + next);
                  });
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: "console.log('Hello from JS!');",
              );
              await _sendDataToWeb();
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class PushWebView extends StatefulWidget {
  final String url;
  const PushWebView({required this.url, super.key});
  @override
  State<PushWebView> createState() => _PushWebViewState();
}

class _PushWebViewState extends State<PushWebView> {
  late InAppWebViewController _ctrl;
  double _prog = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            onWebViewCreated: (controller) {
              _ctrl = controller;
            },
            onLoadStart: (controller, url) {
              setState(() => _prog = 0);
            },
            onLoadStop: (controller, url) {
              setState(() => _prog = 1);
            },
            onProgressChanged: (controller, progress) {
              setState(() => _prog = progress / 100);
            },
          ),
          if (_prog < 1)
            LinearProgressIndicator(
              value: _prog,
              backgroundColor: Colors.grey[200],
              color: Colors.blue,
            ),
        ],
      ),
    );
  }
}