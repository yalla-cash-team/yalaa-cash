import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { UpdateShareRewardDto } from "../src/admin/dto/admin.dto";
import { decideShareReward } from "../src/customer/share-reward";

describe("decideShareReward", () => {
  it("disables the reward when points are zero or negative", () => {
    expect(decideShareReward(BigInt(0), false)).toBe("disabled");
    expect(decideShareReward(BigInt(-5), false)).toBe("disabled");
    expect(decideShareReward(BigInt(0), true)).toBe("disabled");
  });

  it("grants the reward once to an eligible account", () => {
    expect(decideShareReward(BigInt(50), false)).toBe("granted");
  });

  it("never grants again to an account that already claimed", () => {
    expect(decideShareReward(BigInt(50), true)).toBe("already_claimed");
  });
});

describe("UpdateShareRewardDto", () => {
  async function errorsFor(value: unknown): Promise<number> {
    const dto = plainToInstance(UpdateShareRewardDto, {
      shareRewardPoints: value,
    });
    return (await validate(dto)).length;
  }

  it("accepts zero (disabled) and positive whole points", async () => {
    expect(await errorsFor(0)).toBe(0);
    expect(await errorsFor(100)).toBe(0);
  });

  it("rejects negative, fractional and oversized values", async () => {
    expect(await errorsFor(-1)).toBeGreaterThan(0);
    expect(await errorsFor(1.5)).toBeGreaterThan(0);
    expect(await errorsFor(100001)).toBeGreaterThan(0);
  });
});
