import 'dart:async';

import 'package:flutter/material.dart' hide Banner;
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

/// "الآن", "قبل 5 دقيقة", "قبل 3 ساعة", else the local date.
String formatNotificationTime(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final diff = (now ?? DateTime.now()).difference(local);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  return '${local.day}/${local.month}/${local.year}';
}

/// The customer's real notification inbox: unread notifications, newest
/// first. Opening this screen marks nothing as read; tapping one notification
/// opens it, removes it from the list at once and marks only it as read.
class CustomerNotificationsPage extends StatefulWidget {
  const CustomerNotificationsPage({required this.cubit, super.key});

  final CustomerAppCubit cubit;

  @override
  State<CustomerNotificationsPage> createState() =>
      _CustomerNotificationsPageState();
}

class _CustomerNotificationsPageState extends State<CustomerNotificationsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.cubit.loadNotifications());
  }

  Future<void> _open(CustomerNotification notification) async {
    final marking = widget.cubit.openNotification(notification);
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          CustomerNotificationDetailPage(notification: notification),
    )));
    if (!await marking && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تحديث حالة الإشعار. سيبقى غير مقروء.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<CustomerAppState>(
        stream: widget.cubit.stream,
        initialData: widget.cubit.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? widget.cubit.state;
          final entries = _content(state);
          return RefreshIndicator(
            onRefresh: widget.cubit.loadNotifications,
            // Built lazily: only the visible entries are laid out.
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                YcSpace.gutter,
                YcSpace.md,
                YcSpace.gutter,
                YcSpace.xl,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index](context),
            ),
          );
        },
      ),
    );
  }

  /// The inbox as a flat list of lazily built entries: day headings and
  /// notification cards, newest first.
  List<WidgetBuilder> _content(CustomerAppState state) {
    final items = state.notifications;
    final status = state.notificationsStatus;
    void retry() => unawaited(widget.cubit.loadNotifications());
    if (items.isEmpty) {
      return [
        (_) => switch (status) {
              LoadStatus.initial || LoadStatus.loading => const YcSkeleton.card(
                  key: ValueKey('inbox-loading'),
                  rows: 2,
                  label: 'جارٍ تحميل الإشعارات',
                ),
              LoadStatus.failure => YcCard(
                  key: const ValueKey('inbox-error'),
                  child: YcErrorState(
                    icon: Icons.wifi_off_rounded,
                    title: 'تعذر تحميل الإشعارات',
                    description:
                        inboxFailureMessage(state.notificationsFailure),
                    onRetry: retry,
                  ),
                ),
              _ => const YcCard(
                  key: ValueKey('inbox-empty'),
                  child: YcEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'لا توجد إشعارات جديدة',
                    description: 'ستظهر هنا إشعارات يلا كاش الجديدة.',
                  ),
                ),
            },
      ];
    }
    final now = DateTime.now();
    final entries = <WidgetBuilder>[
      if (status == LoadStatus.loading)
        (_) => const Padding(
              padding: EdgeInsets.only(bottom: YcSpace.sm),
              child: LinearProgressIndicator(),
            ),
      if (status == LoadStatus.failure)
        (_) => Padding(
              padding: const EdgeInsets.only(bottom: YcSpace.sm),
              child: YcInlineBanner(
                message: 'تعذر تحديث الإشعارات.',
                tone: YcTone.danger,
                actionLabel: 'إعادة المحاولة',
                onAction: retry,
              ),
            ),
    ];
    String? lastDay;
    for (final notification in items) {
      final day = notificationDayLabel(notification.createdAt, now: now);
      if (day != lastDay) {
        lastDay = day;
        entries.add((_) => _DayHeading(day));
      }
      entries.add((_) => Padding(
            padding: const EdgeInsets.only(bottom: YcSpace.sm),
            child: _NotificationTile(
              key: ValueKey(notification.id),
              notification: notification,
              onTap: () => _open(notification),
            ),
          ));
    }
    return entries;
  }
}

/// Levantine month names, as used in Syria.
const _inboxMonths = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// Day heading for a notification: "اليوم", "أمس", or the local date
/// ("12 تشرين الثاني 2026").
String notificationDayLabel(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = now ?? DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final current = DateTime(today.year, today.month, today.day);
  final days = current.difference(day).inDays;
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  return '${local.day} ${_inboxMonths[local.month - 1]} ${local.year}';
}

/// Friendly Arabic copy for an inbox load failure. Server text is never
/// shown as-is (it may be technical or not in Arabic).
String inboxFailureMessage(YallaCashFailure? failure) {
  if (failure != null &&
      (failure.statusCode == 401 || failure.code == 'unauthorized')) {
    return 'انتهت الجلسة. سجّل الدخول مرة أخرى.';
  }
  if (failure?.code == 'network_error') {
    return 'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجدداً.';
  }
  return 'تحقق من اتصالك ثم حاول مجدداً.';
}

/// Quiet day heading between groups of notifications.
class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, YcSpace.xs),
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: YcType.meta(context)?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
}

/// One notification card. The unread dot, bold title and "غير مقروء"
/// announcement appear only when the notification really is unread
/// ([CustomerNotification.isRead] is false).
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    super.key,
  });

  final CustomerNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = YcColors.of(context);
    final unread = !notification.isRead;
    return Semantics(
      button: true,
      label: unread ? 'إشعار غير مقروء' : 'إشعار',
      child: YcCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YcIconBadge(
              unread
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_rounded,
              tone: unread ? YcTone.brand : YcTone.neutral,
              size: 44,
              circle: true,
            ),
            const SizedBox(width: YcSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w400,
                          color: colors.ink,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (unread) ...[
                      const SizedBox(width: YcSpace.xs),
                      Container(
                        key: const Key('notification-unread-dot'),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: YcType.body(context)?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(formatNotificationTime(notification.createdAt),
                      style: YcType.meta(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full content of one notification.
class CustomerNotificationDetailPage extends StatelessWidget {
  const CustomerNotificationDetailPage({required this.notification, super.key});

  final CustomerNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعار'),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          YcSpace.gutter,
          YcSpace.md,
          YcSpace.gutter,
          YcSpace.xl,
        ),
        children: [
          YcCard(
            padding: const EdgeInsets.all(YcSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(formatNotificationTime(notification.createdAt),
                    style: YcType.meta(context)),
                const SizedBox(height: YcSpace.md),
                SelectableText(
                  notification.body,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
