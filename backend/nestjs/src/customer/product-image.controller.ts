import { Controller, Get, Param, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../auth/decorators/public.decorator";
import { CustomerService } from "./customer.service";

@Controller("digital-products")
export class ProductImageController {
  constructor(private readonly customer: CustomerService) {}

  // Public: product images appear in the catalogue before redemption. The
  // version query parameter changes whenever the image changes.
  @Public()
  @Get(":productId/image")
  async image(@Param("productId") productId: string, @Res() res: Response) {
    const image = await this.customer.getDigitalProductImage(productId);
    res.setHeader("Content-Type", image.contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
    res.send(Buffer.from(image.data));
  }
}
