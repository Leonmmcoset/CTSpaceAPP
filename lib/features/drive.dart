import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

class DrivePage extends ConsumerStatefulWidget {
  const DrivePage({super.key});
  @override
  ConsumerState<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends ConsumerState<DrivePage> {
  int revision = 0;
  bool uploading = false;
  double? progress;
  CancelToken? cancel;
  @override
  void dispose() {
    cancel?.cancel();
    super.dispose();
  }

  Future<void> upload({String? replaceId}) async {
    final file = await pickFile();
    if (file == null || !mounted) return;
    setState(() {
      uploading = true;
      progress = null;
    });
    cancel = CancelToken();
    await perform(
      context,
      () => ref
          .read(apiProvider)
          .upload(
            file,
            path: replaceId == null
                ? '/drive/upload'
                : '/drive/files/$replaceId/replace',
            cancelToken: cancel,
            onProgress: (current, total) {
              if (mounted)
                setState(() => progress = total > 0 ? current / total : null);
            },
          ),
      success: replaceId == null ? '已上传' : '内容已更新，直链保持不变',
    );
    if (mounted)
      setState(() {
        uploading = false;
        revision++;
      });
  }

  Future<void> action(String action, Json row) async {
    final api = ref.read(apiProvider);
    final id = textOf(row['id']);
    switch (action) {
      case 'download':
        await saveRemote(
          context,
          api,
          '/api/drive/raw/${row['shareId']}?download=1',
          textOf(row['name'] ?? row['filename'], '文件'),
        );
        break;
      case 'share':
        await copyText(context, absoluteUrl('/d/${row['shareId']}'));
        break;
      case 'raw':
        await copyText(
          context,
          absoluteUrl('/api/drive/raw/${row['shareId']}'),
        );
        break;
      case 'replace':
        await upload(replaceId: id);
        break;
      case 'rename':
        await showFields(
          context,
          '重命名',
          [FieldSpec('name', '文件名', initial: row['name'] ?? row['filename'])],
          onSubmit: (d) async {
            await api.patch('/drive/files/$id', d);
          },
        );
        break;
      case 'privacy':
        await showFields(
          context,
          '分享设置',
          [
            FieldSpec(
              'isPublic',
              '公开性',
              options: const {'true': '公开', 'false': '私密'},
              initial: textOf(row['isPublic'], 'true'),
            ),
            const FieldSpec(
              'password',
              '访问密码（留空取消）',
              required: false,
              secret: true,
            ),
          ],
          onSubmit: (d) async {
            await api.patch('/drive/files/$id', {
              'isPublic': d['isPublic'] == 'true',
              'password': d['password'],
            });
          },
        );
        break;
      case 'regenerate':
        if (await confirm(context, '重新生成分享链接？', message: '旧链接将失效') && mounted)
          await perform(context, () => api.post('/drive/files/$id/regenerate'));
        break;
      case 'delete':
        if (await confirm(context, '删除文件？') && mounted)
          await perform(context, () => api.delete('/drive/files/$id'));
        break;
    }
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '云盘',
    actions: [
      IconButton(
        tooltip: '刷新',
        onPressed: () => setState(() => revision++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    fab: FloatingActionButton.extended(
      onPressed: uploading ? null : () => upload(),
      icon: const Icon(Icons.cloud_upload_outlined),
      label: const Text('上传文件'),
    ),
    child: AuthGate(
      child: Column(
        children: [
          if (uploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: progress)),
                  IconButton(
                    tooltip: '取消上传',
                    onPressed: () => cancel?.cancel(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncPanel<dynamic>(
              cacheKey: revision,
              load: () => ref.read(apiProvider).get('/drive/files'),
              builder: (data) {
                final map = object(data);
                final usage = object(map['usage']);
                final used = intOf(usage['used']),
                    limit = intOf(usage['limit']);
                final rows = objects(map['items']);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                  children: [
                    SurfaceCard(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cloud_outlined, size: 28),
                              const Spacer(),
                              Text(
                                '${fileSize(used)} / ${fileSize(limit)}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: limit > 0 ? (used / limit).clamp(0, 1) : 0,
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SectionTitle('我的文件'),
                    if (rows.isEmpty)
                      const EmptyState(
                        title: '上传你的第一个文件',
                        icon: Icons.cloud_upload_outlined,
                      ),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SurfaceCard(
                          padding: const EdgeInsets.all(8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _fileIcon(
                                  textOf(row['name'] ?? row['filename']),
                                ),
                              ),
                            ),
                            title: Text(
                              textOf(row['name'] ?? row['filename']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${fileSize(row['size'])} · ${relativeTime(row['updatedAt'] ?? row['createdAt'])}',
                            ),
                            onTap: () => action('download', row),
                            trailing: PopupMenuButton<String>(
                              onSelected: (a) => action(a, row),
                              itemBuilder: (_) => [
                                for (final e in const {
                                  'share': '复制分享链接',
                                  'raw': '复制直链',
                                  'download': '下载',
                                  'replace': '覆盖更新',
                                  'rename': '重命名',
                                  'privacy': '分享设置',
                                  'regenerate': '重新生成链接',
                                  'delete': '删除',
                                }.entries)
                                  PopupMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

IconData _fileIcon(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => Icons.image_outlined,
    'mp4' || 'webm' => Icons.movie_outlined,
    'mp3' || 'wav' => Icons.music_note_outlined,
    'sb3' => Icons.widgets_outlined,
    'zip' || '7z' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class DriveSharePage extends ConsumerStatefulWidget {
  const DriveSharePage({super.key, required this.shareId});
  final String shareId;
  @override
  ConsumerState<DriveSharePage> createState() => _DriveSharePageState();
}

class _DriveSharePageState extends ConsumerState<DriveSharePage> {
  final password = TextEditingController();
  Json? meta;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final data = object(
        await ref.read(apiProvider).get('/drive/share/${widget.shareId}', {
          'password': password.text,
        }),
      );
      if (mounted)
        setState(() {
          meta = data;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = object(meta?['file']).isEmpty
        ? meta ?? {}
        : object(meta?['file']);
    return FeaturePage(
      title: '云盘分享',
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                _fileIcon(textOf(file['name'] ?? file['filename'])),
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                textOf(file['name'] ?? file['filename'], '文件分享'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (file['size'] != null)
                Text(fileSize(file['size']), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (error != null ||
                  meta?['requiresPassword'] == true ||
                  meta?['locked'] == true) ...[
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '访问密码'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : load,
                  child: const Text('解锁'),
                ),
              ] else if (meta != null)
                FilledButton.icon(
                  onPressed: () => saveRemote(
                    context,
                    ref.read(apiProvider),
                    '/api/drive/raw/${widget.shareId}?download=1${meta!['token'] == null ? '' : '&token=${Uri.encodeComponent(textOf(meta!['token']))}'}',
                    textOf(file['name'] ?? file['filename'], '文件'),
                  ),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('下载文件'),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
