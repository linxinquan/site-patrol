import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 浩辰云图 CAD 接入服务。
/// 通过本地/云端 Python 代理转发请求（AppKey/Secret 保留在服务端，不暴露到浏览器）。
///
/// 默认指向本地代理 http://localhost:8800（server/ocf_server.py）；
/// 部署后可覆盖：--dart-define=CAD_HOST=http://<云服务器>:8800
class CadService {
  static const String host = String.fromEnvironment(
    'CAD_HOST',
    defaultValue: 'http://localhost:8800',
  );

  static const Duration _timeout = Duration(seconds: 90);

  /// 提交 DWG 解析任务（getDwgInfo），返回 requestId。
  /// [fileUrl] 或 [fileBase64] 二选一。
  Future<String> submitDwgInfo({
    required String fileName,
    String? fileUrl,
    String? fileBase64,
    String? notifyUrl,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/cad/dwgInfo'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fileName': fileName,
            if (fileUrl != null) 'fileUrl': fileUrl,
            if (fileBase64 != null) 'fileBase64': fileBase64,
            if (notifyUrl != null) 'notifyUrl': notifyUrl,
          }),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw Exception('CAD 解析提交失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _checkGatewayCode(data);
    return (data['bizData']?['requestId'] as String?) ?? '';
  }

  /// 提交 DWG -> OCF 转换任务，返回 requestId。
  Future<String> submitDwgToOcf({
    required String fileName,
    String? fileUrl,
    String? fileBase64,
    String? notifyUrl,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/cad/dwgToOcf'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fileName': fileName,
            if (fileUrl != null) 'fileUrl': fileUrl,
            if (fileBase64 != null) 'fileBase64': fileBase64,
            if (notifyUrl != null) 'notifyUrl': notifyUrl,
          }),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw Exception('OCF 转换提交失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _checkGatewayCode(data);
    return (data['bizData']?['requestId'] as String?) ?? '';
  }

  /// 查询异步任务状态（getTaskStatus）。
  Future<CadTaskStatus> getTaskStatus(String requestId) async {
    final resp = await http
        .get(
          Uri.parse('$host/api/cad/taskStatus?requestId=${Uri.encodeQueryComponent(requestId)}'),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw Exception('任务状态查询失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _checkGatewayCode(data);
    return CadTaskStatus.fromJson(data);
  }

  /// 提交 DWG 解析并等待完成，返回最终 DwgInfo（含图层/布局/图块）。
  /// [pollInterval] 轮询间隔，默认 2s；[maxAttempts] 最大轮询次数。
  Future<DwgInfo> fetchDwgInfo({
    required String fileName,
    String? fileUrl,
    String? fileBase64,
    Duration pollInterval = const Duration(seconds: 2),
    int maxAttempts = 60,
  }) async {
    final requestId = await submitDwgInfo(
      fileName: fileName,
      fileUrl: fileUrl,
      fileBase64: fileBase64,
    );
    if (requestId.isEmpty) {
      throw Exception('提交解析后未返回 requestId');
    }

    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(pollInterval);
      final status = await getTaskStatus(requestId);
      if (status.isDone) {
        // 重新构造带完整 bizData 的 DwgInfo
        final raw = {
          'bizData': status.bizData ?? {'requestId': requestId},
        };
        final info = DwgInfo.fromJson(raw);
        if (info.isOk) return info;
        throw Exception('图纸解析失败: ${info.resultMsg ?? status.resultMsg ?? '未知错误'}');
      }
    }
    throw Exception('图纸解析超时，请稍后重试');
  }

  /// 校验网关返回码，非成功抛异常。
  void _checkGatewayCode(Map<String, dynamic> data) {
    final code = data['rtnCode']?.toString();
    if (code != null && code != '0000000') {
      throw Exception('网关返回错误($code): ${data['msg'] ?? '未知'}');
    }
  }
}
