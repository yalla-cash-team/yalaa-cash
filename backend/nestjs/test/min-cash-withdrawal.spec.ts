import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { UpdateMinCashWithdrawalDto } from "../src/admin/dto/admin.dto";

async function errorsFor(value: unknown): Promise<number> {
  const dto = plainToInstance(UpdateMinCashWithdrawalDto, {
    minCashWithdrawalSyp: value,
  });
  return (await validate(dto)).length;
}

describe("UpdateMinCashWithdrawalDto", () => {
  it("accepts whole SYP amounts including 0 (no minimum)", async () => {
    expect(await errorsFor(0)).toBe(0);
    expect(await errorsFor(5000)).toBe(0);
  });

  it("rejects negative, fractional and oversized amounts", async () => {
    expect(await errorsFor(-1)).toBeGreaterThan(0);
    expect(await errorsFor(10.5)).toBeGreaterThan(0);
    expect(await errorsFor(1000000001)).toBeGreaterThan(0);
  });

  it("rejects missing or non-numeric values", async () => {
    expect(await errorsFor(undefined)).toBeGreaterThan(0);
    expect(await errorsFor("5000")).toBeGreaterThan(0);
  });
});
