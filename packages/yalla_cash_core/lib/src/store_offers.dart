import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:yalla_cash_core/src/core/failure.dart';

/// View-only store offers (see docs/STORE_OFFERS_API.md).
///
/// Offers carry no coupon, QR, points, cash or redemption behaviour: they are
/// informational cards on a store's page.
///
/// Dates come in two forms, both produced by the backend:
/// - [OfferCalendarDate] `startDate` / `endDate`: inclusive Asia/Damascus
///   calendar days, exactly as the admin entered them. Used for display and
///   edit forms; never converted through the device time zone.
/// - `startsAt` / `endsBefore`: the stored UTC instants (`endsBefore` is
///   EXCLUSIVE). Used for status checks, compared as absolute instants.
/// The Damascus day -> instant conversion happens only on the backend.

/// A calendar day ("YYYY-MM-DD") with no time and no time zone.
class OfferCalendarDate extends Equatable
    implements Comparable<OfferCalendarDate> {
  /// Throws [ArgumentError] if the day does not exist (e.g. Feb 30).
  factory OfferCalendarDate(int year, int month, int day) {
    final date = _tryCreate(year, month, day);
    if (date == null) {
      throw ArgumentError('Not a real calendar date: $year-$month-$day');
    }
    return date;
  }

  const OfferCalendarDate._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Strict "YYYY-MM-DD"; null when malformed or not a real day.
  static OfferCalendarDate? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    return _tryCreate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Like [tryParse] but throws a [FormatException].
  static OfferCalendarDate parse(String value) =>
      tryParse(value) ??
      (throw FormatException('Expected a YYYY-MM-DD calendar date', value));

  static OfferCalendarDate? _tryCreate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1) return null;
    // DateTime.utc normalises overflow (Feb 30 -> Mar 2); a real day
    // survives the round trip unchanged. UTC only: no device time zone.
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      return null;
    }
    return OfferCalendarDate._(year, month, day);
  }

  /// "YYYY-MM-DD", the wire format.
  String toJson() => toString();

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(OfferCalendarDate other) =>
      year != other.year
          ? year.compareTo(other.year)
          : month != other.month
              ? month.compareTo(other.month)
              : day.compareTo(other.day);

  @override
  List<Object?> get props => [year, month, day];
}

/// Admin-facing offer state, identical to the backend's `offerStatus`.
enum OfferStatus {
  /// Switched off by an admin. Overrides the date window.
  inactive,

  /// Switched on, but `now < startsAt`.
  scheduled,

  /// Switched on and `startsAt <= now < endsBefore` (null = unbounded).
  active,

  /// Switched on, but `now >= endsBefore`.
  expired;

  static OfferStatus? tryParse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// The backend's availability rule, on absolute instants.
///
/// All comparisons use microseconds since the epoch, so UTC and local
/// [DateTime]s describing the same instant behave identically.
OfferStatus offerStatusAt({
  required bool isActive,
  required DateTime? startsAt,
  required DateTime? endsBefore,
  required DateTime now,
}) {
  if (!isActive) return OfferStatus.inactive;
  final t = now.microsecondsSinceEpoch;
  if (startsAt != null && t < startsAt.microsecondsSinceEpoch) {
    return OfferStatus.scheduled;
  }
  if (endsBefore != null && t >= endsBefore.microsecondsSinceEpoch) {
    return OfferStatus.expired;
  }
  return OfferStatus.active;
}

/// Which endpoint serves an offer's image.
enum OfferImageAccess {
  /// `GET /offers/:id/image`: no authentication, only for offers customers
  /// can currently see. Safe for `Image.network`.
  public,

