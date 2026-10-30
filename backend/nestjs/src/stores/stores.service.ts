import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { presentStore } from "../common/presenters";
import { ListStoresDto } from "./dto/list-stores.dto";

@Injectable()
export class StoresService {
  constructor(private readonly prisma: PrismaService) {}

  async listActiveStores(query: ListStoresDto) {
    const stores = await this.prisma.store.findMany({
      where: {
        isActive: true,
        ...(query.city
          ? { city: { equals: query.city.trim(), mode: "insensitive" } }
          : {}),
        ...(query.category
          ? { category: { equals: query.category.trim(), mode: "insensitive" } }
          : {}),
        // Strict governorate match by id — never falls back to showing
        // stores from a different governorate. Omitted entirely (no
        // filter) only when the caller doesn't provide a governorateId.
        ...(query.governorateId ? { governorateId: query.governorateId } : {}),
      },
      orderBy: [{ city: "asc" }, { category: "asc" }, { name: "asc" }],
    });
    return { items: stores.map(presentStore) };
  }

  async getStoreLogo(storeId: string) {
    const logo = await this.prisma.storeLogo.findUnique({
      where: { storeId },
    });
    if (!logo) throw new NotFoundException("Store logo was not found.");
    return logo;
  }
}
