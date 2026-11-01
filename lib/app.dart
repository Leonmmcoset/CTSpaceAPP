import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'features/auth.dart';
import 'features/policy.dart';
import 'core/app_state.dart';
import 'ui/theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('创客次元')),
          body: Center(
            child: FilledButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录 / 注册'),
            ),
          ),
        ),
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
