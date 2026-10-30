import { BannerPlacement, BannerStyle } from "@prisma/client";
import { presentBanner } from "../src/common/presenters";

describe("presentBanner", () => {
  it("serializes banner scheduling and governorate targeting into the API response", () => {
    const banner = {
      id: "banner-1",
      title: "Summer offers",
      subtitle: "Up to 40% off",
      imageUrl: "https://cdn.example.com/a.png",
      imageVersion: 0,
      targetUrl: "/stores?category=food",
      placement: BannerPlacement.HOME,
      style: BannerStyle.PROMO,
      isActive: true,
      displayOrder: 1,
      startsAt: new Date("2026-01-01T00:00:00.000Z"),
      endsAt: new Date("2026-01-31T00:00:00.000Z"),
      governorateId: "gov-1",
      createdAt: new Date("2026-01-01T00:00:00.000Z"),
      updatedAt: new Date("2026-01-10T00:00:00.000Z"),
    };

    expect(presentBanner(banner)).toEqual({
      id: "banner-1",
      title: "Summer offers",
      subtitle: "Up to 40% off",
      imageUrl: "https://cdn.example.com/a.png",
      targetUrl: "/stores?category=food",
      placement: "home",
      style: "promo",
      isActive: true,
      displayOrder: 1,
      startsAt: "2026-01-01T00:00:00.000Z",
      endsAt: "2026-01-31T00:00:00.000Z",
      governorateId: "gov-1",
      createdAt: "2026-01-01T00:00:00.000Z",
      updatedAt: "2026-01-10T00:00:00.000Z",
    });
  });
});
