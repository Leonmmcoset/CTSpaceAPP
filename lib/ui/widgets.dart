import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import 'platform.dart';
import 'theme.dart';

void toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<T?> perform<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final value = await action();
    if (context.mounted && success != null) toast(context, success);
    return value;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return null;
  }
}

Future<bool> requireSignIn(BuildContext context, WidgetRef ref) async {
  final app = ref.read(appProvider);
  if (app.signedIn) return true;
  final success = await context.push<bool>('/login');
  return success == true && app.signedIn;
}

Future<bool> confirm(
  BuildContext context,
  String title, {
  String? message,
  String action = '确定',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class FeaturePage extends StatelessWidget {
  const FeaturePage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.fab,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? fab;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 76,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
      actions: [...actions, const SizedBox(width: 12)],
    ),
    body: SafeArea(top: false, child: child),
    floatingActionButton: fab,
  );
}

class ReadingWidth extends StatelessWidget {
  const ReadingWidth({
    super.key,
    required this.child,
    this.width = 840,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.title = '这里还没有内容',
    this.icon = Icons.inbox_rounded,
    this.action,
  });
  final String title;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: c.secondaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(icon, size: 36, color: c.onSecondaryContainer),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.error, {super.key, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => EmptyState(
    title: friendlyError(error),
    icon: Icons.wifi_off_rounded,
    action: FilledButton.tonalIcon(
      onPressed: retry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('重试'),
    ),
  );
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    if (app.initializing)
      return const Center(child: CircularProgressIndicator());
    return app.signedIn
        ? child
        : EmptyState(
            title: '登录创客次元',
            icon: Icons.person_outline_rounded,
            action: FilledButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录 / 注册'),
            ),
          );
  }
}

class AsyncPanel<T> extends StatefulWidget {
  const AsyncPanel({
    super.key,
    required this.load,
    required this.builder,
    this.cacheKey,
  });
  final Future<T> Function() load;
  final Widget Function(T) builder;
  final Object? cacheKey;
  @override
  State<AsyncPanel<T>> createState() => AsyncPanelState<T>();
}

class AsyncPanelState<T> extends State<AsyncPanel<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  void didUpdateWidget(covariant AsyncPanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) future = widget.load();
  }

  void reload() {
    if (mounted) setState(() => future = widget.load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        );
      if (snapshot.hasError) return ErrorState(snapshot.error!, retry: reload);
      return widget.builder(snapshot.data as T);
    },
  );
}

class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.header,
    this.grid = false,
    this.cacheKey,
    this.emptyTitle = '这里还没有内容',
    this.padding = const EdgeInsets.all(20),
  });
  final Future<PageResult<Json>> Function(int page) load;
  final Widget Function(Json item, int index) itemBuilder;
  final Widget? header;
  final bool grid;
  final Object? cacheKey;
  final String emptyTitle;
  final EdgeInsetsGeometry padding;
  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final controller = ScrollController();
  List<Json> items = [];
  bool loading = true, more = false, loadingMore = false;
  Object? error;
  int page = 1, generation = 0;
  @override
  void initState() {
    super.initState();
    controller.addListener(_scroll);
    reload();
  }

  @override
  void didUpdateWidget(covariant PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cacheKey != oldWidget.cacheKey) reload();
  }

  void _scroll() {
    if (controller.position.extentAfter < 500 &&
        more &&
        !loadingMore &&
        !loading)
      _next();
  }

  Future<void> reload() async {
    final stamp = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.load(1);
      if (!mounted || stamp != generation) return;
      setState(() {
        items = data.items;
        more = data.hasMore;
        page = 1;
        loading = false;
      });
    } catch (e) {
      if (mounted && stamp == generation)
        setState(() {
          error = e;
          loading = false;
        });
    }
  }

  Future<void> _next() async {
    final stamp = generation;
    setState(() => loadingMore = true);
    try {
      final data = await widget.load(page + 1);
      if (!mounted || stamp != generation) return;
      final ids = items.map((e) => e['id']).toSet();
      setState(() {
        items.addAll(data.items.where((e) => !ids.contains(e['id'])));
        page++;
        more = data.hasMore;
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return ErrorState(error!, retry: reload);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = math.max(1, (constraints.maxWidth / 290).floor());
        return RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.header != null)
                SliverToBoxAdapter(child: widget.header!),
              if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading && items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(title: widget.emptyTitle),
                ),
              if (!loading && items.isNotEmpty)
                SliverPadding(
                  padding: widget.padding,
                  sliver: widget.grid
                      ? SliverGrid.builder(
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                mainAxisExtent: 324,
                              ),
                          itemBuilder: (context, index) => Entrance(
                            index: index,
                            child: widget.itemBuilder(items[index], index),
                          ),
                        )
                      : SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => Entrance(
                            index: index,
                            child: widget.itemBuilder(items[index], index),
                          ),
                        ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
                  child: Center(
                    child: loadingMore
                        ? const CircularProgressIndicator()
                        : more
                        ? TextButton(
                            onPressed: _next,
                            child: const Text('加载更多'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: MediaQuery.disableAnimationsOf(context) || index > 8 ? 1 : 0,
      end: 1,
    ),
    duration: motionDuration(context, 320 + math.min(index, 8) * 24),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}

class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;
  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool pressed = false, hover = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? .98 : 1,
    duration: motionDuration(context, 180),
    curve: Curves.easeOutCubic,
    child: Card(
      color: widget.color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => hover = v),
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => pressed = true),
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        child: AnimatedContainer(
          duration: motionDuration(context, 200),
          padding: widget.padding,
          color: hover && widget.onTap != null
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .04)
              : Colors.transparent,
          child: widget.child,
        ),
      ),
    ),
  );
}

