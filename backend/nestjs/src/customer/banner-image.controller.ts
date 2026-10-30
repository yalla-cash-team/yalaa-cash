import { Controller, Get, Param, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../auth/decorators/public.decorator";
import { CustomerService } from "./customer.service";

@Controller("banners")
export class BannerImageController {
  constructor(private readonly customer: CustomerService) {}

  // Public: banners are shown on the home screen before any sign-in step.
  @Public()
  @Get(":bannerId/image")
  async image(@Param("bannerId") bannerId: string, @Res() res: Response) {
    const image = await this.customer.getBannerImage(bannerId);
    res.setHeader("Content-Type", image.contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
    res.send(Buffer.from(image.data));
  }
}
