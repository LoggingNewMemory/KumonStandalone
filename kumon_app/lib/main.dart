import 'dart:collection'; // Needed for UnmodifiableListView
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Force Portrait Mode (Failsafe)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Permission.camera.request();
  await Permission.microphone.request();

  // 2. Hide Status Bar (Immersive Mode)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kumon App',
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  bool canGoBack = false;

  // --- JAVASCRIPT SPOOFING LOGIC ---
  // This script listens for all pointer events and forces the browser
  // to report them as 'mouse' instead of 'touch'.
  final String spoofInputJs = """
    (function() {
        console.log("Spoofing Mouse Input Active");
        
        const eventTypes = [
            'pointerdown', 'pointermove', 'pointerup', 
            'pointerover', 'pointerout', 'pointerenter', 'pointerleave',
            'gotpointercapture', 'lostpointercapture'
        ];

        eventTypes.forEach(function(type) {
            window.addEventListener(type, function(event) {
                // Intercept the event and force pointerType to 'mouse'
                Object.defineProperty(event, 'pointerType', {
                    get: function() { return 'mouse'; }, // Spoof as mouse
                    configurable: true
                });
            }, { capture: true }); // Capture phase ensures we hit it before the app does
        });
    })();
  """;
  // ---------------------------------

  Future<bool> _onWillPop() async {
    if (await webViewController?.canGoBack() ?? false) {
      webViewController?.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ensure assets exist or handle error if missing
              // Image.asset('assets/logo.png', height: 32),
              const SizedBox(width: 8),
              const Text('Kumon App', style: TextStyle(fontSize: 16)),
            ],
          ),
          actions: [
            if (canGoBack)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => webViewController?.goBack(),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => webViewController?.reload(),
            ),
          ],
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://kumonapp.digital.kumon.com/id/index.html'),
              ),
              // Inject the script at the very start of the document load
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: spoofInputJs,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ]),
              initialOptions: InAppWebViewGroupOptions(
                crossPlatform: InAppWebViewOptions(
                  // Keeping your iPad UA is fine, but sometimes switching to a Desktop UA
                  // helps further if the JS spoof alone isn't enough.
                  userAgent:
                      'Mozilla/5.0 (iPad; CPU OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  // Tapping usually delays slightly on mobile; disabling this might make drawing snappier
                  disableVerticalScroll: false,
                  preferredContentMode: UserPreferredContentMode.RECOMMENDED,
                ),
                android: AndroidInAppWebViewOptions(
                  useHybridComposition: true,
                  // Ensure scale is correct so "mouse" hits the right coordinates
                  loadWithOverviewMode: true,
                  useWideViewPort: true,
                ),
                ios: IOSInAppWebViewOptions(allowsInlineMediaPlayback: true),
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'mediaPermission',
                  callback: (args) async {
                    return true;
                  },
                );
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onLoadStart: (controller, url) {
                setState(() => isLoading = true);
              },
              onLoadStop: (controller, url) async {
                final canNavigateBack = await controller.canGoBack();
                setState(() {
                  isLoading = false;
                  canGoBack = canNavigateBack;
                });
              },
            ),
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