class SpringIconButton extends StatefulWidget {
  const SpringIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
    this.count,
  });
  final IconData icon;
  final Future<void> Function() onPressed;
  final String tooltip;
  final bool selected;
  final int? count;
  @override
  State<SpringIconButton> createState() => _SpringIconButtonState();
}

class _SpringIconButtonState extends State<SpringIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool busy = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) =>
        Transform.scale(scale: controller.value.clamp(.7, 1.35), child: child),
    child: TextButton.icon(
      onPressed: busy
          ? null
          : () async {
              setState(() => busy = true);
              if (!MediaQuery.disableAnimationsOf(context)) {
                controller.animateWith(
                  SpringSimulation(
                    const SpringDescription(
                      mass: 1,
                      stiffness: 360,
                      damping: 15,
                    ),
                    .78,
                    1,
                    0,
                  ),
                );
              }
              try {
                await widget.onPressed();
              } catch (e) {
                if (context.mounted) toast(context, friendlyError(e));
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
      icon: Icon(widget.icon, size: 20),
      label: Text(widget.count == null ? widget.tooltip : '${widget.count}'),
      style: TextButton.styleFrom(
        foregroundColor: widget.selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.radius = 19, this.onTap});
  final Member member;
  final double radius;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(radius),
    onTap:
        onTap ??
        (member.id.isEmpty ? null : () => context.push('/user/${member.id}')),
    child: ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: member.avatar.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Center(
                  child: Text(
                    member.name.isEmpty
                        ? '创'
                        : String.fromCharCode(member.name.runes.first),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : AppImage(member.avatar, fit: BoxFit.cover),
      ),
    ),
  );
}

class AppImage extends StatelessWidget {
  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });
  final String url;
  final BoxFit fit;
  final double? width, height;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
    if (url.isEmpty) return fallback;
    try {
      if (url.startsWith('data:'))
        return Image.memory(
          base64Decode(url.split(',').last),
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => fallback,
        );
      return Image.network(
        absoluteUrl(url),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
      );
    } catch (_) {
      return fallback;
    }
  }
}

class ContentCover extends StatelessWidget {
  const ContentCover(this.item, {super.key});
  final ContentItem item;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return item.cover.isNotEmpty
        ? AppImage(item.cover)
        : ColoredBox(
            color: item.kind == ContentKind.extension
                ? c.tertiaryContainer
                : c.primaryContainer,
            child: Stack(
              children: [
                Positioned(
                  right: -25,
                  top: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surface.withValues(alpha: .28),
                    ),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -55,
                  child: Transform.rotate(
                    angle: .4,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        color: c.surface.withValues(alpha: .22),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    item.kind == ContentKind.extension
                        ? Icons.extension_rounded
                        : Icons.view_in_ar_rounded,
                    size: 64,
                    color: item.kind == ContentKind.extension
                        ? c.onTertiaryContainer
                        : c.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          );
  }
}

class MarkdownContent extends StatelessWidget {
  const MarkdownContent(this.data, {super.key});
  final String data;
  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: true,
    onTapLink: (_, href, _) {
      if (href != null) openLink(context, href);
    },
    imageBuilder: (uri, title, alt) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: AppImage(uri.toString(), fit: BoxFit.contain),
        ),
      ),
    ),
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyLarge,
      codeblockDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      blockquoteDecoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

class StatPill extends StatelessWidget {
  const StatPill(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 15,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
