import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'features/auth.dart';
import 'features/policy.dart';
import 'features/forum.dart';
import 'features/gallery.dart';
import 'features/social.dart';
import 'features/settings.dart';
import 'core/models.dart';
import 'features/composer.dart';
import 'ui/platform.dart';
import 'core/app_state.dart';
import 'ui/theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const CommunityPage()),
      GoRoute(
        path: '/discussion/:id',
        builder: (_, s) => DiscussionPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/seq/:id',
        builder: (_, s) =>
            DiscussionPage(id: s.pathParameters['id']!, bySeq: true),
      ),
      GoRoute(
        path: '/compose',
        builder: (_, s) => ComposerPage(request: s.extra as ComposeRequest),
      ),
      GoRoute(
        path: '/web',
        builder: (_, s) => WebPage(url: s.uri.queryParameters['url'] ?? ''),
      ),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryPage()),
      GoRoute(
        path: '/my-creations',
        builder: (_, _) => const GalleryPage(mine: true),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (_, s) => GalleryDetailPage(
          id: s.pathParameters['id']!,
          kind: ContentKind.project,
        ),
      ),
      GoRoute(
        path: '/extension/:id',
        builder: (_, s) => GalleryDetailPage(
          id: s.pathParameters['id']!,
          kind: ContentKind.extension,
        ),
      ),
      GoRoute(path: '/me', builder: (_, _) => const MePage()),
      GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
      GoRoute(path: '/tags', builder: (_, _) => const TagsPage()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsPage(),
      ),
      GoRoute(path: '/bookmarks', builder: (_, _) => const BookmarksPage()),
      GoRoute(
        path: '/leaderboard',
        builder: (_, _) => const MembersPage(leaderboard: true),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) => UserPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/user/:id/followers',
        builder: (_, s) => MembersPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/user/:id/following',
        builder: (_, s) =>
            MembersPage(id: s.pathParameters['id']!, following: true),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/security', builder: (_, _) => const SecurityPage()),
      GoRoute(path: '/changelogs', builder: (_, _) => const ChangelogsPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/recover', builder: (_, _) => const RecoveryPage()),
      GoRoute(
        path: '/policy/:kind',
        builder: (_, state) => PolicyPage(kind: state.pathParameters['kind']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class CTSpaceApp extends ConsumerWidget {
  const CTSpaceApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    return DynamicColorBuilder(
      builder: (light, dark) {
        return MaterialApp.router(
          title: '创客次元',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          theme: buildTheme(
            state.dynamicColor && light != null
                ? light
                : ColorScheme.fromSeed(
                    seedColor: state.seed,
                    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
                  ),
          ),
          darkTheme: buildTheme(
            state.dynamicColor && dark != null
                ? dark
                : ColorScheme.fromSeed(
                    seedColor: state.seed,
                    brightness: Brightness.dark,
                    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
                  ),
          ),
          themeMode: state.themeMode,
          routerConfig: ref.watch(routerProvider),
        );
      },
    );
  }
}
