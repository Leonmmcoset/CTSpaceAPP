import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'theme.dart';

const destinations =
    <({String label, String path, IconData icon, IconData active})>[
      (
        label: '社区',
        path: '/',
        icon: Icons.forum_outlined,
        active: Icons.forum_rounded,
      ),
      (
        label: '广场',
        path: '/gallery',
        icon: Icons.widgets_outlined,
        active: Icons.widgets_rounded,
      ),
      (
        label: '发现',
        path: '/discover',
        icon: Icons.explore_outlined,
        active: Icons.explore_rounded,
      ),
      (
        label: '消息',
        path: '/messages',
        icon: Icons.chat_bubble_outline_rounded,
        active: Icons.chat_bubble_rounded,
      ),
      (
        label: '我的',
        path: '/me',
        icon: Icons.person_outline_rounded,
        active: Icons.person_rounded,
      ),
    ];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  Timer? timer;
  bool active = true;
  int tick = 0, unread = 0;
  String? lastUser;
  final bucket = PageStorageBucket();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) poll();
  }

  Future<void> poll() async {
    if (!active || !mounted) return;
    final app = ref.read(appProvider);
    if (app.signedIn) {
      try {
        final values = await Future.wait([
          app.api.get('/notifications', {'page': 1, 'pageSize': 1}),
          app.api.get('/im/inbox'),
        ]);
        final inbox = object(values[1]);
        final count =
            intOf(object(values[0])['unreadCount']) +
            [
              ...objects(inbox['dm']),
              ...objects(inbox['groups']),
            ].fold<int>(0, (sum, e) => sum + intOf(e['unread']));
        if (mounted) setState(() => unread = count);
      } catch (_) {}
    } else if (unread != 0 && mounted) {
      setState(() => unread = 0);
    }
    if (tick++ % 4 == 0 && !const bool.fromEnvironment('READ_ONLY_SMOKE')) {
      try {
        var guestToken = app.store.prefs.getString('guestToken');
        if (guestToken == null) {
          guestToken =
              'g_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
          await app.store.prefs.setString('guestToken', guestToken);
        }
        await app.api.post('/presence/heartbeat', {'guestToken': guestToken});
      } catch (_) {}
    }
  }

  int get selected {
    final root = widget.location.split('/').elementAtOrNull(1) ?? '';
    if (['', 'discussion', 'seq', 'tags'].contains(root)) return 0;
    if (['gallery', 'project', 'extension', 'my-creations'].contains(root))
      return 1;
    if (['messages', 'friends', 'groups', 'notifications'].contains(root))
      return 3;
    if ([
      'me',
      'user',
      'settings',
      'decoration',
      'security',
      'bookmarks',
      'orders',
      'addresses',
    ].contains(root))
      return 4;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 600, extended = width >= 1200;
    if (lastUser != app.user?.id) {
      lastUser = app.user?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => poll());
    }
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            context.push('/search'),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            context.push('/search'),
      },
      child: Scaffold(
        bottomNavigationBar:
            mobile && destinations.any((d) => d.path == widget.location)
            ? NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => context.go(destinations[i].path),
                destinations: destinations
                    .map(
                      (d) => NavigationDestination(
                        icon: d.path == '/messages' && unread > 0
                            ? Badge(
                                label: Text(unread > 99 ? '99+' : '$unread'),
                                child: Icon(d.icon),
                              )
                            : Icon(d.icon),
                        selectedIcon: Icon(d.active),
                        label: d.label,
                      ),
                    )
                    .toList(),
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (!mobile)
                SizedBox(
                  width: extended ? 232 : 88,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          extended ? 24 : 16,
                          24,
                          extended ? 24 : 16,
                          24,
                        ),
                        child: InkWell(
                          onTap: () => context.go('/'),
                          borderRadius: BorderRadius.circular(18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  'assets/branding/logo.png',
                                  width: 42,
                                  height: 42,
                                ),
                              ),
                              if (extended) ...[
                                const SizedBox(width: 12),
                                Text(
                                  '创客次元',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontSize: 20),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (extended)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: SearchBar(
                            hintText: '搜索',
                            onTap: () => context.push('/search'),
                            leading: const Icon(Icons.search_rounded),
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              maxHeight: 48,
                            ),
                            trailing: [
                              Text(
                                Theme.of(context).platform ==
                                        TargetPlatform.macOS
                                    ? '⌘ K'
                                    : 'Ctrl K',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                            readOnly: true,
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < destinations.length; i++)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: extended ? 14 : 10,
                                    vertical: 4,
                                  ),
                                  child: Tooltip(
                                    message: extended
                                        ? ''
                                        : destinations[i].label,
                                    child: InkWell(
                                      onTap: () =>
                                          context.go(destinations[i].path),
                                      borderRadius: BorderRadius.circular(20),
                                      child: AnimatedContainer(
                                        duration: motionDuration(context, 300),
                                        curve: motionCurve,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: extended ? 20 : 14,
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected == i
                                              ? scheme.secondaryContainer
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: extended
                                              ? MainAxisAlignment.start
                                              : MainAxisAlignment.center,
                                          children: [
                                            Badge(
                                              isLabelVisible:
                                                  i == 3 && unread > 0,
                                              label: Text('$unread'),
                                              child: Icon(
                                                selected == i
                                                    ? destinations[i].active
                                                    : destinations[i].icon,
                                                color: selected == i
                                                    ? scheme
                                                          .onSecondaryContainer
                                                    : scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (extended) ...[
                                              const SizedBox(width: 18),
                                              Text(
                                                destinations[i].label,
                                                style: TextStyle(
                                                  fontWeight: selected == i
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: selected == i
                                                      ? scheme
                                                            .onSecondaryContainer
                                                      : scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (extended) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  child: Divider(),
                                ),
                                for (final d in <(String, IconData, String)>[
                                  ('云盘', Icons.cloud_outlined, '/drive'),
                                  (
                                    '开发者工具',
                                    Icons.terminal_rounded,
                                    '/developer',
                                  ),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      leading: Icon(d.$2, size: 21),
                                      title: Text(
                                        d.$1,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      onTap: () => context.push(d.$3),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: extended
                            ? SurfaceCard(
                                padding: const EdgeInsets.all(12),
                                onTap: () => context.go('/me'),
                                child: Row(
                                  children: [
                                    MemberAvatar(
                                      app.user ?? Member({'nickname': '创'}),
                                      radius: 18,
                                      onTap: () => context.go('/me'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        app.user?.name ?? '登录账号',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.more_horiz_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              )
                            : IconButton(
                                tooltip: '设置',
                                onPressed: () => context.push('/settings'),
                                icon: const Icon(Icons.tune_rounded),
                              ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ClipRRect(
                  borderRadius: mobile
                      ? BorderRadius.zero
                      : const BorderRadius.only(topLeft: Radius.circular(28)),
                  child: ColoredBox(
                    color: scheme.surface,
                    child: PageStorage(bucket: bucket, child: widget.child),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
