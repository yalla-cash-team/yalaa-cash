# Store Offers API (view-only)

Offers are informational cards shown on an exclusive store's page. They carry
no coupon code, QR, points, cash or redemption behaviour.

Backend code: `backend/nestjs/src/offers/`. Data model: `StoreOffer`,
`StoreOfferImage` (migration `20261105120000_store_offers`).

## Dates: Asia/Damascus calendar days

The admin UI sends **calendar dates** (`"YYYY-MM-DD"`), never device-local
timestamps. Dates are interpreted in the business time zone `Asia/Damascus`.
The offset is resolved from the time zone database, not hard-coded.

| Request field | Meaning | Stored as |
|---|---|---|
| `startDate` | first day the offer is shown (inclusive) | `startsAt` = 00:00 Damascus on that day, as a UTC instant |
| `endDate` | last day the offer is shown (inclusive) | `endsBefore` = 00:00 Damascus on the **next** day (exclusive), as a UTC instant |

Rules:

- Either date may be omitted or `null` for an open-ended window.
- `endDate == startDate` is allowed: a one-day offer.
- `endDate < startDate` returns 400.
- An impossible date (e.g. `2026-02-30`) returns 400.
- Years must be 2000–2100.
- On PATCH, a missing date field leaves that boundary unchanged and `null` clears it. The final combined window is validated.
- An offer is visible when `isActive`, its store `isActive`, and `startsAt <= now < endsBefore` (null boundaries are unbounded).

Example: `startDate: "2026-11-01", endDate: "2026-11-30"` gives
`startsAt: "2026-10-31T21:00:00.000Z"` and `endsBefore: "2026-11-30T21:00:00.000Z"`.

Every response returns both forms:

- `startDate` / `endDate`: inclusive calendar days, for display and edit forms;
- `startsAt` / `endsBefore`: the stored instants.

## Admin endpoints (role ADMIN; 401 without a token, 403 for other roles)

| Method | Path | Body | Success |
|---|---|---|---|
| GET | `/admin/stores/:storeId/offers` | none | 200 `AdminOffer[]`, includes inactive, scheduled and expired offers |
| POST | `/admin/stores/:storeId/offers` | `CreateOffer` | 201 `AdminOffer` |
| PATCH | `/admin/offers/:offerId` | `UpdateOffer` (partial) | 200 `AdminOffer` |
| DELETE | `/admin/offers/:offerId` | none | 200 `{ id, storeId, deleted: true }` |
| POST | `/admin/offers/:offerId/image` | `{ contentType, dataBase64 }` | 200 `AdminOffer` |
| DELETE | `/admin/offers/:offerId/image` | none | 200 `AdminOffer` |
| GET | `/admin/offers/:offerId/image` | none | 200 image bytes (admin preview, any status) |

The image preview is fetched with the admin bearer token.

Ids must be UUIDs; anything else returns 400. A missing store or offer returns 404.

`CreateOffer`:

```json
{
  "title": "2–120 chars, trimmed (required)",
  "description": "≤ 1000 chars, optional, null = empty",
  "discountLabel": "≤ 60 chars, optional, e.g. \"خصم 20%\", blank/null = none",
  "startDate": "YYYY-MM-DD | null (optional)",
  "endDate": "YYYY-MM-DD | null (optional)",
  "isActive": true,
  "displayOrder": 0
}
```

- `isActive` is optional and defaults to `true`.
- `displayOrder` is an integer from 0 to 9999, defaults to 0, and lower values show first.

`UpdateOffer` uses the same fields, all optional:

- an absent field is left unchanged;
- `null` clears `description`, `discountLabel`, `startDate` and `endDate`;
- `null` is invalid for `title`, `isActive` and `displayOrder`.

Any other field returns 400, including `storeId`, `city`, `category`,
`isExclusive`, `imageVersion` and points fields. Offer endpoints never modify
the store.

`AdminOffer`:

```json
{
  "id": "uuid", "storeId": "uuid",
  "title": "…", "description": "…", "discountLabel": "… | null",
  "hasImage": true, "imageVersion": 2,
  "imageUrl": "/admin/offers/<id>/image?v=2 | null",
  "startDate": "2026-11-01 | null", "endDate": "2026-11-30 | null",
  "startsAt": "ISO | null", "endsBefore": "ISO | null",
  "isActive": true, "displayOrder": 0,
  "status": "active | scheduled | expired | inactive",
  "createdAt": "ISO", "updatedAt": "ISO"
}
```

`status` reflects the server time at the moment of the request.

## Public endpoints (no authentication)

| Method | Path | Success |
|---|---|---|
| GET | `/stores/:storeId/offers` | 200 `PublicOffer[]` |
| GET | `/offers/:offerId/image` | 200 image bytes |

`GET /stores/:storeId/offers` returns 404 when the store is missing or
inactive. An active store with no visible offers returns `[]`.

The list is sorted by `displayOrder` ascending, then newest first.

`PublicOffer`:

```json
{
  "id": "uuid", "storeId": "uuid",
  "title": "…", "description": "…", "discountLabel": "… | null",
  "imageUrl": "/offers/<id>/image?v=<imageVersion> | null",
  "startDate": "… | null", "endDate": "… | null",
  "startsAt": "ISO | null", "endsBefore": "ISO | null"
}
```

`GET /offers/:offerId/image` serves only images of currently visible offers.
Any other case returns 404.

Image URLs are relative to the API base URL.

## Images

- Accepted formats are PNG, JPEG and WebP. GIF is not accepted for offers.
- Maximum size is 300 KB decoded. The image is sent as canonical base64 in JSON, with no `data:` prefix.
- The file signature must match `contentType`.
- Bytes are stored in `StoreOfferImage` and never appear in JSON responses.
- `imageVersion` increments on every upload and on every removal. Image URLs carry `?v=<imageVersion>`, so clients can cache images.
- Response headers: `Content-Type` is the stored type and `Cross-Origin-Resource-Policy` is `cross-origin`.
- `Cache-Control` is `public, max-age=86400` on the public endpoint and `private, max-age=86400` on the admin preview.
