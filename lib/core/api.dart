import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'models.dart';

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://forum.ctspace.xyz/api',
);
final siteUri = Uri.parse(apiBase).resolve('/');
String absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('data:')) return url;
  return siteUri.resolve(url).toString();
}

class ApiClient {
  ApiClient({Dio? transport})
    : dio =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: apiBase,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 35),
              headers: {'Accept': 'application/json'},
            ),
          ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final uri = options.uri;
          final base = Uri.parse(apiBase);
          if (token != null &&
              uri.origin == base.origin &&
              uri.path.startsWith('${base.path}/')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401 &&
              !RegExp(
                r'^/auth/(login|register|activate|resend|forgot-|reset-password)',
              ).hasMatch(error.requestOptions.path) &&
              token != null) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }
  final Dio dio;
  String? token;
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, [Json? query]) =>
      request('GET', path, query: query);
  Future<dynamic> post(String path, [dynamic data]) =>
      request('POST', path, data: data ?? <String, dynamic>{});
  Future<dynamic> patch(String path, [dynamic data]) =>
      request('PATCH', path, data: data ?? <String, dynamic>{});
  Future<dynamic> delete(String path, [dynamic data]) =>
      request('DELETE', path, data: data);

  Future<dynamic> request(
    String method,
    String path, {
    dynamic data,
    Json? query,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    Json? headers,
  }) async {
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw const ApiFailure('无效的接口地址');
    }
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await dio.request<dynamic>(
          path,
          data: data,
          queryParameters: query,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          options: Options(method: method, headers: headers),
        );
        if (response.data is String &&
            !(response.headers.value('content-type') ?? '').contains('json')) {
          throw const ApiFailure('服务器返回异常，请稍后重试');
        }
        return response.data;
      } on DioException catch (error) {
        if (method == 'GET' &&
            attempt == 0 &&
            error.response == null &&
            error.type != DioExceptionType.cancel &&
            error.type != DioExceptionType.badCertificate) {
          continue;
        }
        final raw = object(error.response?.data)['message'];
        final message = raw is List ? raw.join('；') : textOf(raw);
        throw ApiFailure(
          message.isNotEmpty
              ? message
              : switch (error.type) {
                  DioExceptionType.cancel => '已取消',
                  DioExceptionType.connectionTimeout ||
                  DioExceptionType.receiveTimeout ||
                  DioExceptionType.sendTimeout =>
                    method == 'GET' ? '连接超时，请重试' : '请求超时，请先检查操作结果',
                  _ => '连接失败，请检查网络',
                },
          status: error.response?.statusCode,
          uncertain:
              method != 'GET' &&
              error.response == null &&
              error.type != DioExceptionType.cancel,
        );
      }
    }
  }

  Future<ResourceRef> upload(
    PlatformFile file, {
    String path = '/resources/upload',
    Json fields = const {},
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final part = file.path != null
        ? await MultipartFile.fromFile(
            file.path!,
            filename: 'upload${_extension(file.name)}',
          )
        : MultipartFile.fromBytes(
            await file.readAsBytes(),
            filename: 'upload${_extension(file.name)}',
          );
    final result = await request(
      'POST',
      path,
      data: FormData.fromMap({...fields, 'name': file.name, 'file': part}),
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    return ResourceRef(object(result));
  }

  Future<void> download(
    String url,
    String destination, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(absoluteUrl(url));
    if (!['https', 'http'].contains(uri.scheme)) {
      throw const ApiFailure('无效的下载地址');
    }
    final file = File(destination);
    final temporary = File('$destination.part');
    try {
      // A separate client prevents credentials from following third-party URLs.
      final client = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final base = Uri.parse(apiBase);
      await client.downloadUri(
        uri,
        temporary.path,
        options: Options(
          headers:
              token != null &&
                  uri.origin == base.origin &&
                  uri.path.startsWith('${base.path}/')
              ? {'Authorization': 'Bearer $token'}
              : null,
        ),
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(destination);
      client.close();
    } on DioException catch (e) {
      if (await temporary.exists()) await temporary.delete();
      throw ApiFailure(e.type == DioExceptionType.cancel ? '已取消' : '下载失败，请重试');
    }
  }

  String _extension(String name) =>
      name.contains('.') ? '.${name.split('.').last}' : '';
}
