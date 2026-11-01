import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_state.dart';
import 'ui/theme.dart';

class CTSpaceApp extends ConsumerWidget {
  const CTSpaceApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    return DynamicColorBuilder(
      builder: (light, dark) {
        return MaterialApp(
          title: '创客次元',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/logo.png',
                    width: 88,
                    height: 88,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '创客次元',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
