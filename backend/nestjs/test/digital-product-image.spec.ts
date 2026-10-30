import { DigitalProduct } from "@prisma/client";
import { presentDigitalProduct } from "../src/common/presenters";

function product(overrides: Partial<DigitalProduct>): DigitalProduct {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    name: "Gift card",
    costInPoints: BigInt(500),
    imageUrl: null,
    imageVersion: 0,
    iconSeed: 3,
    requiresPhoneNumber: false,
    isActive: true,
    createdAt: new Date("2026-10-01T00:00:00Z"),
    updatedAt: new Date("2026-10-01T00:00:00Z"),
    ...overrides,
  } as DigitalProduct;
}

describe("presentDigitalProduct image URL", () => {
  it("uses the uploaded image with a cache-busting version", () => {
    const presented = presentDigitalProduct(
      product({ imageUrl: "https://example.com/old.png", imageVersion: 2 }),
    );
    expect(presented.imageUrl).toBe(
      "/digital-products/11111111-1111-4111-8111-111111111111/image?v=2",
    );
  });

  it("keeps the legacy imageUrl when nothing was uploaded", () => {
    const presented = presentDigitalProduct(
      product({ imageUrl: "https://example.com/legacy.png" }),
    );
    expect(presented.imageUrl).toBe("https://example.com/legacy.png");
  });

  it("returns null when the product has no image at all", () => {
    expect(presentDigitalProduct(product({})).imageUrl).toBeNull();
  });
});
