import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/pow.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';

class CaptchaValue {
  const CaptchaValue(this.token, this.answer, this.nonce);
  final String token, answer, nonce;
  Json toJson() => {
    'captchaToken': token,
    'captchaAnswer': answer,
    'captchaPowNonce': nonce,
  };
}

class CaptchaInput extends ConsumerStatefulWidget {
  const CaptchaInput({super.key});
  @override
  ConsumerState<CaptchaInput> createState() => CaptchaInputState();
}

class CaptchaInputState extends ConsumerState<CaptchaInput> {
  final answer = TextEditingController();
  Json? captcha;
  String? nonce, error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    answer.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final stamp = ++generation;
    setState(() {
      captcha = null;
      nonce = null;
      error = null;
      answer.clear();
    });
    try {
      final result = object(await ref.read(apiProvider).get('/captcha'));
      if (!mounted || stamp != generation) return;
      setState(() => captcha = result);
      final solution = await computeProofOfWork(object(result['pow']));
      if (mounted && stamp == generation) setState(() => nonce = solution);
    } catch (e) {
      if (mounted && stamp == generation)
        setState(() => error = friendlyError(e));
    }
  }

  CaptchaValue? get value =>
      captcha != null && nonce != null && answer.text.trim().isNotEmpty
      ? CaptchaValue(textOf(captcha!['token']), answer.text.trim(), nonce!)
      : null;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 78,
              child: captcha == null
                  ? Center(
                      child: error == null
                          ? const CircularProgressIndicator()
                          : Text(error!),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppImage(
                        textOf(captcha!['image']),
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
          IconButton(
            onPressed: refresh,
            tooltip: '刷新验证码',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: answer,
        textCapitalization: TextCapitalization.characters,
        maxLength: 4,
        decoration: InputDecoration(
          labelText: '验证码',
          counterText: '',
          suffixIcon: captcha != null && nonce == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        validator: (v) => v == null || v.trim().isEmpty ? '请输入验证码' : null,
      ),
    ],
  );
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final form = GlobalKey<FormState>();
  final captcha = GlobalKey<CaptchaInputState>();
  final username = TextEditingController(), password = TextEditingController();
  bool hidden = true, busy = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    final proof = captcha.currentState?.value;
    if (proof == null) {
      toast(context, '请完成验证码验证');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(appProvider).signIn({
        'username': username.text.trim(),
        'password': password.text,
        ...proof.toJson(),
      });
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyError(e));
        unawaited(captcha.currentState?.refresh());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '登录',
    child: Center(
      child: SingleChildScrollView(
        child: ReadingWidth(
          width: 460,
          child: AutofillGroup(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/branding/logo.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '欢迎回来',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: username,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名或邮箱',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入用户名或邮箱' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    obscureText: hidden,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hidden = !hidden),
                        tooltip: hidden ? '显示密码' : '隐藏密码',
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 20),
                  CaptchaInput(key: captcha),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : login,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => context.push('/register'),
                        child: const Text('注册账号'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/recover'),
                        child: const Text('找回账号'),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () async {
                      await showFields(
                        context,
                        '重发激活邮件',
                        const [FieldSpec('identifier', '邮箱或用户名')],
                        submitLabel: '发送',
                        onSubmit: (data) async {
                          await ref
                              .read(apiProvider)
                              .post('/auth/resend', data);
                        },
                      );
                    },
                    child: const Text('重发激活邮件'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool busy = false, sent = false, accepted = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || !accepted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(apiProvider).post('/auth/register', {
        'username': username.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
      });
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '注册',
    child: SingleChildScrollView(
      child: ReadingWidth(
        width: 480,
        child: sent
            ? Column(
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.mark_email_read_rounded, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    '查收激活邮件',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(email.text),
                  const SizedBox(height: 12),
                  const Text('请在 30 分钟内完成激活'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('返回登录'),
                  ),
                ],
              )
            : Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '加入创客次元',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: username,
                      decoration: const InputDecoration(labelText: '用户名'),
                      validator: (v) =>
                          (v?.trim().length ?? 0) < 2 ? '至少 2 个字符' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
                      validator: (v) =>
                          v == null ||
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v.trim())
                          ? '请输入有效邮箱'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                      validator: (v) =>
                          (v?.length ?? 0) < 6 ? '密码至少 6 位' : null,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: accepted,
                      onChanged: (v) => setState(() => accepted = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: Wrap(
                        children: [
                          const Text('我已阅读并同意'),
                          for (final e in {
                            'privacyPolicy': '隐私政策',
                            'serviceTerms': '服务条款',
                            'communityGuidelines': '社区公约',
                          }.entries)
                            TextButton(
                              onPressed: () => context.push('/policy/${e.key}'),
                              child: Text(e.value),
                            ),
                        ],
                      ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy || !accepted ? null : submit,
                      child: Text(busy ? '正在注册' : '注册'),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class RecoveryPage extends ConsumerStatefulWidget {
  const RecoveryPage({super.key});
  @override
  ConsumerState<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends ConsumerState<RecoveryPage> {
  final email = TextEditingController();
  final captcha = GlobalKey<CaptchaInputState>();
  bool usernameMode = false, busy = false;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '找回账号',
    child: SingleChildScrollView(
      child: ReadingWidth(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('找回密码')),
                ButtonSegment(value: true, label: Text('找回用户名')),
              ],
              selected: {usernameMode},
              onSelectionChanged: (v) => setState(() => usernameMode = v.first),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '注册邮箱'),
            ),
            const SizedBox(height: 20),
            CaptchaInput(key: captcha),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final proof = captcha.currentState?.value;
                      if (proof == null || email.text.trim().isEmpty) {
                        toast(context, '请填写邮箱和验证码');
                        return;
                      }
                      setState(() => busy = true);
                      await perform(
                        context,
                        () => ref.read(apiProvider).post(
                          usernameMode
                              ? '/auth/forgot-username'
                              : '/auth/forgot-password',
                          {'email': email.text.trim(), ...proof.toJson()},
                        ),
                        success: '已发送，请查收邮件',
                      );
                      if (mounted) {
                        setState(() => busy = false);
                        unawaited(captcha.currentState?.refresh());
                      }
                    },
              child: Text(busy ? '正在发送' : '发送邮件'),
            ),
            TextButton(
              onPressed: () async {
                await showFields(
                  context,
                  '重置密码',
                  const [
                    FieldSpec('token', '邮件中的重置令牌'),
                    FieldSpec('newPassword', '新密码', secret: true, minLength: 6),
                  ],
                  onSubmit: (data) async {
                    await ref
                        .read(apiProvider)
                        .post('/auth/reset-password', data);
                  },
                );
              },
              child: const Text('使用重置令牌'),
            ),
          ],
        ),
      ),
    ),
  );
}
