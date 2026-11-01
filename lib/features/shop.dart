import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/forms.dart';
import '../ui/platform.dart';
import '../ui/widgets.dart';

String money(dynamic cents) => '¥${(intOf(cents) / 100).toStringAsFixed(2)}';

class ShopPage extends ConsumerWidget {
  const ShopPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FeaturePage(
    title: '商城',
    actions: [
      IconButton(
        tooltip: '我的订单',
        onPressed: () => context.push('/orders'),
        icon: const Icon(Icons.receipt_long_outlined),
      ),
    ],
    child: AuthGate(
      child: PagedList(
        grid: true,
        load: (page) async {
          final d = await ref.read(apiProvider).get('/shop/products');
          return PageResult.fromJson(d, (e) => e);
        },
        itemBuilder: (product, i) => SurfaceCard(
          onTap: () => context.push('/shop/${product['id']}'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: product['coverImage'] != null
                    ? AppImage(textOf(product['coverImage']))
                    : ColoredBox(
                        color: i.isEven
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.tertiaryContainer,
                        child: Icon(
                          _productIcon(textOf(product['type'])),
                          size: 64,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textOf(product['title']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (product['pointsPrice'] != null)
                          '${product['pointsPrice']} 积分',
                        if (product['cashPrice'] != null)
                          money(product['cashPrice']),
                      ].join(' / '),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

IconData _productIcon(String type) => switch (type) {
  'cloud' => Icons.cloud_outlined,
  'physical' => Icons.inventory_2_outlined,
  'digital' => Icons.download_for_offline_outlined,
  _ => Icons.auto_awesome_outlined,
};

class ProductPage extends ConsumerStatefulWidget {
  const ProductPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<ProductPage>
    with WidgetsBindingObserver {
  final panel = GlobalKey<AsyncPanelState<dynamic>>();
  int quantity = 1;
  String? sku, addressId, payMethod;
  bool busy = false;
  Json? payment;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && payment != null)
      panel.currentState?.reload();
  }

  Future<void> checkout(Json product) async {
    if (busy) return;
    final needsAddress =
        product['requiresAddress'] == true || product['type'] == 'physical';
    if (needsAddress && addressId == null) {
      toast(context, '请选择收货地址');
      return;
    }
    final variants = objects(product['variants']);
    if (variants.isNotEmpty && sku == null) {
      toast(context, '请选择规格');
      return;
    }
    if (payMethod == null) {
      toast(context, '请选择支付方式');
      return;
    }
    final chosen = variants.where((e) => e['sku'] == sku).firstOrNull;
    final stock = chosen?['stock'] ?? product['stock'];
    if (stock != null && quantity > intOf(stock)) {
      toast(context, '库存不足');
      return;
    }
    final requiredPoints = payMethod!.startsWith('points')
        ? intOf(product['pointsPrice']) * quantity
        : 0;
    if (requiredPoints > (ref.read(appProvider).user?.points ?? 0)) {
      toast(context, '积分不足');
      return;
    }
    if (!await confirm(
          context,
          '确认下单？',
          message: '${textOf(product['title'])} × $quantity',
          action: '确认下单',
        ) ||
        !mounted)
      return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = object(
        await ref.read(apiProvider).post('/shop/checkout', {
          'productId': widget.id,
          'quantity': quantity,
          'payMethod': payMethod,
          if (needsAddress) 'addressId': addressId,
          if (sku != null) 'variantSku': sku,
        }),
      );
      if (!mounted) return;
      if (result['needsPayment'] == true) {
        setState(() => payment = result);
      } else {
        await ref.read(appProvider).refreshUser();
        if (mounted) {
          toast(context, '下单成功');
          context.push('/orders');
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '商品详情',
    actions: [
      IconButton(
        tooltip: '订单',
        onPressed: () => context.push('/orders'),
        icon: const Icon(Icons.receipt_long_outlined),
      ),
    ],
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        key: panel,
        load: () async {
          final api = ref.read(apiProvider);
          return await Future.wait([
            api.get('/shop/products/${widget.id}'),
            api.get('/addresses'),
          ]);
        },
        builder: (data) {
          final product = object(data[0]);
          final addresses = objects(
            data[1] is List ? data[1] : object(data[1])['items'],
          );
          final variants = objects(product['variants']);
          final methods = textOf(
            product['paymentMethods'],
            'points',
          ).split(',').map((e) => e.trim()).toSet();
          final choices = <String, String>{
            if (methods.contains('points'))
              'points': '${product['pointsPrice']} 积分',
            if (methods.contains('wxpay'))
              'wxpay': '微信 · ${money(product['cashPrice'])}',
            if (methods.contains('alipay'))
              'alipay': '支付宝 · ${money(product['cashPrice'])}',
            if (methods.contains('points') && methods.contains('wxpay'))
              'points_wxpay': '积分 + 微信',
            if (methods.contains('points') && methods.contains('alipay'))
              'points_alipay': '积分 + 支付宝',
          };
          if (payMethod == null && choices.isNotEmpty)
            payMethod = choices.keys.first;
          if (addressId == null) {
            final address = addresses
                .where((e) => e['isDefault'] == true)
                .firstOrNull;
            if (address != null) addressId = textOf(address['id']);
          }
          return SingleChildScrollView(
            child: ReadingWidth(
              width: 800,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SizedBox(
                      height: 260,
                      child: product['coverImage'] != null
                          ? AppImage(textOf(product['coverImage']))
                          : ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                _productIcon(textOf(product['type'])),
                                size: 84,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    textOf(product['title']),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  MarkdownContent(textOf(product['description'])),
                  const SizedBox(height: 24),
                  Text(
                    [
                      if (product['pointsPrice'] != null)
                        '${product['pointsPrice']} 积分',
                      if (product['cashPrice'] != null)
                        money(product['cashPrice']),
                    ].join(' / '),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (variants.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: sku,
                      decoration: const InputDecoration(labelText: '规格'),
                      isExpanded: true,
                      items: variants
                          .map(
                            (v) => DropdownMenuItem(
                              value: textOf(v['sku']),
                              child: Text(
                                textOf(v['label'] ?? v['name'] ?? v['sku']),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: payment != null
                          ? null
                          : (v) => setState(() => sku = v),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Text('数量'),
                      const Spacer(),
                      IconButton(
                        tooltip: '减少',
                        onPressed: quantity <= 1 || payment != null
                            ? null
                            : () => setState(() => quantity--),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      Text(
                        '$quantity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        tooltip: '增加',
                        onPressed: quantity >= 99 || payment != null
                            ? null
                            : () => setState(() => quantity++),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  if (product['requiresAddress'] == true ||
                      product['type'] == 'physical') ...[
                    const SectionTitle('收货地址'),
                    if (addresses.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: addressId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '地址'),
                        items: addresses
                            .map(
                              (a) => DropdownMenuItem(
                                value: textOf(a['id']),
                                child: Text(
                                  '${a['receiverName']} · ${a['detail']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: payment != null
                            ? null
                            : (v) => setState(() => addressId = v),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        await context.push('/addresses');
                        panel.currentState?.reload();
                      },
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('管理地址'),
                    ),
                  ],
                  const SectionTitle('支付方式'),
                  for (final e in choices.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        payMethod == e.key
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: payMethod == e.key
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(e.value),
                      onTap: payment != null
                          ? null
                          : () => setState(() => payMethod = e.key),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/orders'),
                      child: const Text('检查我的订单'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (payment == null)
                    FilledButton(
                      onPressed: busy ? null : () => checkout(product),
                      child: Text(busy ? '正在下单' : '确认下单'),
                    )
                  else
                    PaymentPanel(payment: payment!),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class PaymentPanel extends StatelessWidget {
  const PaymentPanel({super.key, required this.payment});
  final Json payment;
  @override
  Widget build(BuildContext context) {
    final type = textOf(payment['payType']);
    final info = textOf(payment['payInfo']);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('订单已创建', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          if (type == 'qrcode')
            SizedBox(height: 240, child: AppImage(info, fit: BoxFit.contain)),
          if (type == 'jump')
            FilledButton.icon(
              onPressed: () => openLink(context, info, external: true),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('前往支付'),
            ),
          if (type == 'html')
            FilledButton.icon(
              onPressed: () async {
                if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _HtmlPaymentPage(html: info),
                    ),
                  );
                } else {
                  final dir = await getTemporaryDirectory();
                  final file = File(
                    '${dir.path}/ctspace-payment-${DateTime.now().millisecondsSinceEpoch}.html',
                  );
                  await file.writeAsString(info);
                  final ok = await launchUrl(Uri.file(file.path));
                  if (!ok && context.mounted) toast(context, '无法打开收银台');
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('打开收银台'),
            ),
          if (!['qrcode', 'jump', 'html'].contains(type))
            const Text('请到官网完成此订单的支付'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push('/orders'),
            child: const Text('查看支付结果'),
          ),
        ],
      ),
    );
  }
}

class _HtmlPaymentPage extends StatefulWidget {
  const _HtmlPaymentPage({required this.html});
  final String html;
  @override
  State<_HtmlPaymentPage> createState() => _HtmlPaymentPageState();
}

class _HtmlPaymentPageState extends State<_HtmlPaymentPage> {
  late final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadHtmlString(widget.html);
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '收银台',
    child: WebViewWidget(controller: controller),
  );
}

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});
  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage>
    with WidgetsBindingObserver {
  int revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted)
      setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '我的订单',
    actions: [
      IconButton(
        tooltip: '刷新',
        onPressed: () => setState(() => revision++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/shop/my/orders'),
        builder: (d) {
          final rows = objects(d is List ? d : object(d)['items']);
          return rows.isEmpty
              ? const EmptyState(
                  title: '还没有订单',
                  icon: Icons.shopping_bag_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, i) {
                    final order = rows[i];
                    final product = object(order['product']);
                    final status = textOf(order['status']);
                    return SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  textOf(
                                    product['title'] ?? order['productTitle'],
                                    '订单',
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  const {
                                        'pending': '待支付',
                                        'paid': '已支付',
                                        'shipped': '已发货',
                                        'completed': '已完成',
                                        'cancelled': '已取消',
                                        'canceled': '已取消',
                                      }[status] ??
                                      status,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '数量 ${intOf(order['quantity'])} · ${relativeTime(order['createdAt'])}',
                          ),
                          if (order['trackingNo'] != null)
                            SelectableText('物流单号 ${order['trackingNo']}'),
                          if (order['pointsTotal'] != null)
                            Text('${order['pointsTotal']} 积分'),
                          if (order['cashTotal'] != null)
                            Text(money(order['cashTotal'])),
                          Wrap(
                            spacing: 12,
                            children: [
                              if ([
                                'pending',
                                'unpaid',
                                'pending_payment',
                              ].contains(status))
                                TextButton(
                                  onPressed: () async {
                                    if (await confirm(context, '取消订单？') &&
                                        context.mounted) {
                                      await perform(
                                        context,
                                        () => ref
                                            .read(apiProvider)
                                            .post(
                                              '/shop/my/orders/${order['id']}/cancel',
                                            ),
                                      );
                                      if (mounted) setState(() => revision++);
                                    }
                                  },
                                  child: const Text('取消订单'),
                                ),
                              if (status == 'shipped')
                                FilledButton.tonal(
                                  onPressed: () async {
                                    if (await confirm(context, '确认已收到商品？') &&
                                        context.mounted) {
                                      await perform(
                                        context,
                                        () => ref
                                            .read(apiProvider)
                                            .post(
                                              '/shop/my/orders/${order['id']}/confirm',
                                            ),
                                      );
                                      if (mounted) setState(() => revision++);
                                    }
                                  },
                                  child: const Text('确认收货'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
        },
      ),
    ),
  );
}

class AddressesPage extends ConsumerStatefulWidget {
  const AddressesPage({super.key});
  @override
  ConsumerState<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends ConsumerState<AddressesPage> {
  int revision = 0;
  Future<void> edit([Json? address]) async {
    final data = await showFields(
      context,
      address == null ? '新增地址' : '编辑地址',
      [
        FieldSpec('receiverName', '收货人', initial: address?['receiverName']),
        FieldSpec('phone', '手机号', initial: address?['phone']),
        FieldSpec('province', '省份', initial: address?['province']),
        FieldSpec('city', '城市', initial: address?['city']),
        FieldSpec('district', '区县', initial: address?['district']),
        FieldSpec('detail', '详细地址', lines: 2, initial: address?['detail']),
        FieldSpec(
          'isDefault',
          '设为默认',
          options: const {'false': '否', 'true': '是'},
          initial: textOf(address?['isDefault'], 'false'),
        ),
      ],
      onSubmit: (d) async {
        final api = ref.read(apiProvider);
        final body = {...d, 'isDefault': d['isDefault'] == 'true'};
        if (address == null)
          await api.post('/addresses', body);
        else
          await api.patch('/addresses/${address['id']}', body);
      },
    );
    if (data != null && mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '收货地址',
    fab: FloatingActionButton.extended(
      onPressed: () => edit(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('新增地址'),
    ),
    child: AuthGate(
      child: AsyncPanel<dynamic>(
        cacheKey: revision,
        load: () => ref.read(apiProvider).get('/addresses'),
        builder: (d) {
          final rows = objects(d is List ? d : object(d)['items']);
          return rows.isEmpty
              ? const EmptyState(
                  title: '还没有收货地址',
                  icon: Icons.location_on_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final a = rows[i];
                    return SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${a['receiverName']}  ${a['phone']}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (a['isDefault'] == true)
                                const Chip(label: Text('默认')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${a['province']}${a['city']}${a['district']} ${a['detail']}',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: () => edit(a),
                                child: const Text('编辑'),
                              ),
                              if (a['isDefault'] != true)
                                TextButton(
                                  onPressed: () async {
                                    await perform(
                                      context,
                                      () => ref
                                          .read(apiProvider)
                                          .post(
                                            '/addresses/${a['id']}/default',
                                          ),
                                    );
                                    if (mounted) setState(() => revision++);
                                  },
                                  child: const Text('设为默认'),
                                ),
                              TextButton(
                                onPressed: () async {
                                  if (await confirm(context, '删除此地址？') &&
                                      context.mounted) {
                                    await perform(
                                      context,
                                      () => ref
                                          .read(apiProvider)
                                          .delete('/addresses/${a['id']}'),
                                    );
                                    if (mounted) setState(() => revision++);
                                  }
                                },
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
        },
      ),
    ),
  );
}
