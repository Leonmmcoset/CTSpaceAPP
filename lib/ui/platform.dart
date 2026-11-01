import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/api.dart';
import '../core/models.dart';

Future<void> copyText(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制')));
}

Future<void> openLink(
  BuildContext context,
  String value, {
  bool external = false,
}) async {
  final uri = Uri.tryParse(absoluteUrl(value.trim()));
  if (uri == null || !['http', 'https', 'mailto'].contains(uri.scheme)) return;
  if (!external && uri.host == siteUri.host) {
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      final route = switch (segments[0]) {
        'discussion' => '/discussion/${segments[1]}',
        'ts' => '/seq/${segments[1]}',
        'project' || 'projects' || 'works' => '/project/${segments[1]}',
        'extension' || 'extensions' => '/extension/${segments[1]}',
        'user' || 'users' => '/user/${segments[1]}',
        'd' || 'c' => '/drive/share/${segments[1]}',
        _ => null,
      };
      if (route != null) {
        context.push(route);
        return;
      }
    }
  }
  if (!external &&
      uri.scheme == 'https' &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    if (context.mounted)
      context.push('/web?url=${Uri.encodeComponent(uri.toString())}');
  } else {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}

Future<PlatformFile?> pickFile({List<String>? extensions}) async {
  final result = await FilePicker.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  return result.firstOrNull;
}

Future<void> saveRemote(
  BuildContext context,
  ApiClient api,
  String url,
  String name,
) async {
  final safeName = name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
  final cancel = CancelToken();
  final progress = ValueNotifier<double?>(null);
  final directory = await getTemporaryDirectory();
  final temporary = File(
    '${directory.path}/ctspace-${DateTime.now().microsecondsSinceEpoch}-$safeName',
  );
  if (!context.mounted) return;
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(safeName),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text(value == null ? '准备下载' : '${(value * 100).round()}%'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancel.cancel();
            },
            child: const Text('取消'),
          ),
        ],
      ),
    ),
  ).whenComplete(() => dialogOpen = false);
  try {
    await api.download(
      url,
      temporary.path,
      cancelToken: cancel,
      onProgress: (current, total) =>
          progress.value = total > 0 ? current / total : null,
    );
    if (!context.mounted) return;
    if (dialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
    }
    final bytes = await temporary.readAsBytes();
    final destination = await FilePicker.saveFile(
      fileName: safeName,
      dialogTitle: '保存文件',
      bytes: bytes,
    );
    if (context.mounted && destination != null)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
  } catch (e) {
    if (context.mounted) {
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
    progress.dispose();
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url});
  final String url;
  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? controller;
  int progress = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (uri == null || uri.scheme != 'https') {
      error = '无效的网页地址';
      return;
    }
    if (Platform.isWindows || Platform.isLinux) return;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (v) {
            if (mounted) setState(() => progress = v);
          },
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true)
              setState(() => error = '网页加载失败');
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            return target != null &&
                    ['https', 'http', 'about'].contains(target.scheme)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('创客次元'),
      actions: [
        IconButton(
          tooltip: '浏览器打开',
          onPressed: () => openLink(context, widget.url, external: true),
          icon: const Icon(Icons.open_in_new_rounded),
        ),
        if (controller != null)
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              setState(() => error = null);
              controller!.reload();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    ),
    body: error != null
        ? Center(child: Text(error!))
        : controller == null
        ? Center(
            child: FilledButton.icon(
              onPressed: () => openLink(context, widget.url, external: true),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('在浏览器中打开'),
            ),
          )
        : Column(
            children: [
              if (progress < 100)
                LinearProgressIndicator(value: progress / 100),
              Expanded(child: WebViewWidget(controller: controller!)),
            ],
          ),
  );
}
