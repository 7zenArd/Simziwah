import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera init error: $e');
  }

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Simziwah',
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
      ),
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
  InAppWebViewController? webViewController;
  DateTime? lastBackPress;
  bool _isPickerActive = false;
  int _lastClickTime = 0;

  final ImagePicker _imagePicker = ImagePicker();
  late final WebUri _urlUtama;

  final List<String> _logicalStack = [];
  static const int _maxStackSize = 50;

  static final InAppWebViewSettings _webViewSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    cacheEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    useHybridComposition: true,
    hardwareAcceleration: true,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    thirdPartyCookiesEnabled: true,
    allowContentAccess: true,
    safeBrowsingEnabled: true,
    userAgent:
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    geolocationEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    initialScale: 100,
    minimumFontSize: 8,
    loadWithOverviewMode: true,
    useWideViewPort: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
  );

  @override
  void initState() {
    super.initState();
    _urlUtama = WebUri('https://simziwah.com');
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    webViewController = null;
    _logicalStack.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (webViewController == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        webViewController!.pauseTimers();
        break;
      case AppLifecycleState.resumed:
        webViewController!.resumeTimers();
        break;
      default:
        break;
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.storage,
      Permission.location,
    ].request();
  }

  Future<XFile?> _compressImageForLowRam(String path) async {
    final tempDir = Directory.systemTemp;
    final targetPath =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';

    final result = await fic.FlutterImageCompress.compressAndGetFile(
      path,
      targetPath,
      quality: 60,
      minWidth: 800,
      minHeight: 800,
      format: fic.CompressFormat.jpeg,
    );
    return result;
  }

  Future<void> _handlePhotoPicker(bool isCamera) async {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastClickTime < 1500) return;
    _lastClickTime = currentTime;

    if (_isPickerActive || !mounted) return;
    _isPickerActive = true;

    try {
      XFile? photo;

      if (isCamera && cameras.isNotEmpty) {
        photo = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(
            builder: (_) => const InAppCameraScreen(),
            fullscreenDialog: true,
          ),
        );
      } else {
        photo = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
          maxWidth: 800,
          maxHeight: 800,
          requestFullMetadata: false,
        );
      }

      if (photo != null && webViewController != null && mounted) {
        _showLoadingDialog();

        XFile? fileToProcess = photo;

        try {
          if (isCamera) {
            final compressed = await _compressImageForLowRam(photo.path);
            if (compressed != null) fileToProcess = compressed;
          }

          final base64Image = await compute(
            _encodeImageToBase64,
            fileToProcess.path,
          );
          final fileName = fileToProcess.path.split('/').last;
          await _injectPhotoToWeb(base64Image, fileName);
        } catch (e) {
          debugPrint('Error proses gambar: $e');
          if (mounted) _showErrorSnackbar();
        } finally {
          try {
            final tempOriginal = File(photo.path);
            if (await tempOriginal.exists()) await tempOriginal.delete();

            if (fileToProcess != null && fileToProcess != photo) {
              final tempCompressed = File(fileToProcess.path);
              if (await tempCompressed.exists()) await tempCompressed.delete();
            }
          } catch (_) {}

          if (mounted && Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      debugPrint('Photo picker error: $e');
    } finally {
      _isPickerActive = false;
    }
  }

  static String _encodeImageToBase64(String imagePath) {
    final bytes = File(imagePath).readAsBytesSync();
    return base64Encode(bytes);
  }

  Future<void> _injectPhotoToWeb(String base64Image, String fileName) async {
    if (webViewController == null) return;
    try {
      await webViewController!.evaluateJavascript(
        source: """
        (function() {
          try {
            var dataURL = 'data:image/jpeg;base64,$base64Image';
            var fileInput = window._lastClickedFileInput || document.querySelector('input[type="file"]');
            if (fileInput) {
              fetch(dataURL)
                .then(function(res) { return res.blob(); })
                .then(function(blob) {
                  var file = new File([blob], "$fileName", { type: "image/jpeg" });
                  var dt = new DataTransfer();
                  dt.items.add(file);
                  fileInput.files = dt.files;
                  fileInput.dispatchEvent(new Event('change', { bubbles: true }));
                  fileInput.dispatchEvent(new Event('input', { bubbles: true }));
                  window._lastClickedFileInput = null;
                  dataURL = null; // Free up JS Memory
                  blob = null; // Free up JS Memory
                });
            }
          } catch(e) { console.error('InjectPhoto:', e); }
        })();
        """,
      );
    } catch (e) {
      debugPrint('Inject error: $e');
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

  void _showErrorSnackbar() {
    messengerKey.currentState?.clearSnackBars();
    messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Gagal memproses gambar'),
        backgroundColor: Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  bool _isYouTubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'youtu.be' ||
        host == 'music.youtube.com';
  }

  Future<void> _launchExternalUrl(String urlStr) async {
    try {
      final uri = Uri.parse(urlStr);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Launch URL error: $e');
    }
  }

  void _handleExit() {
    final now = DateTime.now();
    if (lastBackPress == null ||
        now.difference(lastBackPress!) > const Duration(seconds: 2)) {
      lastBackPress = now;
      messengerKey.currentState?.clearSnackBars();
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_logicalStack.length > 1) {
          _logicalStack.removeLast();
          final targetUrl = _logicalStack.last;

          if (webViewController == null) return;

          final history = await webViewController!.getCopyBackForwardList();
          if (history?.currentIndex == null || history?.list == null) return;

          final currentIndex = history!.currentIndex!;
          int targetIndex = -1;

          for (int i = currentIndex - 1; i >= 0; i--) {
            if (history.list![i].url?.toString() == targetUrl) {
              targetIndex = i;
              break;
            }
          }

          if (targetIndex != -1) {
            await webViewController!.goBackOrForward(
              steps: targetIndex - currentIndex,
            );
          } else {
            if (await webViewController!.canGoBack()) {
              await webViewController!.goBack();
            }
          }
        } else {
          _handleExit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: _urlUtama),
            initialSettings: _webViewSettings,
            onWebViewCreated: (controller) {
              webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'photoPickerHandler',
                callback: (args) async {
                  await _handlePhotoPicker(args.isNotEmpty && args[0] == true);
                  return null;
                },
              );
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              if (url == null || isReload == true) return;
              final urlStr = url.toString();
              final existingIndex = _logicalStack.indexOf(urlStr);

              if (existingIndex != -1) {
                _logicalStack.removeRange(
                  existingIndex + 1,
                  _logicalStack.length,
                );
              } else {
                if (_logicalStack.length >= _maxStackSize) {
                  _logicalStack.removeAt(0);
                }
                _logicalStack.add(urlStr);
              }
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: """
                (function() {
                  var meta = document.querySelector('meta[name="viewport"]');
                  if (meta) {
                    meta.setAttribute('content',
                      'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');
                  } else {
                    var m = document.createElement('meta');
                    m.name = 'viewport';
                    m.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                    document.head.appendChild(m);
                  }

                  if (window._simHandlerReady) return;
                  window._simHandlerReady = true;

                  var isHandling = false;
                  document.addEventListener('click', function(e) {
                    var target = e.target;
                    var input = (target.tagName === 'INPUT' && target.type === 'file')
                      ? target
                      : target.closest('input[type="file"]');

                    if (!input) return;
                    if (isHandling) return;

                    isHandling = true;
                    e.preventDefault();
                    window._lastClickedFileInput = input;

                    window.flutter_inappwebview
                      .callHandler('photoPickerHandler', input.hasAttribute('capture'))
                      .finally(function() {
                        setTimeout(function() { isHandling = false; }, 1000);
                      });
                  }, true);
                })();
                """,
              );
            },
            onGeolocationPermissionsShowPrompt: (controller, origin) async {
              return GeolocationPermissionShowPromptResponse(
                origin: origin,
                allow: true,
                retain: true,
              );
            },
            onPermissionRequest: (controller, request) async {
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url;
              if (url == null) return NavigationActionPolicy.ALLOW;

              final urlStr = url.toString();

              if (_isYouTubeUrl(urlStr)) {
                await _launchExternalUrl(urlStr);
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
            onConsoleMessage: (controller, consoleMessage) {},
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

class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({super.key});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  void _toggleFlash() {
    if (_controller == null) return;
    setState(() => _isFlashOn = !_isFlashOn);
    _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    try {
      setState(() => _isProcessing = true);

      if (_isFlashOn) await _controller!.setFlashMode(FlashMode.off);

      final XFile image = await _controller!.takePicture();

      if (_isFlashOn) setState(() => _isFlashOn = false);
      if (!mounted) return;

      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(imagePath: image.path),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      if (result != null) {
        Navigator.pop(context, XFile(result));
      } else {
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      debugPrint('Take picture error: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 10,
                left: 20,
                right: 20,
              ),
              color: const Color(0x4D000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  IconButton(
                    icon: Icon(
                      _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: _isFlashOn ? Colors.yellow : Colors.white,
                      size: 28,
                    ),
                    onPressed: _toggleFlash,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 30,
                top: 30,
              ),
              color: const Color(0x66000000),
              child: Center(
                child: GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child:
                          _isProcessing
                              ? const CircularProgressIndicator(
                                color: Color(0xFF4CAF50),
                              )
                              : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String imagePath;
  const ImagePreviewScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            cacheWidth: 800,
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ulangi'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, imagePath),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Gunakan'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
