typedef Json = Map<String, dynamic>;

Json object(dynamic value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
List<Json> objects(dynamic value) =>
    value is List ? value.whereType<Map>().map(object).toList() : <Json>[];
String textOf(dynamic value, [String fallback = '']) =>
    value == null ? fallback : value.toString();
int intOf(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
bool boolOf(dynamic value) => value == true || value == 1 || value == 'true';

class PageResult<T> {
  const PageResult(
    this.items, {
    this.total = 0,
    this.page = 1,
    this.pageSize = 24,
  });
  final List<T> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
  factory PageResult.fromJson(
    dynamic json,
    T Function(Json) decode, {
    int page = 1,
    int pageSize = 24,
  }) {
    final map = object(json);
    final items = objects(json is List ? json : map['items']);
    return PageResult(
      items.map(decode).toList(),
      total: json is List ? items.length : intOf(map['total']),
      page: intOf(map['page']) == 0 ? page : intOf(map['page']),
      pageSize: intOf(map['pageSize']) == 0 ? pageSize : intOf(map['pageSize']),
    );
  }
}

class Member {
  Member(this.raw);
  final Json raw;
  String get id => textOf(raw['id']);
  String get username => textOf(raw['username']);
  String get name => textOf(raw['nickname']).trim().isNotEmpty
      ? textOf(raw['nickname'])
      : username;
  String get avatar => textOf(raw['avatar']);
  String get signature => textOf(raw['signature'] ?? raw['bio']);
  String get role => textOf(raw['role']);
  int get points => intOf(raw['points']);
  int get level => intOf(raw['level']);
}

enum ContentKind { discussion, project, extension }

class ContentItem {
  ContentItem(this.raw, this.kind);
  final Json raw;
  final ContentKind kind;
  String get id => textOf(raw['id']);
  String get title => textOf(raw['title']);
  String get summary => textOf(raw['summary'] ?? raw['content']);
  Member get author => Member(object(raw['author']));
  String get cover => textOf(object(raw['cover'])['url'] ?? raw['coverUrl']);
  int get views => intOf(raw['views']);
  int get likes => intOf(raw['likeCount']);
  int get replies =>
      intOf(raw['postCount'] ?? object(raw['_count'])['comments']);
  String get createdAt => textOf(raw['createdAt']);
  bool get pinned => boolOf(raw['isPinned']);
  bool get locked => boolOf(raw['isLocked']);
  List<Json> get tags => objects(
    raw['tags'],
  ).map((e) => e.containsKey('tag') ? object(e['tag']) : e).toList();
}

class ResourceRef {
  ResourceRef(Json json)
    : id = textOf(json['id']),
      url = textOf(json['url']),
      filename = textOf(json['filename']),
      size = intOf(json['size']);
  final String id, url, filename;
  final int size;
}

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status, this.uncertain = false});
  final String message;
  final int? status;
  final bool uncertain;
  @override
  String toString() => message;
}

String friendlyError(Object error) =>
    error is ApiFailure ? error.message : '暂时无法完成，请稍后重试';

String compactNumber(dynamic value) {
  final n = intOf(value);
  return n >= 10000 ? '${(n / 10000).toStringAsFixed(1)}万' : '$n';
}

String fileSize(dynamic value) {
  final n = intOf(value);
  if (n >= 1073741824) return '${(n / 1073741824).toStringAsFixed(1)} GB';
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '$n B';
}

String relativeTime(dynamic value) {
  final date = DateTime.tryParse(textOf(value));
  if (date == null) return '';
  final delta = DateTime.now().difference(date);
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  if (delta.inDays < 7) return '${delta.inDays} 天前';
  final local = date.toLocal();
  return '${local.year}/${local.month}/${local.day}';
}
