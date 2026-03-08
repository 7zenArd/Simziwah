import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SimziwahApp());
}

class SimziwahApp extends StatelessWidget {
  const SimziwahApp({super.key});

  static final ThemeData _theme = ThemeData.light(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Simziwah',
      theme: _theme,
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  InAppWebViewController? _webCtrl;
  final _picker = ImagePicker();
  static final WebUri _homeUrl = WebUri('https://simziwah.com');

  bool _isPickerActive = false;
  int _lastPickerTime = 0;
  DateTime? _lastBackPress;
  final List<String> _navStack = [];
  static const int _navStackMax = 50;

  static final InAppWebViewSettings _webSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    cacheEnabled: true,
    useHybridComposition: true,
    transparentBackground: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    safeBrowsingEnabled: true,
    thirdPartyCookiesEnabled: true,
    allowContentAccess: true,
    mediaPlaybackRequiresUserGesture: false,
    disableHorizontalScroll: false,
    disableVerticalScroll: false,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    initialScale: 100,
    minimumFontSize: 8,
    userAgent:
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  );

  static const String _jsOnLoad = r"""
  (function() {
    // Disable zoom
    var vp = document.querySelector('meta[name="viewport"]');
    if (vp) {
      vp.content = 'width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no';
    } else {
      var m = document.createElement('meta');
      m.name = 'viewport';
      m.content = 'width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no';
      document.head.appendChild(m);
    }

    if (window._simReady) return;
    window._simReady = true;

    var busy = false;
    document.addEventListener('click', function(e) {
      var inp = (e.target.type === 'file') ? e.target : e.target.closest('input[type="file"]');
      if (inp && !busy) {
        busy = true;
        e.preventDefault();
        window._activeInput = inp;
        window.flutter_inappwebview
          .callHandler('photoPicker', inp.hasAttribute('capture'))
          .finally(function() { setTimeout(function() { busy = false; }, 1000); });
        return;
      }

      var target = e.target;
      var shareBtn = target.closest('[data-share]') || target.closest('.share-btn') || 
                     target.closest('[class*="share"]') || target.closest('a[href*="whatsapp"]') ||
                     target.closest('a[href*="facebook"]') || target.closest('a[href*="fb:"]') ||
                     target.closest('a[href*="instagram"]') || target.closest('a[href*="twitter"]') ||
                     target.closest('a[href*="x.com"]') || target.closest('a[href*="wa.me"]');
      
      if (shareBtn) {
        var href = shareBtn.href || shareBtn.getAttribute('data-url') || '';
        if (href) {
          e.preventDefault();
          e.stopPropagation();
          window.flutter_inappwebview.callHandler('shareSheet', href);
        }
      }
    }, true);
  })();
  """;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webCtrl?.dispose();
    _navStack.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_webCtrl == null) return;
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      _webCtrl?.pauseTimers();
    } else if (state == AppLifecycleState.resumed) {
      _webCtrl?.resumeTimers();
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.storage,
      Permission.location,
    ].request();
  }

  Future<void> _handlePhotoPicker(bool isCamera) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPickerTime < 1500 || _isPickerActive || !mounted) return;
    _lastPickerTime = now;
    _isPickerActive = true;

    try {
      final XFile? photo = isCamera
          ? await _picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 55,
              maxWidth: 1024,
              maxHeight: 1024,
              requestFullMetadata: false,
            )
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 55,
              maxWidth: 1024,
              maxHeight: 1024,
              requestFullMetadata: false,
            );

      if (photo == null || _webCtrl == null || !mounted) return;

      _showLoadingDialog();

      try {
        final b64 = await compute(_encodeBase64, photo.path);
        final name = photo.path.split('/').last;
        await _injectPhoto(b64, name);
      } catch (e) {
        debugPrint('Photo process error: $e');
        if (mounted) _showError('Gagal memproses gambar');
      } finally {
        try {
          final f = File(photo.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Picker error: $e');
    } finally {
      _isPickerActive = false;
    }
  }

  static String _encodeBase64(String path) =>
      base64Encode(File(path).readAsBytesSync());

  Future<void> _injectPhoto(String b64, String name) async {
    await _webCtrl?.evaluateJavascript(source: """
    (function() {
      var inp = window._activeInput || document.querySelector('input[type="file"]');
      if (!inp) return;
      fetch('data:image/jpeg;base64,$b64')
        .then(function(r){ return r.blob(); })
        .then(function(blob){
          var f = new File([blob], "$name", {type:'image/jpeg'});
          var dt = new DataTransfer();
          dt.items.add(f);
          inp.files = dt.files;
          inp.dispatchEvent(new Event('change',{bubbles:true}));
          inp.dispatchEvent(new Event('input',{bubbles:true}));
          window._activeInput = null;
        });
    })();
    """);
  }

  bool _isYouTube(String url) {
    final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return h == 'youtube.com' ||
        h == 'www.youtube.com' ||
        h == 'm.youtube.com' ||
        h == 'youtu.be' ||
        h == 'music.youtube.com';
  }

  Future<void> _launchExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Launch error: $e');
    }
  }

  Future<void> _handleShareSheet(String url) async {
    final lowerUrl = url.toLowerCase();
    String? appUrl;

    if (lowerUrl.contains('whatsapp') || lowerUrl.contains('wa.me')) {
      appUrl = lowerUrl.contains('whatsapp.com') || lowerUrl.contains('wa.me')
          ? url
          : 'whatsapp://send?text=${Uri.encodeComponent(url)}';
    } else if (lowerUrl.contains('facebook') || lowerUrl.contains('fb:')) {
      appUrl = 'fb://facewebmodal/f?href=${Uri.encodeComponent(url)}';
    } else if (lowerUrl.contains('instagram')) {
      appUrl = 'instagram://web';
    } else if (lowerUrl.contains('twitter') || lowerUrl.contains('x.com')) {
      appUrl = 'twitter://post?text=${Uri.encodeComponent(url)}';
    }

    if (appUrl != null) {
      final uri = Uri.parse(appUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await _launchExternal(url);
      }
    } else {
      await _launchExternal(url);
    }
  }

  void _updateNavStack(String url, bool isReload) {
    if (isReload) return;

    final i = _navStack.indexOf(url);
    if (i != -1) {
      _navStack.removeRange(i + 1, _navStack.length);
    } else {
      if (_navStack.length >= _navStackMax) _navStack.removeAt(0);
      _navStack.add(url);
    }
  }

  Future<void> _handleBack() async {
    if (_navStack.length <= 1) {
      _handleExit();
      return;
    }

    _navStack.removeLast();
    if (_webCtrl == null) return;

    final history = await _webCtrl!.getCopyBackForwardList();
    if (history?.currentIndex == null || history?.list == null) return;

    final cur = history!.currentIndex!;
    int targetIdx = -1;

    for (int i = cur - 1; i >= 0; i--) {
      if (history.list![i].url?.toString() == _navStack.last) {
        targetIdx = i;
        break;
      }
    }

    if (targetIdx != -1) {
      await _webCtrl!.goBackOrForward(steps: targetIdx - cur);
    } else if (await _webCtrl!.canGoBack()) {
      await _webCtrl!.goBack();
    }
  }

  void _handleExit() {
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Tekan sekali lagi untuk keluar'),
            duration: Duration(seconds: 2),
          ),
        );
    } else {
      SystemNavigator.pop();
    }
  }

  void _showLoadingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: _LoadingDialog()),
    );
  }

  void _showError(String msg) {
    messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: _homeUrl),
            initialSettings: _webSettings,

            onWebViewCreated: (ctrl) {
              _webCtrl = ctrl;
              ctrl.addJavaScriptHandler(
                handlerName: 'photoPicker',
                callback: (args) async {
                  await _handlePhotoPicker(args.isNotEmpty && args[0] == true);
                },
              );
              ctrl.addJavaScriptHandler(
                handlerName: 'shareSheet',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    await _handleShareSheet(args[0].toString());
                  }
                },
              );
            },

            onUpdateVisitedHistory: (_, url, isReload) {
              if (url != null) {
                _updateNavStack(url.toString(), isReload ?? false);
              }
            },

            onLoadStop: (ctrl, _) => ctrl.evaluateJavascript(source: _jsOnLoad),

            shouldOverrideUrlLoading: (_, action) async {
              final url = action.request.url?.toString() ?? '';
              final lowerUrl = url.toLowerCase();

              if (_isYouTube(url)) {
                await _launchExternal(url);
                return NavigationActionPolicy.CANCEL;
              }

              if (lowerUrl.contains('whatsapp') ||
                  lowerUrl.contains('wa.me') ||
                  lowerUrl.contains('fb:') ||
                  lowerUrl.contains('facebook') ||
                  lowerUrl.contains('instagram') ||
                  lowerUrl.contains('twitter') ||
                  lowerUrl.contains('x.com') ||
                  url.startsWith('whatsapp://') ||
                  url.startsWith('fb://') ||
                  url.startsWith('instagram://') ||
                  url.startsWith('twitter://') ||
                  url.startsWith('tg://')) {
                await _handleShareSheet(url);
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },

            onGeolocationPermissionsShowPrompt:
                (_, origin) async => GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: true,
                  retain: true,
                ),

            onPermissionRequest:
                (_, req) async => PermissionResponse(
                  resources: req.resources,
                  action: PermissionResponseAction.GRANT,
                ),

            onConsoleMessage: (_, __) {},
          ),
        ),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
                strokeWidth: 4,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Mengirim Data...',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
