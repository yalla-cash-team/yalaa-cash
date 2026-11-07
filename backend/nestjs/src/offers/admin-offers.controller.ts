import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Res,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import type { Response } from "express";
import { Roles } from "../auth/decorators/roles.decorator";
import {
  CreateStoreOfferDto,
  UpdateStoreOfferDto,
  UploadOfferImageDto,
} from "./dto/store-offer.dto";
import { OffersService } from "./offers.service";

/// Admin-only offer management. Class-level @Roles(ADMIN) and no @Public():
/// the global JwtAuthGuard requires a valid token (401 otherwise) and the
/// global RolesGuard rejects every non-admin role (403).
@Roles(UserRole.ADMIN)
@Controller("admin")
export class AdminOffersController {
  constructor(private readonly offers: OffersService) {}

  @Get("stores/:storeId/offers")
  list(@Param("storeId", ParseUUIDPipe) storeId: string) {
    return this.offers.listStoreOffersForAdmin(storeId);
  }

  @Post("stores/:storeId/offers")
  create(
    @Param("storeId", ParseUUIDPipe) storeId: string,
    @Body() dto: CreateStoreOfferDto,
  ) {
    return this.offers.createOffer(storeId, dto);
  }

  @Patch("offers/:offerId")
  update(
    @Param("offerId", ParseUUIDPipe) offerId: string,
    @Body() dto: UpdateStoreOfferDto,
  ) {
    return this.offers.updateOffer(offerId, dto);
  }

  @Delete("offers/:offerId")
  remove(@Param("offerId", ParseUUIDPipe) offerId: string) {
    return this.offers.deleteOffer(offerId);
  }

  @Post("offers/:offerId/image")
  @HttpCode(HttpStatus.OK)
  setImage(
    @Param("offerId", ParseUUIDPipe) offerId: string,
    @Body() dto: UploadOfferImageDto,
  ) {
    return this.offers.setOfferImage(offerId, dto);
  }

  @Delete("offers/:offerId/image")
  removeImage(@Param("offerId", ParseUUIDPipe) offerId: string) {
    return this.offers.removeOfferImage(offerId);
  }

  // Preview for the admin UI, including inactive/scheduled/expired offers
  // whose images the public endpoint does not serve.
  @Get("offers/:offerId/image")
  async image(
    @Param("offerId", ParseUUIDPipe) offerId: string,
    @Res() res: Response,
  ) {
    const image = await this.offers.getOfferImageForAdmin(offerId);
    res.setHeader("Content-Type", image.contentType);
    res.setHeader("Cache-Control", "private, max-age=86400");
    res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
    res.send(Buffer.from(image.data));
  }
}
