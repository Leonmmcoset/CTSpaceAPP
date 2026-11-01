import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/markdown_codec.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

const projectCategories = {
  'game': '游戏',
  'animation': '动画',
  'story': '故事',
  'music': '音乐',
  'art': '艺术',
  'tutorial': '教程',
};
const extensionCategories = {
  'util': '工具',
  'ui': '界面',
  'data': '数据',
  'network': '网络',
  'other': '其他',
};

class ComposeRequest {
  const ComposeRequest(
    this.kind, {
    this.id,
    this.initial = const {},
    this.discussionId,
    this.replyToId,
    this.targetType,
    this.targetId,
    this.parentId,
  });
  final String kind;
  final String? id, discussionId, replyToId, targetType, targetId, parentId;
  final Json initial;
}

class ComposerPage extends ConsumerStatefulWidget {
  const ComposerPage({super.key, required this.request});
  final ComposeRequest request;
  @override
  ConsumerState<ComposerPage> createState() => _ComposerPageState();
}

class _ComposerPageState extends ConsumerState<ComposerPage> {
  final codec = MarkdownCodec();
  final title = TextEditingController(),
      summary = TextEditingController(),
      source = TextEditingController(),
      code = TextEditingController(),
      license = TextEditingController(),
      version = TextEditingController(),
      changelog = TextEditingController();
  late QuillController editor;
  final focus = FocusNode();
  final editorScroll = ScrollController();
  Timer? draftTimer;
  bool sourceMode = false,
      preview = false,
      busy = false,
      uploading = false,
      allowDownload = true,
      syncToForum = false,
      changed = false,
      ready = false;
  String category = 'game',
      original = '',
      baseline = '',
      draftStatus = '',
      error = '';
  String? fileId, coverId, publishedId;
  List<String> attachments = [], selectedTags = [];
  List<Json> tags = [];
  Json? poll;
  double? uploadProgress;
  CancelToken? uploadCancel;
  ComposeRequest get request => widget.request;
  bool get isProject => request.kind == 'project';
  bool get isExtension => request.kind == 'extension';
  bool get needsTitle =>
      ['discussion', 'project', 'extension'].contains(request.kind);
  String get userId => ref.read(appProvider).user?.id ?? 'guest';
  String get draftKey =>
      '${request.kind}_${request.id ?? request.discussionId ?? request.targetId ?? 'new'}';
  String get markdown => sourceMode
      ? source.text
      : !changed
      ? original
      : codec.encode(editor.document);
  @override
  void initState() {
    super.initState();
    original = textOf(
      request.initial['content'] ?? request.initial['description'],
    );
    sourceMode = codec.requiresSource(original);
    editor = QuillController(
      document: sourceMode ? Document() : codec.decode(original),
      selection: const TextSelection.collapsed(offset: 0),
    );
    baseline = jsonEncode(editor.document.toDelta().toJson());
    source.text = original;
    title.text = textOf(request.initial['title']);
    summary.text = textOf(request.initial['summary']);
    code.text = textOf(request.initial['code']);
    license.text = textOf(request.initial['license'], 'MIT');
    category = textOf(
      request.initial['category'],
      isExtension ? 'util' : 'game',
    );
    allowDownload = request.initial['allowDownload'] != false;
    selectedTags = objects(
      request.initial['tags'],
    ).map((e) => textOf(object(e['tag'])['id'] ?? e['id'])).toList();
    editor.addListener(_editorChanged);
    for (final c in [
      title,
      summary,
      source,
      code,
      license,
      version,
      changelog,
    ]) {
      c.addListener(_scheduleDraft);
    }
    _initialize();
  }

