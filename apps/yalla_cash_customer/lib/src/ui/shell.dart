/// Customer app shell chrome: header, bottom navigation and settings drawer.
///
/// Presentation only. Every action is a callback supplied by the shell, so
/// navigation, data refresh and account behaviour stay where they were.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// App header: the menu button at the far right (start, in RTL), the official
/// Yalla Cash logo exactly centred, and the notification bell at the far left
/// (end). Menu and bell share one 44dp style, and the two sides have equal
/// widths, so the logo stays centred whatever the name length.
///
/// With [showGreeting] (the Home tab) a compact, right-aligned greeting row
/// sits under the toolbar. Header text follows the system text size up to
/// 1.4×, so the fixed-height bar never clips.
class CustomerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomerAppBar({
    required this.firstName,
    super.key,
    this.showGreeting = true,
    this.unreadNotifications = 0,
    this.onOpenNotifications,
  });

  /// Unread inbox entries; the bell shows a small dot when above zero.
  final int unreadNotifications;

  /// Opens the notification inbox.
  final VoidCallback? onOpenNotifications;

  /// The customer's first name (empty shows the greeting word alone).
  final String firstName;

  /// Shows the greeting row under the toolbar (Home tab only).
  final bool showGreeting;

  static const double toolbarHeight = 64;
  static const double greetingHeight = 34;
  static const double buttonSize = 44;

  /// Official logo height inside the toolbar.
  static const double logoHeight = 46;

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (showGreeting ? greetingHeight : 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    // Leading and trailing areas are the same width, so the toolbar centres
    // the logo on the screen's true centre line.
    const sideWidth = YcSpace.gutter + buttonSize;
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.4),
      ),
      child: AppBar(
        toolbarHeight: toolbarHeight,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        // Status-bar icons contrast with the header in both themes.
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: sideWidth,
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(start: YcSpace.gutter),
          child: Center(
            child: Builder(
              builder: (context) => _HeaderButton(
                icon: Icons.menu_rounded,
                tooltip: 'القائمة',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ),
        ),
        // The official artwork, unaltered (fixed height, aspect preserved).
        title: const YallaCashLogo(height: logoHeight),
        actions: [
          SizedBox(
            width: sideWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: YcSpace.gutter),
              child: Center(
                child: Builder(
                  builder: (context) => _HeaderButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: unreadNotifications > 0
                        ? 'الإشعارات، $unreadNotifications غير مقروءة'
                        : 'الإشعارات',
                    // A subtle dot only when real unread notifications exist.
                    showDot: unreadNotifications > 0,
                    onPressed: onOpenNotifications ?? () {},
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: showGreeting
            ? PreferredSize(
                preferredSize: const Size.fromHeight(greetingHeight),
                child: _GreetingRow(name: firstName.trim()),
              )
            : null,
      ),
    );
  }
}

/// Matching 44dp tinted square button for the menu and the bell.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Small unread dot at the icon's top corner (no number).
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget glyph = showDot
        ? Badge(
            key: const Key('notifications-unread-dot'),
            smallSize: 8,
            backgroundColor: YallaColors.danger,
            child: Icon(icon),
          )
        : Icon(icon);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(
          CustomerAppBar.buttonSize,
          CustomerAppBar.buttonSize,
        ),
        backgroundColor: scheme.primary.withValues(alpha: .10),
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YcRadius.sm),
        ),
      ),
      icon: glyph,
    );
  }
}

/// "مرحباً" and the first name on one compact, right-aligned line.
class _GreetingRow extends StatelessWidget {
  const _GreetingRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(YcSpace.gutter, 0, YcSpace.gutter, 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: MergeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('مرحباً', style: YcType.meta(context)),
              if (name.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

/// Bottom navigation for the four customer tabs, in order:
/// الرئيسية، كودي، المحفظة، المتجر.
///
/// A flat surface with a hairline top border and a quiet indicator. Selection
/// animates with the framework's indicator plus a small icon settle; both
/// run instantly under reduced motion. The page stack itself lives in the
/// shell, so tab state is untouched by this widget.
class CustomerNavBar extends StatelessWidget {
  const CustomerNavBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final surface = YcSurface.of(context);
    final labelStyle = theme.textTheme.labelMedium;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.card,
        border: Border(top: BorderSide(color: surface.hairline)),
      ),
      child: NavigationBarTheme(
        data: theme.navigationBarTheme.copyWith(
          height: 68,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: scheme.primary.withValues(alpha: dark ? .18 : .11),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YcRadius.md),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => labelStyle?.copyWith(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: YcMotion.resolve(context, YcMotion.medium),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon:
                  _NavIcon(Icons.home_rounded, active: selectedIndex == 0),
              label: 'الرئيسية',
            ),
            // A single icon: the selected colour and indicator mark it.
            const NavigationDestination(
              icon: Icon(Icons.qr_code_2_rounded),
              label: 'كودي',
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: _NavIcon(
                Icons.account_balance_wallet_rounded,
                active: selectedIndex == 2,
              ),
              label: 'المحفظة',
            ),
            NavigationDestination(
              icon: const Icon(Icons.redeem_outlined),
              selectedIcon:
                  _NavIcon(Icons.redeem_rounded, active: selectedIndex == 3),
              label: 'المتجر',
            ),
          ],
        ),
      ),
    );
  }
}

