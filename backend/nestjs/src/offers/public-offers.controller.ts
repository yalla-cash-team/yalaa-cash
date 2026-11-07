import { Controller, Get, Param, ParseUUIDPipe, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../auth/decorators/public.decorator";
import { OffersService } from "./offers.service";

/// Customer-facing, read-only offer endpoints. Public like the store list
/// and store logos (shown before sign-in). Separate from StoresController so
/// the existing store endpoints are unchanged.
@Controller()
export class PublicOffersController {
  constructor(private readonly offers: OffersService) {}

  @Public()
  @Get("stores/:storeId/offers")
  list(@Param("storeId", ParseUUIDPipe) storeId: string) {
    return this.offers.listPublicStoreOffers(storeId);
  }

  // The version query parameter changes on every upload/removal, so
  // long-lived caching is safe.
  @Public()
  @Get("offers/:offerId/image")
  async image(
    @Param("offerId", ParseUUIDPipe) offerId: string,
    @Res() res: Response,
  ) {
    const image = await this.offers.getPublicOfferImage(offerId);
    res.setHeader("Content-Type", image.contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    // Helmet defaults to same-origin; images are meant to load in other apps.
    res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
    res.send(Buffer.from(image.data));
  }
}
