import 'dart:async';

import 'package:flutter/material.dart' hide Banner;
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
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
      builder: (_) => CustomerNotificationDetailPage(notification: notification),
    )));
    if (!await marking && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تحديث حالة الإشعار. سيبقى غير مقروء.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<CustomerAppState>(
        stream: widget.cubit.stream,
        initialData: widget.cubit.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? widget.cubit.state;
          return RefreshIndicator(
            onRefresh: widget.cubit.loadNotifications,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                YcSpace.gutter,
                YcSpace.md,
                YcSpace.gutter,
                YcSpace.xl,
              ),
              children: _content(state),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(CustomerAppState state) {
    final items = state.notifications;
    final status = state.notificationsStatus;
    if (items.isEmpty) {
      return [
        switch (status) {
          LoadStatus.initial ||
          LoadStatus.loading =>
            const _InboxLoading(key: ValueKey('inbox-loading')),
          LoadStatus.failure => YcCard(
              key: const ValueKey('inbox-error'),
              child: YcEmptyState(
                icon: Icons.wifi_off_rounded,
                tone: YcTone.danger,
                title: 'تعذر تحميل الإشعارات',
                description: state.notificationsFailure?.message ??
                    'تحقق من اتصالك ثم حاول مجدداً.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => unawaited(widget.cubit.loadNotifications()),
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
    return [
      if (status == LoadStatus.loading)
        const Padding(
          padding: EdgeInsets.only(bottom: YcSpace.sm),
          child: LinearProgressIndicator(),
        ),
      if (status == LoadStatus.failure)
        Padding(
          padding: const EdgeInsets.only(bottom: YcSpace.sm),
          child: Row(children: [
            Expanded(
              child: Text('تعذر تحديث الإشعارات.',
                  style: YcType.meta(context)),
            ),
            TextButton(
              onPressed: () => unawaited(widget.cubit.loadNotifications()),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
      for (final notification in items)
        Padding(
          padding: const EdgeInsets.only(bottom: YcSpace.sm),
          child: _NotificationTile(
            key: ValueKey(notification.id),
            notification: notification,
            onTap: () => _open(notification),
          ),
        ),
    ];
  }
}

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
    return Semantics(
      button: true,
      label: 'إشعار غير مقروء',
      child: YcCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YcIconBadge(Icons.notifications_active_outlined,
                tone: YcTone.brand, size: 44, circle: true),
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
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: YcSpace.xs),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
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

/// Static placeholders while the inbox loads (calm with reduced motion).
class _InboxLoading extends StatelessWidget {
  const _InboxLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final block =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .10);
    Widget bar(double? width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Semantics(
      container: true,
      label: 'جارٍ تحميل الإشعارات',
      child: ExcludeSemantics(
        child: Column(children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: YcSpace.sm),
              child: YcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(140, 14),
                    const SizedBox(height: 10),
                    bar(double.infinity, 12),
                    const SizedBox(height: 8),
                    bar(90, 10),
                  ],
                ),
              ),
            ),
        ]),
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
                    fontWeight: FontWeight.w900,
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
