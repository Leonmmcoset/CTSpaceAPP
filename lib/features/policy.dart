import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/widgets.dart';

class PolicyPage extends ConsumerWidget {
  const PolicyPage({super.key, required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return FeaturePage(
      title:
          const {
            'privacyPolicy': '隐私政策',
            'serviceTerms': '服务条款',
            'communityGuidelines': '社区公约',
          }[kind] ??
          '社区政策',
      child: SingleChildScrollView(
        child: ReadingWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarkdownContent(textOf(app.settings[kind], '暂时无法加载')),
              if (app.signedIn) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => perform(context, () async {
                    await app.api.post('/users/accept-policy', {
                      'version': app.settings['policyVersion'],
                    });
                    await app.refreshUser();
                  }, success: '已确认'),
                  child: const Text('同意最新政策'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