  /// `GET /admin/offers/:id/image`: admin bearer token REQUIRED. Never load
  /// it as a plain network image; fetch the bytes through
  /// `YallaCashRepository.fetchAdminOfferImage`.
  adminPreview,
}

class StoreOffer extends Equatable {
  const StoreOffer({
    required this.id,
    required this.storeId,
    required this.title,
    this.description = '',
    this.discountLabel,
    this.imageUrl,
    this.imageVersion,
    this.hasImage = false,
    this.imageAccess = OfferImageAccess.public,
    this.startDate,
    this.endDate,
    this.startsAt,
    this.endsBefore,
    this.isActive = true,
    this.displayOrder,
    this.serverStatus,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses an offer object returned by the API.
  ///
  /// [resolveUrl] turns the server-relative `imageUrl` (which already carries
  /// the `?v=<imageVersion>` cache-buster) into an absolute URL; the query is
  /// preserved. [imageAccess] records which endpoint family returned the
  /// offer: admin responses point at the authenticated preview endpoint.
  factory StoreOffer.fromJson(
    Map<String, Object?> json, {
    String Function(String path)? resolveUrl,
    OfferImageAccess imageAccess = OfferImageAccess.public,
  }) {
    final rawImageUrl = json['imageUrl'];
    final imageUrl = rawImageUrl is String && rawImageUrl.isNotEmpty
        ? (resolveUrl?.call(rawImageUrl) ?? rawImageUrl)
        : null;
    return StoreOffer(
      id: _string(json, 'id'),
      storeId: _string(json, 'storeId'),
      title: _string(json, 'title'),
      description: json['description'] as String? ?? '',
      discountLabel: json['discountLabel'] as String?,
      imageUrl: imageUrl,
      imageVersion: _optionalInt(json['imageVersion']),
      hasImage: json['hasImage'] as bool? ?? imageUrl != null,
      imageAccess: imageAccess,
      startDate: _optionalDate(json['startDate']),
      endDate: _optionalDate(json['endDate']),
      startsAt: _optionalInstant(json['startsAt']),
      endsBefore: _optionalInstant(json['endsBefore']),
      // The public endpoint only ever returns active offers and omits the flag.
      isActive: json['isActive'] as bool? ?? true,
      displayOrder: _optionalInt(json['displayOrder']),
      serverStatus: OfferStatus.tryParse(json['status']),
      createdAt: _optionalInstant(json['createdAt']),
      updatedAt: _optionalInstant(json['updatedAt']),
    );
  }

  final String id;
  final String storeId;
  final String title;
  final String description;

  /// Free-text label such as "خصم 20%". Display only; never calculated.
  final String? discountLabel;

  /// Absolute, versioned image URL (`...?v=<imageVersion>`), or null when
  /// the offer has no image. How to load it depends on [imageAccess].
  final String? imageUrl;

  /// Admin responses only; bumped on every upload and removal.
  final int? imageVersion;
  final bool hasImage;
  final OfferImageAccess imageAccess;

  /// First available Damascus calendar day (inclusive), or null.
  final OfferCalendarDate? startDate;

  /// Last available Damascus calendar day (INCLUSIVE), or null.
  final OfferCalendarDate? endDate;

  /// Stored UTC instant of [startDate]'s start (inclusive), or null.
  final DateTime? startsAt;

  /// Stored UTC instant of the day AFTER [endDate] (EXCLUSIVE), or null.
  final DateTime? endsBefore;

  final bool isActive;

  /// Admin responses only (public lists arrive already ordered).
  final int? displayOrder;

  /// Status computed by the server at response time (admin responses only).
  /// Prefer [statusAt] for live UI; this is useful when the device clock is
  /// not trusted.
  final OfferStatus? serverStatus;

  /// Admin responses only.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  OfferStatus statusAt(DateTime now) => offerStatusAt(
        isActive: isActive,
        startsAt: startsAt,
        endsBefore: endsBefore,
        now: now,
      );

  /// Whether customers can see the offer at [now] (ignoring the store's own
  /// active flag, which the server checks).
  bool isAvailableAt(DateTime now) => statusAt(now) == OfferStatus.active;

  /// The API's JSON shape (image URL as held, i.e. already absolute).
  Map<String, Object?> toJson() => {
        'id': id,
        'storeId': storeId,
        'title': title,
        'description': description,
        'discountLabel': discountLabel,
        'imageUrl': imageUrl,
        if (imageVersion != null) 'imageVersion': imageVersion,
        'hasImage': hasImage,
        'startDate': startDate?.toJson(),
        'endDate': endDate?.toJson(),
        'startsAt': startsAt?.toUtc().toIso8601String(),
        'endsBefore': endsBefore?.toUtc().toIso8601String(),
        'isActive': isActive,
        if (displayOrder != null) 'displayOrder': displayOrder,
        if (serverStatus != null) 'status': serverStatus!.name,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id,
        storeId,
        title,
        description,
        discountLabel,
        imageUrl,
        imageVersion,
        hasImage,
        imageAccess,
        startDate,
        endDate,
        startsAt,
        endsBefore,
        isActive,
        displayOrder,
        serverStatus,
        createdAt,
        updatedAt,
      ];
}

/// Parses an offer list response. The offer endpoints return a bare JSON
/// array; an `{items: [...]}` envelope (the convention of other list
/// endpoints) is accepted too.
List<StoreOffer> storeOffersFromJson(
  Object? response, {
  String Function(String path)? resolveUrl,
  OfferImageAccess imageAccess = OfferImageAccess.public,
}) {
  final Object? items =
      response is Map ? response['items'] : response;
  if (items is! List) {
    throw const YallaCashFailure(
      code: 'invalid_response',
      message: 'استجابة الخادم لا تحتوي على قائمة صالحة.',
    );
  }
  return [
    for (final item in items)
      StoreOffer.fromJson(
        _map(item),
        resolveUrl: resolveUrl,
        imageAccess: imageAccess,
      ),
  ];
}

/// The backend's ordering: displayOrder ascending, then newest first.
/// Stable for ties; missing values sort last.
List<StoreOffer> sortStoreOffers(Iterable<StoreOffer> offers) {
  final list = offers.toList();
  final indices = List<int>.generate(list.length, (i) => i);
  int compareNullable(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  indices.sort((i, j) {
    final a = list[i];
    final b = list[j];
    final byOrder = compareNullable(a.displayOrder, b.displayOrder);
    if (byOrder != 0) return byOrder;
    final aCreated = a.createdAt?.microsecondsSinceEpoch;
    final bCreated = b.createdAt?.microsecondsSinceEpoch;
    if (aCreated != bCreated) {
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;
      return bCreated.compareTo(aCreated); // newest first
    }
    return i.compareTo(j);
  });
  return List.unmodifiable([for (final i in indices) list[i]]);
}

/// Body of `POST /admin/stores/:storeId/offers`.
class StoreOfferDraft {
  const StoreOfferDraft({
    required this.title,
    this.description = '',
    this.discountLabel,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.displayOrder = 0,
  });

  /// 2–120 characters after trimming (validated by the server).
  final String title;

  /// At most 1000 characters.
  final String description;

  /// At most 60 characters; null or blank = no label.
  final String? discountLabel;

  /// Inclusive Damascus calendar days; null = open-ended.
  final OfferCalendarDate? startDate;
  final OfferCalendarDate? endDate;

  final bool isActive;

  /// 0–9999; lower shows first.
  final int displayOrder;

  Map<String, Object?> toJson() => {
        'title': title,
        'description': description,
        'discountLabel': discountLabel,
        'startDate': startDate?.toJson(),
        'endDate': endDate?.toJson(),
        'isActive': isActive,
        'displayOrder': displayOrder,
      };
}

/// A change to a nullable field in a partial update: set a value or clear it.
/// (Leaving the field out of [StoreOfferUpdate] keeps it unchanged.)
class OfferFieldUpdate<T extends Object> extends Equatable {
  const OfferFieldUpdate.set(T this.value);
  const OfferFieldUpdate.clear() : value = null;

  final T? value;

  @override
  List<Object?> get props => [value];
}

/// Body of `PATCH /admin/offers/:offerId`. Only non-null fields are sent:
/// absent = unchanged; [OfferFieldUpdate.clear] = JSON null (cleared).
/// The server validates the date order against the combined stored window.
class StoreOfferUpdate {
  const StoreOfferUpdate({
    this.title,
    this.description,
    this.discountLabel,
    this.startDate,
    this.endDate,
    this.isActive,
    this.displayOrder,
  });

  final String? title;
  final OfferFieldUpdate<String>? description;
  final OfferFieldUpdate<String>? discountLabel;
  final OfferFieldUpdate<OfferCalendarDate>? startDate;
  final OfferFieldUpdate<OfferCalendarDate>? endDate;
  final bool? isActive;
  final int? displayOrder;

  bool get isEmpty => toJson().isEmpty;

  Map<String, Object?> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description!.value,
        if (discountLabel != null) 'discountLabel': discountLabel!.value,
        if (startDate != null) 'startDate': startDate!.value?.toJson(),
        if (endDate != null) 'endDate': endDate!.value?.toJson(),
        if (isActive != null) 'isActive': isActive,
        if (displayOrder != null) 'displayOrder': displayOrder,
      };
}

/// Image bytes fetched from the authenticated admin preview endpoint. Held
/// in memory only; never written to disk or a shared cache.
class OfferImageData {
  const OfferImageData({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// Content types the offer image endpoints accept and serve.
const offerImageContentTypes = {'image/png', 'image/jpeg', 'image/webp'};

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw YallaCashFailure(
    code: 'invalid_response',
    message: 'استجابة الخادم غير متوقعة.',
    details: 'StoreOffer.$key',
  );
}

int? _optionalInt(Object? value) => switch (value) {
      null => null,
      int v => v,
      num v => v.round(),
      _ => int.tryParse('$value'),
    };

OfferCalendarDate? _optionalDate(Object? value) =>
    value is String ? OfferCalendarDate.tryParse(value) : null;

/// Instants are kept in UTC; never shifted into the device time zone.
DateTime? _optionalInstant(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw const YallaCashFailure(
    code: 'invalid_response',
    message: 'استجابة الخادم غير متوقعة.',
  );
}
