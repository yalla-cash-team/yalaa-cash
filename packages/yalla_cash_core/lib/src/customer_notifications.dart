import 'package:equatable/equatable.dart';
import 'package:yalla_cash_core/src/core/failure.dart';

/// Push `data.type` of an admin broadcast; `data.broadcastId` identifies it.
const broadcastPushType = 'broadcast';

/// The broadcast id carried by a tapped push's data, or null when the push
/// is not an admin broadcast.
String? broadcastIdFromPushData(Map<String, Object?> data) {
  final id = data['broadcastId'];
  return data['type'] == broadcastPushType && id is String && id.isNotEmpty
      ? id
      : null;
}

/// One entry of the signed-in customer's notification inbox
/// (`GET /customer/notifications`). Only the owner can read or mark it.
class CustomerNotification extends Equatable {
  const CustomerNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.broadcastId,
    this.readAt,
  });

  factory CustomerNotification.fromJson(Map<String, Object?> json) {
    String text(String key) {
      final value = json[key];
      if (value is String) return value;
      throw YallaCashFailure(
        code: 'invalid_response',
        message: 'استجابة الخادم غير متوقعة.',
        details: 'CustomerNotification.$key',
      );
    }

    final readAt = json['readAt'];
    return CustomerNotification(
      id: text('id'),
      broadcastId: json['broadcastId'] as String?,
      title: text('title'),
      body: text('body'),
      createdAt: DateTime.parse(text('createdAt')).toUtc(),
      readAt: readAt is String ? DateTime.parse(readAt).toUtc() : null,
    );
  }

  final String id;

  /// The admin broadcast it came from (matches a tapped push's data).
  final String? broadcastId;
  final String title;
  final String body;
  final DateTime createdAt;

  /// Null while unread.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  CustomerNotification markedRead(DateTime at) => CustomerNotification(
        id: id,
        broadcastId: broadcastId,
        title: title,
        body: body,
        createdAt: createdAt,
        readAt: at,
      );

  @override
  List<Object?> get props => [id, broadcastId, title, body, createdAt, readAt];
}

/// A page of the inbox plus the customer's total unread count.
class CustomerNotificationInbox {
  const CustomerNotificationInbox({
    required this.items,
    required this.unreadCount,
  });

  final List<CustomerNotification> items;
  final int unreadCount;
}

/// Result of marking one notification read: it, plus the new unread count.
class CustomerNotificationReadResult {
  const CustomerNotificationReadResult({
    required this.notification,
    required this.unreadCount,
  });

  final CustomerNotification notification;
  final int unreadCount;
}
