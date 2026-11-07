import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;

/// Admin management of one exclusive store's view-only offers.
///
/// Data comes from the shared core: [AdminAppCubit.loadStoreOffers] and the
/// offer operations, which keep their own per-store status. Calendar dates
/// are Asia/Damascus days entered as plain dates, never converted through
/// the device time zone. Images load through the authenticated admin
/// preview, never as plain network images.

/// Largest offer image accepted; the backend enforces the same limit.
const int maxOfferImageBytes = 300 * 1024;

typedef OfferImagePick = ({StoreLogoUpload? image, String? error});
typedef OfferImagePicker = Future<OfferImagePick> Function();

/// PNG, JPEG or WebP, detected from the file signature (the backend checks
/// the signature too, so a renamed file is rejected early here).
String? offerImageTypeOf(List<int> bytes) {
  bool has(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (has(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (has(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (has(const [0x52, 0x49, 0x46, 0x46]) &&
      has(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}

/// Turns picked bytes into an upload, or an Arabic error message.
OfferImagePick validateOfferImage(List<int> bytes) {
  if (bytes.isEmpty) return (image: null, error: 'الملف فارغ.');
  if (bytes.length > maxOfferImageBytes) {
    return (image: null, error: 'حجم الصورة يجب ألا يتجاوز 300 KB.');
  }
  final type = offerImageTypeOf(bytes);
  if (type == null) {
    return (image: null, error: 'الصيغ المسموحة: PNG أو JPEG أو WebP.');
  }
  return (image: StoreLogoUpload(bytes: bytes, contentType: type), error: null);
}

Future<OfferImagePick> pickOfferImageFile() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    withData: true,
  );
  final bytes = picked?.files.firstOrNull?.bytes;
  if (bytes == null) return (image: null, error: null);
  return validateOfferImage(bytes);
}

/// Null when the window is valid. The end date is the last included day.
String? offerWindowError(OfferCalendarDate? start, OfferCalendarDate? end) =>
    start != null && end != null && end.compareTo(start) < 0
        ? 'تاريخ النهاية يجب ألا يسبق تاريخ البداية.'
        : null;

String offerStatusLabel(OfferStatus status) => switch (status) {
      OfferStatus.active => 'نشط',
      OfferStatus.scheduled => 'مجدول',
      OfferStatus.expired => 'منتهي',
      OfferStatus.inactive => 'متوقف',
    };

/// The status computed by the server at load time (lists reload after every
/// change), falling back to the same rule on the device clock.
OfferStatus _statusOf(StoreOffer offer) =>
    offer.serverStatus ?? offer.statusAt(DateTime.now());

String _windowText(StoreOffer offer) {
  final start = offer.startDate;
  final end = offer.endDate;
  if (start == null && end == null) return 'بدون تاريخ محدد';
  if (start == null) return 'حتى $end';
  if (end == null) return 'من $start';
  if (start == end) return 'يوم $start فقط';
  return 'من $start إلى $end';
}

class StoreOffersAdminPage extends StatefulWidget {
  const StoreOffersAdminPage({
    required this.cubit,
    required this.repository,
    required this.store,
    this.pickImage = pickOfferImageFile,
    super.key,
  });

  final AdminAppCubit cubit;
  final YallaCashRepository repository;
  final PartnerStore store;
  final OfferImagePicker pickImage;

  @override
  State<StoreOffersAdminPage> createState() => _StoreOffersAdminPageState();
}

class _StoreOffersAdminPageState extends State<StoreOffersAdminPage> {
  /// Offers with an action in flight; their buttons are disabled so a
  /// double tap can never send the same request twice.
  final Set<String> _busy = {};

  String get _storeId => widget.store.id;

  @override
  void initState() {
    super.initState();
    unawaited(widget.cubit.loadStoreOffers(_storeId));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AdminAppState>(
        stream: widget.cubit.stream,
        initialData: widget.cubit.state,
        builder: (context, snapshot) {
          final offers =
              (snapshot.data ?? widget.cubit.state).offersFor(_storeId);
          return Scaffold(
            appBar: AppBar(
              title: Text('عروض ${widget.store.name}'),
              actions: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: FilledButton.icon(
                    // The app theme makes filled buttons full-width; the app
                    // bar's action row has no width limit.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة عرض'),
                  ),
                ),
              ],
            ),
            body: _body(context, offers),
          );
        },
      );

  Widget _body(BuildContext context, StoreOffersState state) {
    final offers = state.offers;
    if (offers.isEmpty) {
      return switch (state.status) {
        LoadStatus.initial || LoadStatus.loading => const Center(
            child: CircularProgressIndicator(key: Key('offers-loading'))),
        LoadStatus.failure => _OffersMessage(
            icon: Icons.cloud_off_rounded,
            title: 'تعذر تحميل العروض',
            text: state.failure?.message ?? 'حدث خطأ غير متوقع.',
            action: FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ),
        _ => _OffersMessage(
            icon: Icons.local_offer_outlined,
            title: 'لا توجد عروض لهذا المحل بعد',
            text: 'أضف عرضاً ليظهر للعملاء في صفحة المحل.',
            action: FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة أول عرض'),
            ),
          ),
      };
    }

    final counts = <OfferStatus, int>{};
    for (final offer in offers) {
      counts.update(_statusOf(offer), (n) => n + 1, ifAbsent: () => 1);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (state.status == LoadStatus.failure)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.error_outline_rounded),
                          title: Text(state.failure?.message ??
                              'تعذر تحديث العروض.'),
                          trailing: TextButton(
                            onPressed: _reload,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${offers.length} عروض',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      for (final status in OfferStatus.values)
                        if (counts[status] case final count?)
                          OfferStatusChip(status: status, count: count),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth >= 900
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth >= 560
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final offer in offers)
                          SizedBox(
                            width: width,
                            child: _OfferCard(
                              key: ValueKey(offer.id),
                              cubit: widget.cubit,
                              offer: offer,
                              busy: _busy.contains(offer.id),
                              onEdit: () => _openEditor(offer),
                              onToggle: () => _toggle(offer),
                              onDelete: () => _delete(offer),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() => widget.cubit.loadStoreOffers(_storeId);

  Future<void> _openEditor([StoreOffer? offer]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfferEditorDialog(
        cubit: widget.cubit,
        repository: widget.repository,
        storeId: _storeId,
        offer: offer,
        pickImage: widget.pickImage,
      ),
    );
    if (saved == true && mounted) {
      _snack(offer == null ? 'تمت إضافة العرض.' : 'تم حفظ التعديلات.');
    }
  }

  Future<void> _toggle(StoreOffer offer) => _runFor(
        offer,
        () => widget.cubit.updateOffer(
          offer,
          StoreOfferUpdate(isActive: !offer.isActive),
        ),
        offer.isActive ? 'تعذر إيقاف العرض.' : 'تعذر تفعيل العرض.',
      );

  Future<void> _delete(StoreOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف العرض'),
        content: Text(
            'هل أنت متأكد من حذف العرض "${offer.title}"؟ لا يمكن التراجع عن الحذف.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف العرض')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runFor(
      offer,
      () => widget.cubit.deleteOffer(offer),
      'تعذر حذف العرض.',
    );
  }

  Future<void> _runFor(
    StoreOffer offer,
    Future<bool> Function() action,
    String fallbackError,
  ) async {
    if (_busy.contains(offer.id)) return;
    setState(() => _busy.add(offer.id));
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy.remove(offer.id));
    if (!ok) {
      final message =
          widget.cubit.state.offersFor(_storeId).operationFailure?.message;
      _snack(message == null || message.isEmpty ? fallbackError : message);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class OfferStatusChip extends StatelessWidget {
  const OfferStatusChip({required this.status, this.count, super.key});

  final OfferStatus status;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      OfferStatus.active => YallaColors.success,
      OfferStatus.scheduled => YallaColors.primaryStrong,
      OfferStatus.expired => YallaColors.gold,
      OfferStatus.inactive => scheme.onSurfaceVariant,
    };
    final label = offerStatusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        count == null ? label : '$label $count',
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.cubit,
    required this.offer,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final AdminAppCubit cubit;
  final StoreOffer offer;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: AdminOfferImage(cubit: cubit, offer: offer),
              ),
              PositionedDirectional(
                top: 10,
                start: 10,
                child: OfferStatusChip(status: _statusOf(offer)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(offer.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  if (offer.discountLabel case final label?) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: YallaColors.gold.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF9A6A12))),
                    ),
                  ],
                ]),
                if (offer.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(offer.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.event_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(_windowText(offer),
                          style: theme.textTheme.bodySmall)),
                  Text('الترتيب ${offer.displayOrder ?? 0}',
                      style: theme.textTheme.bodySmall),
                ]),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              TextButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onToggle,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        offer.isActive
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 18),
                label: Text(offer.isActive ? 'إيقاف' : 'تفعيل'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'حذف العرض',
                onPressed: busy ? null : onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// An offer image loaded through the authenticated admin preview endpoint
/// ([AdminAppCubit.loadOfferImage]: bearer token in the header, bytes kept
/// in memory only). Never a plain network image.
class AdminOfferImage extends StatefulWidget {
  const AdminOfferImage({required this.cubit, required this.offer, super.key});

  final AdminAppCubit cubit;
  final StoreOffer offer;

  @override
  State<AdminOfferImage> createState() => _AdminOfferImageState();
}

class _AdminOfferImageState extends State<AdminOfferImage> {
  late Future<OfferImageData?> _image = _load();

  Future<OfferImageData?> _load() => widget.cubit.loadOfferImage(widget.offer);

  @override
  void didUpdateWidget(AdminOfferImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.id != widget.offer.id ||
        oldWidget.offer.imageVersion != widget.offer.imageVersion ||
        oldWidget.offer.hasImage != widget.offer.hasImage) {
      _image = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Icon(Icons.local_offer_outlined,
          size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    return FutureBuilder<OfferImageData?>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snapshot.hasError) {
          return Center(
            child: IconButton(
              tooltip: 'تعذر تحميل الصورة، اضغط لإعادة المحاولة',
              icon: const Icon(Icons.broken_image_outlined),
              onPressed: () => setState(() => _image = _load()),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return placeholder;
        return Image.memory(
          data.bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder,
        );
      },
    );
  }
}

/// Create/edit form. It performs the save itself so it can stay open (with
/// the admin's input) on failure, and it ignores repeated taps while saving.
///
/// Creating happens in two steps, because the server assigns the offer id:
/// create the offer, then upload its image. If the upload fails, the offer
/// already exists, so the form switches to editing that offer. Saving again
/// then retries only the image and never creates a duplicate.
class OfferEditorDialog extends StatefulWidget {
  const OfferEditorDialog({
    required this.cubit,
    required this.repository,
    required this.storeId,
    required this.pickImage,
    this.offer,
    super.key,
  });

  final AdminAppCubit cubit;
  final YallaCashRepository repository;
  final String storeId;
  final StoreOffer? offer;
  final OfferImagePicker pickImage;

  @override
  State<OfferEditorDialog> createState() => _OfferEditorDialogState();
}

class _OfferEditorDialogState extends State<OfferEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.offer?.title);
  late final _description =
      TextEditingController(text: widget.offer?.description);
  late final _label = TextEditingController(text: widget.offer?.discountLabel);
  late final _order =
      TextEditingController(text: '${widget.offer?.displayOrder ?? 0}');
  late OfferCalendarDate? _startDate = widget.offer?.startDate;
  late OfferCalendarDate? _endDate = widget.offer?.endDate;
  late bool _isActive = widget.offer?.isActive ?? true;

  /// The offer being edited: null until a new offer has been created.
  late StoreOffer? _saved = widget.offer;
  StoreLogoUpload? _pendingImage;
  bool _removeImage = false;
  String? _imageError;
  String? _dateError;
  String? _saveError;
  bool _saving = false;

  bool get _hasImage =>
      _pendingImage != null || (!_removeImage && (_saved?.hasImage ?? false));

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _label.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await widget.pickImage();
    if (!mounted) return;
    if (picked.image == null && picked.error == null) return; // cancelled
    setState(() {
      _imageError = picked.error;
      if (picked.image != null) {
        _pendingImage = picked.image;
        _removeImage = false;
      }
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startDate : _endDate;
    final fallback = start ? _endDate : _startDate;
    final initial = current ?? fallback;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // A plain calendar day for the picker UI only; no time zone involved.
      initialDate: initial == null
          ? DateTime(now.year, now.month, now.day)
          : DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: start ? 'تاريخ البداية' : 'تاريخ النهاية (مشمول)',
    );
    if (picked == null || !mounted) return;
    final day = OfferCalendarDate(picked.year, picked.month, picked.day);
    setState(() {
      if (start) {
        _startDate = day;
      } else {
        _endDate = day;
      }
      _dateError = offerWindowError(_startDate, _endDate);
    });
  }

  String? _optional(String text) {
    final value = text.trim();
    return value.isEmpty ? null : value;
  }

  StoreOfferDraft _draft() => StoreOfferDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        discountLabel: _optional(_label.text),
        startDate: _startDate,
        endDate: _endDate,
        isActive: _isActive,
        displayOrder: int.parse(_order.text.trim()),
      );

  /// Only the fields that differ from [offer] are sent.
  StoreOfferUpdate _changesFrom(StoreOffer offer) {
    final draft = _draft();
    OfferFieldUpdate<T>? field<T extends Object>(T? before, T? after) =>
        before == after
            ? null
            : after == null
                ? OfferFieldUpdate<T>.clear()
                : OfferFieldUpdate<T>.set(after);
    return StoreOfferUpdate(
      title: draft.title == offer.title ? null : draft.title,
      description: draft.description == offer.description
          ? null
          : OfferFieldUpdate.set(draft.description),
      discountLabel: field(offer.discountLabel, draft.discountLabel),
      startDate: field(offer.startDate, draft.startDate),
      endDate: field(offer.endDate, draft.endDate),
      isActive: draft.isActive == offer.isActive ? null : draft.isActive,
      displayOrder:
          draft.displayOrder == offer.displayOrder ? null : draft.displayOrder,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final dateError = offerWindowError(_startDate, _endDate);
    final valid = _form.currentState!.validate();
    setState(() => _dateError = dateError);
    if (!valid || dateError != null) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    var existing = _saved;
    if (existing == null) {
      try {
        existing = await widget.repository.createOffer(widget.storeId, _draft());
      } on Object catch (error) {
        // Nothing was created: saving again is safe.
        _failed(error is YallaCashFailure ? error.message : null,
            'تعذر إنشاء العرض.');
        unawaited(widget.cubit.loadStoreOffers(widget.storeId));
        return;
      }
      _saved = existing;
      if (_pendingImage == null) {
        await widget.cubit.loadStoreOffers(widget.storeId);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final ok = await widget.cubit.updateOffer(
        existing,
        const StoreOfferUpdate(),
        image: _pendingImage,
      );
      if (ok) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      _failed(
        _operationError(),
        'تعذر رفع الصورة.',
        prefix: 'تم إنشاء العرض، لكن تعذر رفع الصورة: ',
        suffix: ' يمكنك إعادة المحاولة أو الحفظ بدون صورة.',
      );
      return;
    }

    final ok = await widget.cubit.updateOffer(
      existing,
      _changesFrom(existing),
      image: _pendingImage,
      removeImage: _removeImage && _pendingImage == null,
    );
    if (ok) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    _failed(_operationError(), 'تعذر حفظ العرض.');
  }

  String? _operationError() =>
      widget.cubit.state.offersFor(widget.storeId).operationFailure?.message;

  void _failed(
    String? message,
    String fallback, {
    String prefix = '',
    String suffix = '',
  }) {
    if (!mounted) return;
    // Re-read the offer: part of the change may have been applied (for
    // example the fields but not the image), so a retry sends only the rest.
    final saved = _saved;
    final fresh = saved == null
        ? null
        : widget.cubit.state
            .offersFor(widget.storeId)
            .offers
            .where((offer) => offer.id == saved.id)
            .firstOrNull;
    setState(() {
      if (fresh != null) _saved = fresh;
      _saving = false;
      final reason = message == null || message.isEmpty ? fallback : message;
      _saveError = '$prefix$reason$suffix';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = _saved != null;
    return AlertDialog(
      title: Text(editing ? 'تعديل العرض' : 'إضافة عرض'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _imageSection(context),
                if (_imageError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_imageError!,
                        style: TextStyle(color: scheme.error)),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('offer-title'),
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'عنوان العرض'),
                  validator: (value) {
                    final length = (value ?? '').trim().length;
                    return length < 2 || length > 120
                        ? 'العنوان يجب أن يكون بين 2 و120 حرفاً.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('offer-description'),
                  controller: _description,
                  enabled: !_saving,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                  validator: (value) => (value ?? '').trim().length > 1000
                      ? 'الوصف يجب ألا يتجاوز 1000 حرف.'
                      : null,
                ),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('offer-label'),
                      controller: _label,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'وصف الخصم (اختياري)',
                        hintText: 'مثال: خصم 20%',
                      ),
                      validator: (value) => (value ?? '').trim().length > 60
                          ? 'يجب ألا يتجاوز 60 حرفاً.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      key: const Key('offer-order'),
                      controller: _order,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'ترتيب العرض'),
                      validator: (value) {
                        final order = int.tryParse((value ?? '').trim());
                        return order == null || order < 0 || order > 9999
                            ? 'من 0 إلى 9999'
                            : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _DateButton(
                      key: const Key('offer-start-date'),
                      label: 'تاريخ البداية',
                      value: _startDate,
                      enabled: !_saving,
                      onPick: () => _pickDate(start: true),
                      onClear: () => setState(() {
                        _startDate = null;
                        _dateError = offerWindowError(_startDate, _endDate);
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      key: const Key('offer-end-date'),
                      label: 'تاريخ النهاية (مشمول)',
                      value: _endDate,
                      enabled: !_saving,
                      onPick: () => _pickDate(start: false),
                      onClear: () => setState(() {
                        _endDate = null;
                        _dateError = offerWindowError(_startDate, _endDate);
                      }),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  _dateError ??
                      'التواريخ أيام تقويمية بتوقيت دمشق. ترك التاريخ فارغاً يعني بلا حد.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _dateError != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('offer-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('العرض مفعّل'),
                  subtitle: const Text('العرض المتوقف لا يظهر للعملاء.'),
                  value: _isActive,
                  onChanged:
                      _saving ? null : (value) => setState(() => _isActive = value),
                ),
                if (_saveError != null)
                  Container(
                    key: const Key('offer-save-error'),
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_saveError!,
                        style: TextStyle(color: scheme.onErrorContainer)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          // True only when a new offer was created (its image upload failed
          // and the admin closed the form instead of retrying).
          onPressed: _saving
              ? null
              : () => Navigator.pop(
                  context, widget.offer == null && _saved != null),
          child: Text(
              _saved != null && widget.offer == null ? 'إغلاق' : 'إلغاء'),
        ),
        FilledButton(
          key: const Key('offer-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }

  Widget _imageSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _pendingImage;
    final saved = _saved;
    final Widget preview = pending != null
        ? Image.memory(Uint8List.fromList(pending.bytes), fit: BoxFit.cover)
        : (!_removeImage && saved != null && saved.hasImage)
            ? AdminOfferImage(cubit: widget.cubit, offer: saved)
            : Center(
                child: Icon(Icons.add_photo_alternate_outlined,
                    size: 36, color: scheme.onSurfaceVariant));
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 160,
          height: 90,
          child: ColoredBox(color: scheme.surfaceContainerHighest, child: preview),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const Key('offer-pick-image'),
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_hasImage ? 'تغيير الصورة' : 'اختيار صورة'),
              ),
              if (_hasImage)
                TextButton(
                  key: const Key('offer-remove-image'),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _pendingImage = null;
                            _removeImage = true;
                            _imageError = null;
                          }),
                  child: const Text('إزالة الصورة'),
                ),
            ]),
            const SizedBox(height: 6),
            Text('PNG أو JPEG أو WebP، بحد أقصى 300 KB.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    ]);
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    required this.onClear,
    super.key,
  });

  final String label;
  final OfferCalendarDate? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              const EdgeInsetsDirectional.only(start: 12, end: 4, top: 4),
          suffixIcon: value != null && enabled
              ? IconButton(
                  tooltip: 'مسح التاريخ',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClear,
                )
              : null,
        ),
        child: InkWell(
          onTap: enabled ? onPick : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 18),
              const SizedBox(width: 8),
              Text(value?.toString() ?? 'بلا تاريخ'),
            ]),
          ),
        ),
      );
}

class _OffersMessage extends StatelessWidget {
  const _OffersMessage({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 54, color: YallaColors.primary),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(text, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  action,
                ]),
              ),
            ),
          ),
        ),
      );
}