/// Filled selected icon that settles from 90% to 100% when it becomes active.
class _NavIcon extends StatelessWidget {
  const _NavIcon(this.icon, {required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: active ? 1 : .9,
        duration: YcMotion.resolve(context, YcMotion.fast),
        curve: YcMotion.standard,
        child: Icon(icon),
      );
}

// ---------------------------------------------------------------------------
// Settings drawer
// ---------------------------------------------------------------------------

/// Settings drawer in three restrained groups: preferences, support and
/// sharing, and the account. It keeps the framework's drawer behaviour (edge
/// swipe, scrim, back button) and only restyles its content. Every action is
/// a callback owned by the shell.
class CustomerDrawer extends StatelessWidget {
  const CustomerDrawer({
    required this.governorateName,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onChangeGovernorate,
    required this.onContact,
    required this.onRate,
    required this.onInvite,
    required this.onLogout,
    super.key,
  });

  final String governorateName;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onChangeGovernorate;
  final VoidCallback onContact;
  final VoidCallback onRate;
  final VoidCallback onInvite;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final danger = YcToneColors.of(context, YcTone.danger).foreground;
    Widget chevron() =>
        Icon(Icons.chevron_left_rounded, size: 20, color: scheme.outline);
    return Drawer(
      // Page-coloured panel so the white cards read as raised groups.
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            YcSpace.md,
            YcSpace.md,
            YcSpace.md,
            YcSpace.xl,
          ),
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
              child: Row(
                children: [
                  const YcIconBadge(
                    Icons.person_outline_rounded,
                    size: 48,
                    circle: true,
                  ),
                  const SizedBox(width: YcSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'إعدادات الحساب',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YcType.item(context),
                          ),
                        ),
                        Text(
                          'اللغة، المظهر والتواصل',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: YcType.meta(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _GroupLabel('التفضيلات'),
            _Group(children: [
              YcListRow(
                icon: Icons.location_on_outlined,
                title: 'تغيير المحافظة',
                subtitle: governorateName,
                trailing: chevron(),
                onTap: onChangeGovernorate,
              ),
              YcListRow(
                icon: Icons.dark_mode_outlined,
                title: 'الوضع الداكن',
                trailing: Switch(
                  value: darkMode,
                  onChanged: onDarkModeChanged,
                ),
                onTap: () => onDarkModeChanged(!darkMode),
              ),
              YcListRow(
                icon: Icons.language_rounded,
                title: 'اللغة',
                trailing: Text(
                  'العربية',
                  style: YcType.meta(context)?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ]),
            const _GroupLabel('الدعم والمشاركة'),
            _Group(children: [
              YcListRow(
                icon: Icons.message_outlined,
                title: 'تواصل معنا',
                trailing: chevron(),
                onTap: onContact,
              ),
              YcListRow(
                icon: Icons.star_outline_rounded,
                iconTone: YcTone.warning,
                title: 'قيّم التطبيق',
                trailing: chevron(),
                onTap: onRate,
              ),
              YcListRow(
                icon: Icons.card_giftcard_rounded,
                title: 'ادعُ أصدقاءك واربح نقاط',
                titleMaxLines: 2,
                trailing: chevron(),
                onTap: onInvite,
              ),
            ]),
            const _GroupLabel('الحساب'),
            _Group(children: [
              YcListRow(
                icon: Icons.logout_rounded,
                iconTone: YcTone.danger,
                title: 'تسجيل الخروج',
                titleColor: danger,
                onTap: onLogout,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Small group heading inside the drawer.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          4,
          YcSpace.lg,
          4,
          YcSpace.xs,
        ),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: YcType.meta(context)?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      );
}

/// A [YcCard] of rows separated by hairline dividers inset past the icons.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  /// Row padding + badge (40) + gap, so dividers start under the text.
  static const double _dividerIndent = YcSpace.md + 40 + YcSpace.sm;

  @override
  Widget build(BuildContext context) {
    final hairline = YcSurface.of(context).hairline;
    return YcCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: _dividerIndent,
                color: hairline,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
