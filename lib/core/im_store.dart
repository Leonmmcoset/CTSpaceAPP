import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'models.dart';

class Conversation {
  const Conversation({
    required this.kind,
    required this.id,
    required this.title,
    this.avatar = '',
    this.raw = const {},
  });
  final String kind, id, title, avatar;
  final Json raw;
  String get path => kind == 'dm' ? '/im/dm/$id' : '/im/groups/$id';
}

class ImStore extends ChangeNotifier {
  ImStore(this.api);
  final ApiClient api;
  io.Socket? socket;
  Timer? fallback;
  bool active = true,
      connected = false,
      loading = false,
      loadingHistory = false,
      disposed = false,
      resyncing = false;
  String? error;
  Json inbox = {};
  Conversation? current;
  List<Json> messages = [];
  int page = 1, generation = 0;
  bool hasMore = false;
  Future<void> start() async {
    await refreshInbox();
    if (disposed) return;
    socket = io.io(
      siteUri.origin,
      io.OptionBuilder()
          .setPath('/api/im/ws')
          .setTransports(['websocket'])
          .setAuth({'token': api.token})
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .build(),
    );
    socket!.onConnect((_) {
      connected = true;
      _stopFallback();
      notify();
      unawaited(resync());
    });
    socket!.onDisconnect((_) {
      connected = false;
      notify();
      _startFallback();
    });
    socket!.onConnectError((_) {
      connected = false;
      notify();
      _startFallback();
    });
    for (final kind in ['dm', 'group']) {
      socket!.on('$kind:message', (raw) {
        final event = object(raw);
        final id = textOf(event[kind == 'dm' ? 'threadId' : 'groupId']);
        if (current?.kind == kind && current?.id == id) {
          merge([object(event['message'])]);
          unawaited(markRead());
        }
        unawaited(refreshInbox());
      });
      socket!.on('$kind:recall', (raw) {
        final event = object(raw);
        final patch = object(event['message']);
        if (current?.id == textOf(event[kind == 'dm' ? 'threadId' : 'groupId']))
          merge([patch]);
      });
    }
    for (final event in ['inbox:update', 'group:updated', 'redpacket:update']) {
      socket!.on(event, (_) => unawaited(refreshInbox()));
    }
    socket!.connect();
    _startFallback();
  }

  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> refreshInbox() async {
    if (!active || disposed) return;
    try {
      inbox = object(await api.get('/im/inbox'));
      error = null;
      notify();
    } catch (e) {
      error = friendlyError(e);
      notify();
    }
  }

  Future<void> resync() async {
    await refreshInbox();
    final selected = current;
    if (selected == null || disposed) return;
    if (resyncing || !active) return;
    resyncing = true;
    final stamp = generation;
    final known = messages.map((e) => textOf(e['id'])).toSet();
    try {
      var cursor = 1;
      while (true) {
        final result = object(
          await api.get('${selected.path}/messages', {'page': cursor}),
        );
        if (disposed || stamp != generation || !active) return;
        final rows = objects(result['items']);
        merge(rows);
        if (known.isEmpty ||
            rows.any((e) => known.contains(textOf(e['id']))) ||
            !messagePageHasMore(result, cursor))
          break;
        cursor++;
      }
      await markRead();
    } catch (_) {
      // The next reconnect or fallback tick reconciles the gap again.
    } finally {
      resyncing = false;
    }
  }

  void setActive(bool value) {
    active = value;
    if (value) {
      socket?.connect();
      _startFallback();
      unawaited(resync());
    } else {
      socket?.disconnect();
      _stopFallback();
    }
  }

  void _startFallback() {
    if (!active || disposed) return;
    fallback ??= Timer.periodic(const Duration(seconds: 8), (_) {
      if (!connected) unawaited(resync());
    });
  }

  void _stopFallback() {
    fallback?.cancel();
    fallback = null;
  }

  Future<void> open(Conversation conversation) async {
    final stamp = ++generation;
    current = conversation;
    messages = [];
    page = 1;
    loading = true;
    error = null;
    notify();
    try {
      final data = object(
        await api.get('${conversation.path}/messages', {'page': 1}),
      );
      if (disposed || stamp != generation) return;
      messages = mergeMessages([], objects(data['items']));
      hasMore = messagePageHasMore(data, page);
      await markRead();
      await refreshInbox();
    } catch (e) {
      if (!disposed && stamp == generation) error = friendlyError(e);
    } finally {
      if (!disposed && stamp == generation) {
        loading = false;
        notify();
      }
    }
  }

  Future<void> openUser(Member user) async {
    final result = object(
      await api.post('/im/dm/thread', {'otherId': user.id}),
    );
    if (disposed) return;
    await open(
      Conversation(
        kind: 'dm',
        id: textOf(result['threadId'] ?? result['id']),
        title: user.name,
        avatar: user.avatar,
        raw: {'peer': user.raw},
      ),
    );
  }

  Future<void> older() async {
    final c = current;
    if (c == null || loadingHistory || !hasMore) return;
    loadingHistory = true;
    notify();
    try {
      final data = object(
        await api.get('${c.path}/messages', {'page': page + 1}),
      );
      if (disposed || current?.id != c.id || current?.kind != c.kind) return;
      final rows = objects(data['items']);
      messages = mergeMessages(messages, rows);
      page++;
      hasMore = messagePageHasMore(data, page);
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loadingHistory = false;
      notify();
    }
  }

  Future<void> markRead() async {
    final c = current;
    if (c == null || !active || disposed) return;
    try {
      await api.post('${c.path}/read');
    } catch (_) {}
  }

  Future<void> send(Json body) async {
    final c = current;
    if (c == null) return;
    final message = object(await api.post('${c.path}/messages', body));
    if (disposed) return;
    if (current?.id == c.id) merge([message]);
    await refreshInbox();
  }

  void merge(List<Json> incoming) {
    messages = mergeMessages(messages, incoming);
    notify();
  }

  void close() {
    generation++;
    current = null;
    messages = [];
    error = null;
    notify();
  }

  @override
  void dispose() {
    disposed = true;
    _stopFallback();
    socket?.dispose();
    super.dispose();
  }
}

List<Json> mergeMessages(List<Json> existing, List<Json> incoming) {
  final map = <String, Json>{
    for (final m in existing)
      if (textOf(m['id']).isNotEmpty) textOf(m['id']): m,
  };
  for (final m in incoming) {
    final id = textOf(m['id']);
    if (id.isNotEmpty) map[id] = {...?map[id], ...m};
  }
  final result = map.values.toList();
  result.sort((a, b) {
    final order = textOf(a['createdAt']).compareTo(textOf(b['createdAt']));
    return order == 0 ? textOf(a['id']).compareTo(textOf(b['id'])) : order;
  });
  return result;
}

/// Uses authoritative totals when provided, and the server page size otherwise.
bool messagePageHasMore(Json data, int page) {
  final count = objects(data['items']).length;
  if (count == 0) return false;
  final size = intOf(data['pageSize']) > 0 ? intOf(data['pageSize']) : 20;
  return data['total'] is num
      ? page * size < intOf(data['total'])
      : count >= size;
}
