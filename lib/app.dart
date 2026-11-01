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
import 'features/drive.dart';
import 'features/developer.dart';
import 'features/shop.dart';
import 'features/messages.dart';
import 'features/origmark.dart';
import 'features/live.dart';
import 'features/discover.dart';
import 'features/library.dart';
import 'features/support.dart';
import 'features/decoration.dart';
import 'ui/shell.dart';
import 'ui/navigation.dart';
import 'core/models.dart';
import 'features/composer.dart';
import 'ui/platform.dart';
import 'core/app_state.dart';
import 'ui/theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      ShellRoute(
        builder: (_, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/assets', builder: (_, _) => const LibraryPage()),
          GoRoute(
            path: '/assets/:id',
            builder: (_, s) => LibraryDetailPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/games',
            builder: (_, _) => const LibraryPage(games: true),
          ),
          GoRoute(
            path: '/games/:id',
            builder: (_, s) =>
                LibraryDetailPage(id: s.pathParameters['id']!, games: true),
          ),
          GoRoute(path: '/support', builder: (_, _) => const SupportPage()),
          GoRoute(
            path: '/support/:id',
            builder: (_, s) =>
                SupportConversationPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/decoration',
            builder: (_, _) => const DecorationPage(),
          ),
          GoRoute(
            path: '/discover',
            pageBuilder: (context, state) =>
                destinationPage(context, state, const DiscoverPage()),
          ),
          GoRoute(path: '/finance', builder: (_, _) => const FinancePage()),
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                destinationPage(context, state, const CommunityPage()),
          ),
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
            path: '/gallery',
            pageBuilder: (context, state) =>
                destinationPage(context, state, const GalleryPage()),
          ),
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
          GoRoute(
            path: '/me',
            pageBuilder: (context, state) =>
                destinationPage(context, state, const MePage()),
          ),
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
          GoRoute(
            path: '/changelogs',
            builder: (_, _) => const ChangelogsPage(),
          ),
          GoRoute(path: '/drive', builder: (_, _) => const DrivePage()),
          GoRoute(
            path: '/drive/share/:id',
            builder: (_, s) => DriveSharePage(shareId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/developer', builder: (_, _) => const DeveloperPage()),
          GoRoute(path: '/api-keys', builder: (_, _) => const ApiKeysPage()),
          GoRoute(path: '/cloud', builder: (_, _) => const CloudProjectsPage()),
          GoRoute(
            path: '/cloud/:id',
            builder: (_, s) => CloudProjectPage(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/shop', builder: (_, _) => const ShopPage()),
          GoRoute(
            path: '/shop/:id',
            builder: (_, s) => ProductPage(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
          GoRoute(path: '/addresses', builder: (_, _) => const AddressesPage()),
          GoRoute(
            path: '/messages',
            pageBuilder: (context, state) => destinationPage(
              context,
              state,
              MessagesPage(userId: state.uri.queryParameters['user']),
            ),
          ),
          GoRoute(path: '/friends', builder: (_, _) => const FriendsPage()),
          GoRoute(
            path: '/groups/:id',
            builder: (_, s) => GroupPage(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/live', builder: (_, _) => const LivePage()),
          GoRoute(path: '/origmark', builder: (_, _) => const OrigMarkPage()),
          GoRoute(
            path: '/origmark/registration/:id',
            builder: (_, s) => OrigMarkDetailPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/origmark/verify',
            builder: (_, s) =>
                CertificatePage(initial: s.uri.queryParameters['cert'] ?? ''),
          ),
          GoRoute(
            path: '/origmark/requests',
            builder: (_, _) => const OrigMarkRequestsPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/compose',
        builder: (_, s) => s.extra is ComposeRequest
            ? ComposerPage(request: s.extra as ComposeRequest)
            : const CommunityPage(),
      ),
      GoRoute(
        path: '/web',
        builder: (_, s) => WebPage(url: s.uri.queryParameters['url'] ?? ''),
      ),
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