  Future<void> _initialize() async {
    final store = ref.read(storeProvider);
    final draft = await store.readDraft(userId, draftKey);
    if (draft != null && mounted) {
      final restore = await confirm(context, '恢复未完成的草稿？', action: '恢复');
      if (restore && mounted) {
        title.text = textOf(draft['title']);
        summary.text = textOf(draft['summary']);
        source.text = textOf(draft['content']);
        original = source.text;
        sourceMode =
            codec.requiresSource(original) || boolOf(draft['sourceMode']);
        if (!sourceMode) editor.document = codec.decode(original);
        code.text = textOf(draft['code']);
        license.text = textOf(draft['license'], 'MIT');
        fileId = draft['fileId'] as String?;
        coverId = draft['coverId'] as String?;
        category = textOf(draft['category'], category);
        allowDownload = draft['allowDownload'] != false;
        attachments = (draft['attachments'] as List? ?? [])
            .map((e) => '$e')
            .toList();
        selectedTags = (draft['tagIds'] as List? ?? [])
            .map((e) => '$e')
            .toList();
        publishedId = draft['publishedId'] as String?;
        poll = draft['poll'] == null ? null : object(draft['poll']);
      }
    }
    try {
      tags = objects(await ref.read(apiProvider).get('/tags'));
    } catch (_) {}
    if (mounted) setState(() => ready = true);
  }

  void _editorChanged() {
    if (jsonEncode(editor.document.toDelta().toJson()) != baseline)
      changed = true;
    _scheduleDraft();
  }

