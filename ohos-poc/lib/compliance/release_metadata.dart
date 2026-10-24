import 'package:flutter/foundation.dart';

/// Public publisher information. Never put certificate passwords or tokens here.
abstract final class ReleaseMetadata {
  static const policyVersion = '2026-10-24.1';
  static const operatorName = String.fromEnvironment('BILI_REMOTE_OPERATOR');
  static const contactEmail = String.fromEnvironment(
    'BILI_REMOTE_CONTACT_EMAIL',
  );
  static const sourceUrl = String.fromEnvironment('BILI_REMOTE_SOURCE_URL');
  static const privacyUrl = String.fromEnvironment('BILI_REMOTE_PRIVACY_URL');
  static const termsUrl = String.fromEnvironment('BILI_REMOTE_TERMS_URL');

  static Map<String, String> get publicFields => {
    'operator': operatorName,
    'contact_email': contactEmail,
    'source_url': sourceUrl,
    'privacy_url': privacyUrl,
    'terms_url': termsUrl,
    'policy_version': policyVersion,
  };

  static List<String> publicationIssues(Map<String, String> fields) {
    final issues = <String>[];
    final operator = fields['operator']?.trim() ?? '';
    if (operator.isEmpty ||
        RegExp(
          r'待补|待填|TODO|example',
          caseSensitive: false,
        ).hasMatch(operator)) {
      issues.add('运营者名称未填写');
    }
    final email = fields['contact_email']?.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.endsWith('@example.com') ||
        email.endsWith('.invalid')) {
      issues.add('有效的公开联系邮箱未填写');
    }
    for (final item in {
      'source_url': '对应版本公开源码链接',
      'privacy_url': '公开隐私政策 HTTPS 链接',
      'terms_url': '公开用户协议 HTTPS 链接',
    }.entries) {
      final uri = Uri.tryParse(fields[item.key]?.trim() ?? '');
      final host = uri?.host.toLowerCase() ?? '';
      if (uri == null ||
          uri.scheme != 'https' ||
          host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          host == 'localhost' ||
          host == 'example.com' ||
          host.endsWith('.example.com') ||
          host.endsWith('.invalid') ||
          host.startsWith('127.') ||
          host.startsWith('192.168.') ||
          host.startsWith('10.')) {
        issues.add('${item.value}未填写或不是公开 HTTPS 地址');
      }
    }
    return issues;
  }

  static List<String> get missingPublicationFields =>
      publicationIssues(publicFields);

  static void checkReleaseConfiguration() {
    if (kReleaseMode && missingPublicationFields.isNotEmpty) {
      throw StateError('此发布包缺少必要的公开发布资料，请完成发布配置后重新构建。');
    }
  }

  static String renderDocument(String document) {
    var text = document;
    for (final field in publicFields.entries) {
      final value = field.value.trim();
      text = text.replaceAll(
        '{{${field.key}}}',
        value.isEmpty ? '未配置（开发测试版资料待补齐，不得用于正式发布）' : value,
      );
    }
    return text;
  }
}
