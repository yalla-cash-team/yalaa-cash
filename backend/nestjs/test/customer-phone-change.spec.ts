import { BadRequestException } from "@nestjs/common";
import { CustomerService } from "../src/customer/customer.service";
import { UpdateCustomerProfileDto } from "../src/customer/dto/customer.dto";

/**
 * Regression tests for the security audit findings:
 *  - auth-unverified-phone-change-prehijack: a profile update can never bind
 *    a different phone number (the OTP login identifier) to an account.
 *  - customer-phone-registration-oracle: refusing a phone change must not
 *    reveal whether the requested number is registered.
 * Existing clients that resend the unchanged phone keep working.
 */

const USER_ID = "11111111-1111-4111-8111-111111111111";
const OWN_PHONE = "+963900000001";
const REGISTERED_ELSEWHERE = "+963900000002";
const UNREGISTERED = "+963900000099";

function setup(currentPhone: string | null = OWN_PHONE) {
  const prisma = {
    user: {
      findUnique: jest.fn().mockResolvedValue({ phone: currentPhone }),
      update: jest.fn(),
    },
    customerProfile: {
      update: jest.fn().mockImplementation(({ data }) =>
        Promise.resolve({
          userId: USER_ID,
          name: data.name,
          governorate: data.governorate,
          governorateId: null,
          cityId: null,
          pointsBalance: 0n,
          createdAt: new Date(0),
          user: { phone: currentPhone, authMethod: "PHONE" },
        }),
      ),
    },
  };
  const service = new CustomerService(
    prisma as never,
    {} as never,
    {} as never,
    {} as never,
  );
  const update = (body: Partial<UpdateCustomerProfileDto>) =>
    service.updateProfile(USER_ID, {
      name: " Customer ",
      governorate: " Damascus ",
      ...body,
    } as UpdateCustomerProfileDto);
  return { prisma, update };
}

async function rejection(promise: Promise<unknown>) {
  const error = (await promise.catch((e: unknown) => e)) as BadRequestException;
  expect(error).toBeInstanceOf(BadRequestException);
  return { status: error.getStatus(), body: error.getResponse() };
}

describe("Finding auth-unverified-phone-change-prehijack", () => {
  it("updates the profile when no phone is sent", async () => {
    const t = setup();
    const result = await t.update({});
    expect(result.name).toBe("Customer");
    expect(t.prisma.user.findUnique).not.toHaveBeenCalled();
    expect(t.prisma.customerProfile.update.mock.calls[0][0].data).toEqual({
      name: "Customer",
      governorate: "Damascus",
    });
  });

  it("accepts the unchanged phone from existing clients, in any formatting", async () => {
    const t = setup();
    await expect(t.update({ phone: OWN_PHONE })).resolves.toBeDefined();
    await expect(t.update({ phone: "+963 900-000-001" })).resolves.toBeDefined();
    expect(t.prisma.customerProfile.update).toHaveBeenCalledTimes(2);
  });

  it("refuses a different phone and writes nothing", async () => {
    const t = setup();
    const { body } = await rejection(t.update({ phone: UNREGISTERED }));
    expect(body).toMatchObject({ message: "Phone number changes require verification." });
    expect(t.prisma.customerProfile.update).not.toHaveBeenCalled();
    expect(t.prisma.user.update).not.toHaveBeenCalled();
  });

  it("refuses to attach a phone to an account that has none (OAuth sign-up)", async () => {
    const t = setup(null);
    await rejection(t.update({ phone: UNREGISTERED }));
    expect(t.prisma.customerProfile.update).not.toHaveBeenCalled();
  });

  it("never writes User.phone from a profile update, even when the phone is unchanged", async () => {
    const t = setup();
    await t.update({ phone: OWN_PHONE });
    const data = t.prisma.customerProfile.update.mock.calls[0][0].data;
    expect(data).not.toHaveProperty("user");
    expect(t.prisma.user.update).not.toHaveBeenCalled();
  });
});

describe("Finding customer-phone-registration-oracle", () => {
  it("returns the identical response for registered and unregistered numbers", async () => {
    const registered = await rejection(setup().update({ phone: REGISTERED_ELSEWHERE }));
    const unregistered = await rejection(setup().update({ phone: UNREGISTERED }));
    expect(registered).toEqual(unregistered);
    expect(registered.status).toBe(400);
  });

  it("never looks up the requested number, so no uniqueness error can occur", async () => {
    const t = setup();
    await rejection(t.update({ phone: REGISTERED_ELSEWHERE }));
    // Only the caller's own row is read, by id.
    expect(t.prisma.user.findUnique).toHaveBeenCalledTimes(1);
    expect(t.prisma.user.findUnique).toHaveBeenCalledWith({
      where: { id: USER_ID },
      select: { phone: true },
    });
  });
});