  void _scheduleDraft() {
    if (!ready || busy) return;
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        await ref.read(storeProvider).saveDraft(userId, draftKey, _draft());
        if (mounted) setState(() => draftStatus = '草稿已保存');
      } catch (_) {
        if (mounted) setState(() => draftStatus = '草稿保存失败');
      }
    });
  }

  Json _draft() => {
    'title': title.text,
    'summary': summary.text,
    'content': markdown,
    'sourceMode': sourceMode,
    'code': code.text,
    'license': license.text,
    'category': category,
    'allowDownload': allowDownload,
    'fileId': fileId,
    'coverId': coverId,
    'attachments': attachments,
    'tagIds': selectedTags,
    'poll': poll,
    'publishedId': publishedId,
  };
  @override
  void dispose() {
    draftTimer?.cancel();
    uploadCancel?.cancel();
    editor.removeListener(_editorChanged);
    editor.dispose();
    focus.dispose();
    editorScroll.dispose();
    for (final c in [
      title,
      summary,
      source,
      code,
      license,
      version,
      changelog,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void toggleSource() {
    if (sourceMode) {
      if (codec.requiresSource(source.text)) {
        toast(context, '此内容含特殊格式，请使用源码编辑');
        return;
      }
      try {
        editor.document = codec.decode(source.text);
        original = source.text;
        baseline = jsonEncode(editor.document.toDelta().toJson());
        changed = false;
      } catch (_) {
        toast(context, '无法转换此格式');
        return;
      }
    } else {
      source.text = markdown;
    }
    setState(() => sourceMode = !sourceMode);
    _scheduleDraft();
  }

  Future<void> upload(String type) async {
    final file = await pickFile(
      extensions: type == 'sb3'
          ? ['sb3']
          : type == 'cover' || type == 'image'
          ? ['png', 'jpg', 'jpeg', 'webp', 'gif']
          : null,
    );
    if (file == null || !mounted) return;
    final size = await file.length() ?? 0;
    if (type == 'sb3' && size > 200 * 1024 * 1024) {
      if (mounted) toast(context, 'sb3 文件不能超过 200 MB');
      return;
    }
    if (RegExp(
      r'\.(mp4|webm|mov)$',
      caseSensitive: false,
    ).hasMatch(file.name)) {
      try {
        final permission = object(
          await ref.read(apiProvider).get('/resources/can-upload-video'),
        );
        if (permission['allowed'] != true && permission['canUpload'] != true) {
          if (mounted) toast(context, '当前账号不能上传视频');
          return;
        }
      } catch (e) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
    }
    setState(() {
      uploading = true;
      uploadProgress = null;
    });
    uploadCancel = CancelToken();
    try {
      final resource = await ref
          .read(apiProvider)
          .upload(
            file,
            cancelToken: uploadCancel,
            onProgress: (sent, total) {
              if (mounted)
                setState(
                  () => uploadProgress = total > 0 ? sent / total : null,
                );
            },
          );
      if (!mounted) return;
      if (type == 'sb3')
        fileId = resource.id;
      else if (type == 'cover')
        coverId = resource.id;
      else {
        attachments.add(resource.id);
        if (type == 'image' && !sourceMode) {
          editor.replaceText(
            editor.selection.baseOffset.clamp(0, editor.document.length - 1),
            0,
            BlockEmbed.image(resource.url),
            null,
          );
        } else {
          final entry = type == 'image'
              ? '![](${resource.url})'
              : '[${resource.filename}](${resource.url})';
          if (sourceMode)
            source.text += '\n$entry\n';
          else
            editor.replaceText(
              editor.selection.baseOffset.clamp(0, editor.document.length - 1),
              0,
              '${resource.filename}\n',
              null,
            );
        }
      }
      setState(() {});
      _scheduleDraft();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> netdisk() async {
    final result = await showFields(context, '添加网盘资源', const [
      FieldSpec('provider', '网盘名称'),
      FieldSpec('link', '分享链接'),
      FieldSpec('extractCode', '提取码', required: false),
    ]);
    if (result == null || !mounted) return;
    final resource = await perform(
      context,
      () => ref.read(apiProvider).post('/resources/netdisk', result),
    );
    if (resource != null) {
      attachments.add(textOf(object(resource)['id']));
      setState(() {});
      _scheduleDraft();
    }
  }

  Future<void> submit() async {
    final app = ref.read(appProvider);
    if (!await requireSignIn(context, ref) || !mounted) return;
    if (needsTitle &&
        (title.text.trim().length < 2 || title.text.length > 255)) {
      toast(context, '标题需为 2–255 个字符');
      return;
    }
    if (isProject && request.id == null && fileId == null) {
      toast(context, '请上传 sb3 作品文件');
      return;
    }
    if (!isProject && !isExtension && markdown.trim().isEmpty) {
      toast(context, '请填写正文');
      return;
    }
    if (isExtension && code.text.trim().isEmpty) {
      toast(context, '请填写扩展源码');
      return;
    }
    if (summary.text.length > 500) {
      toast(context, '简介最多 500 字');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    draftTimer?.cancel();
    final api = app.api;
    try {
      final base = switch (request.kind) {
        'discussion' => '/discussions',
        'reply' => '/posts',
        'comment' => '/comments',
        'project' => '/projects',
        _ => '/extensions',
      };
      final body = <String, dynamic>{
        if (needsTitle) 'title': title.text.trim(),
        if (!isExtension) 'content': markdown,
        if (request.kind == 'discussion') 'tagIds': selectedTags,
        if (request.kind == 'reply' && request.id == null)
          'discussionId': request.discussionId,
        if (request.replyToId != null) 'replyToId': request.replyToId,
        if (request.kind == 'comment') ...{
          'targetType': request.targetType,
          'targetId': request.targetId,
          if (request.parentId != null) 'parentId': request.parentId,
        },
        if (isProject || isExtension) ...{
          'summary': summary.text.trim(),
          'category': category,
        },
        if (isExtension) ...{
          'code': code.text,
          'description': markdown,
          'license': license.text.trim(),
        },
        if (isProject) ...{
          'allowDownload': allowDownload,
          if (coverId != null) 'coverResourceId': coverId,
          if (fileId != null)
            request.id == null ? 'fileResourceId' : 'newFileResourceId': fileId,
          if (request.id == null) ...{
            'syncToForum': syncToForum,
            'forumTagIds': selectedTags,
          },
          if (request.id != null && fileId != null) ...{
            'versionLabel': version.text.trim(),
            'changelog': changelog.text.trim(),
          },
        },
      };
      if (publishedId == null) {
        final response = object(
          request.id == null
              ? await api.post(base, body)
              : await api.patch('$base/${request.id}', body),
        );
        publishedId = textOf(response['id'], request.id ?? '');
        if (publishedId!.isEmpty) throw const ApiFailure('响应缺少内容编号，请先检查我的内容');
        await app.store.saveDraft(userId, draftKey, _draft());
      }
      if (['discussion', 'reply'].contains(request.kind)) {
        for (final resourceId in List<String>.of(attachments)) {
          await api.patch('/resources/$resourceId', {
            request.kind == 'discussion' ? 'discussionId' : 'postId':
                publishedId,
          });
          attachments.remove(resourceId);
        }
      }
      if (poll != null && request.kind == 'discussion') {
        await api.post('/polls', {'discussionId': publishedId, ...poll!});
        poll = null;
      }
      await app.store.deleteDraft(userId, draftKey);
      app.changed();
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted)
        setState(
          () => error = publishedId == null
              ? friendlyError(e)
              : '内容已保存，附件或投票未完成：${friendlyError(e)}',
        );
      await app.store.saveDraft(userId, draftKey, _draft());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = request.id != null
        ? '编辑内容'
        : const {
                'discussion': '发布讨论',
                'reply': '回复',
                'comment': '评论',
                'project': '发布作品',
                'extension': '发布扩展',
              }[request.kind] ??
              '发布';
    return PopScope(
      canPop: !busy && !uploading,
      child: FeaturePage(
        title: heading,
        subtitle: draftStatus.isEmpty ? null : draftStatus,
        actions: [
          IconButton(
            tooltip: '预览',
            onPressed: () => setState(() => preview = !preview),
            icon: Icon(
              preview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: busy || uploading ? null : submit,
              child: Text(
                busy
                    ? '正在保存'
                    : publishedId != null
                    ? '完成关联'
                    : request.id == null
                    ? '发布'
                    : '保存',
              ),
            ),
          ),
        ],
        child: !ready
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: ReadingWidth(
                  width: 960,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (needsTitle) ...[
                        TextField(
                          controller: title,
                          maxLength: 255,
                          style: Theme.of(context).textTheme.headlineSmall,
                          decoration: const InputDecoration(
                            hintText: '标题',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (isProject || isExtension) ...[
                        TextField(
                          controller: summary,
                          maxLength: 500,
                          decoration: const InputDecoration(labelText: '简介'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue:
                              (isExtension
                                      ? extensionCategories
                                      : projectCategories)
                                  .containsKey(category)
                              ? category
                              : null,
                          decoration: const InputDecoration(labelText: '分类'),
                          items:
                              (isExtension
                                      ? extensionCategories
                                      : projectCategories)
                                  .entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            setState(() => category = v!);
                            _scheduleDraft();
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (!preview) ...[
                        Row(
                          children: [
                            Text(
                              '正文',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: toggleSource,
                              icon: const Icon(Icons.code_rounded),
                              label: Text(sourceMode ? '切换富文本' : 'Markdown'),
                            ),
                          ],
                        ),
                        if (!sourceMode)
                          QuillSimpleToolbar(
                            controller: editor,
                            config: const QuillSimpleToolbarConfig(
                              showFontFamily: false,
                              showFontSize: false,
                              showColorButton: false,
                              showBackgroundColorButton: false,
                              showUnderLineButton: false,
                              showSubscript: false,
                              showSuperscript: false,
                              showSearchButton: false,
                              showAlignmentButtons: false,
                              showIndent: false,
                              toolbarIconAlignment: WrapAlignment.start,
                              showListCheck: false,
                            ),
                          ),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          constraints: const BoxConstraints(minHeight: 280),
                          padding: const EdgeInsets.all(16),
                          child: sourceMode
                              ? TextField(
                                  controller: source,
                                  minLines: 12,
                                  maxLines: null,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Markdown 正文',
                                    filled: false,
                                  ),
                                )
                              : QuillEditor(
                                  controller: editor,
                                  focusNode: focus,
                                  scrollController: editorScroll,
                                  config: const QuillEditorConfig(
                                    scrollable: false,
                                    minHeight: 260,
                                    placeholder: '写点什么…',
                                    embedBuilders: [_ImageEmbed()],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: uploading
                                  ? null
                                  : () => upload('image'),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('图片'),
                            ),
                            OutlinedButton.icon(
                              onPressed: uploading
                                  ? null
                                  : () => upload('attachment'),
                              icon: const Icon(Icons.attach_file_rounded),
                              label: const Text('附件'),
                            ),
                            TextButton.icon(
                              onPressed: netdisk,
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('网盘资源'),
                            ),
                          ],
                        ),
                      ] else
                        SurfaceCard(child: MarkdownContent(markdown)),
                      if (uploading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: uploadProgress,
                                ),
                              ),
                              IconButton(
                                onPressed: () => uploadCancel?.cancel(),
                                icon: const Icon(Icons.close_rounded),
                                tooltip: '取消上传',
                              ),
                            ],
                          ),
                        ),
                      if (attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            spacing: 8,
                            children: attachments
                                .map(
                                  (e) => InputChip(
                                    label: const Text('已上传附件'),
                                    onDeleted: () {
                                      setState(() => attachments.remove(e));
                                      _scheduleDraft();
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (request.kind == 'discussion' || isProject) ...[
                        const SectionTitle('标签'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: tags
                              .map(
                                (t) => FilterChip(
                                  label: Text(textOf(t['name'])),
                                  selected: selectedTags.contains(t['id']),
                                  onSelected: (v) {
                                    setState(
                                      () => v
                                          ? selectedTags.add(textOf(t['id']))
                                          : selectedTags.remove(t['id']),
                                    );
                                    _scheduleDraft();
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (request.kind == 'discussion') ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final value = await showFields(
                              context,
                              '添加投票',
                              const [
                                FieldSpec('question', '投票问题'),
                                FieldSpec('options', '选项（每行一个）', lines: 4),
                                FieldSpec(
                                  'multiple',
                                  '投票方式',
                                  options: {'false': '单选', 'true': '多选'},
                                ),
                              ],
                            );
                            if (value == null || !context.mounted) return;
                            final options = textOf(value['options'])
                                .split('\n')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toSet()
                                .toList();
                            if (options.length < 2) {
                              toast(context, '至少填写两个不同选项');
                              return;
                            }
                            setState(
                              () => poll = {
                                'question': value['question'],
                                'options': options,
                                'multiple': value['multiple'] == 'true',
                              },
                            );
                            _scheduleDraft();
                          },
                          icon: const Icon(Icons.poll_outlined),
                          label: Text(poll == null ? '添加投票' : '已添加投票'),
                        ),
                      ],
                      if (isProject) ...[
                        const SectionTitle('作品文件'),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: uploading ? null : () => upload('sb3'),
                              icon: const Icon(Icons.upload_file_rounded),
                              label: Text(
                                fileId == null
                                    ? request.id == null
                                          ? '上传 sb3'
                                          : '上传新版本'
                                    : '作品已上传',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: uploading
                                  ? null
                                  : () => upload('cover'),
                              icon: const Icon(Icons.photo_outlined),
                              label: Text(coverId == null ? '上传封面' : '封面已上传'),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('允许下载源文件'),
                          value: allowDownload,
                          onChanged: (v) {
                            setState(() => allowDownload = v);
                            _scheduleDraft();
                          },
                        ),
                        if (request.id == null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('同步到论坛'),
                            value: syncToForum,
                            onChanged: (v) => setState(() => syncToForum = v),
                          ),
                        if (request.id != null && fileId != null) ...[
                          TextField(
                            controller: version,
                            decoration: const InputDecoration(labelText: '版本号'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: changelog,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: '更新内容',
                            ),
                          ),
                        ],
                      ],
                      if (isExtension) ...[
                        const SectionTitle('源码'),
                        TextField(
                          controller: code,
                          minLines: 12,
                          maxLines: 24,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'JavaScript',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: license,
                          decoration: const InputDecoration(labelText: '许可证'),
                        ),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ImageEmbed extends EmbedBuilder {
  const _ImageEmbed();
  @override
  String get key => 'image';
  @override
  Widget build(BuildContext context, EmbedContext embedContext) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: AppImage(
        textOf(embedContext.node.value.data),
        fit: BoxFit.contain,
      ),
    ),
  );
}
