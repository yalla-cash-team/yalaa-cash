import { Controller, Get, Param, Query, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../auth/decorators/public.decorator";
import { ListStoresDto } from "./dto/list-stores.dto";
import { StoresService } from "./stores.service";

@Controller("stores")
export class StoresController {
  constructor(private readonly stores: StoresService) {}

  @Public()
  @Get()
  list(@Query() query: ListStoresDto) {
    return this.stores.listActiveStores(query);
  }

  // Public: logos are shown to customers before they sign in. The version
  // query parameter changes whenever the logo changes, so caching is safe.
  @Public()
  @Get(":storeId/logo")
  async logo(@Param("storeId") storeId: string, @Res() res: Response) {
    const logo = await this.stores.getStoreLogo(storeId);
    res.setHeader("Content-Type", logo.contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    // Helmet defaults to same-origin; logos are meant to load in other apps.
    res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
    res.send(Buffer.from(logo.data));
  }
}
