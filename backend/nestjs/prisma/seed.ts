import {
  BannerPlacement,
  BannerStyle,
  PrismaClient,
  UserRole,
} from "@prisma/client";
import * as bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main(): Promise<void> {
  const adminEmail = process.env.SEED_ADMIN_EMAIL ?? "admin@yallacash.app";
  const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? "admin123";
  const merchantEmail =
    process.env.SEED_MERCHANT_EMAIL ?? "wasim@yallacash.app";
  const merchantPassword = process.env.SEED_MERCHANT_PASSWORD ?? "123456";

  await prisma.platformSettings.upsert({
    where: { id: 1 },
    update: {},
    create: { id: 1, pointValueSyp: 5 },
  });

  await prisma.governorate.upsert({
    where: { id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee" },
    update: { nameAr: "إدلب", isActive: true, displayOrder: 1 },
    create: {
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      nameAr: "إدلب",
      isActive: true,
      displayOrder: 1,
    },
  });

  await prisma.banner.upsert({
    where: { id: "99999999-9999-4999-8999-999999999999" },
    update: {
      title: "عرض إدلب الصيفي",
      subtitle: "خصومات مختارة لعملاء إدلب",
      imageUrl:
        "https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=1200&q=80",
      targetUrl: "/stores?category=restaurants",
      placement: BannerPlacement.HOME,
      style: BannerStyle.PROMO,
      isActive: true,
      displayOrder: 1,
      startsAt: null,
      endsAt: null,
      governorateId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    },
    create: {
      id: "99999999-9999-4999-8999-999999999999",
      title: "عرض إدلب الصيفي",
      subtitle: "خصومات مختارة لعملاء إدلب",
      imageUrl:
        "https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=1200&q=80",
      targetUrl: "/stores?category=restaurants",
      placement: BannerPlacement.HOME,
      style: BannerStyle.PROMO,
      isActive: true,
      displayOrder: 1,
      governorateId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    },
  });

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {
      passwordHash: await bcrypt.hash(adminPassword, 12),
      isActive: true,
      adminProfile: {
        upsert: {
          update: { displayName: "Yalla Cash Admin" },
          create: { displayName: "Yalla Cash Admin" },
        },
      },
    },
    create: {
      role: UserRole.ADMIN,
      email: adminEmail,
      passwordHash: await bcrypt.hash(adminPassword, 12),
      adminProfile: { create: { displayName: "Yalla Cash Admin" } },
    },
  });

  const idlibGovernorateId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

  const stores = [
    {
      id: "11111111-1111-4111-8111-111111111111",
      name: "مطعم الوسيم",
      category: "مطاعم",
      city: "دمشق",
      commissionRate: 6.7,
      description: "مطعم شامي تقليدي بأطباق منزلية.",
      location: "دمشق - المزة",
      iconSeed: 0,
      governorateId: idlibGovernorateId,
    },
    {
      id: "22222222-2222-4222-8222-222222222222",
      name: "ماركت البركة",
      category: "سوبرماركت",
      city: "دمشق",
      commissionRate: 5,
      description: "ماركت شامل للمواد الغذائية والمنزلية.",
      location: "دمشق - الميدان",
      iconSeed: 1,
      governorateId: idlibGovernorateId,
    },
    {
      id: "33333333-3333-4333-8333-333333333333",
      name: "كافيه الزاوية",
      category: "كافيهات",
      city: "دمشق",
      commissionRate: 8,
      description: "كافيه هادئ لمحبي القهوة المختصة.",
      location: "دمشق - أبو رمانة",
      iconSeed: 2,
      governorateId: idlibGovernorateId,
    },
  ];

  // Stores belong to a city (unique per governorate) and hold a 1-based
  // display position inside it, matching what the admin service maintains.
  const city = await prisma.city.upsert({
    where: {
      governorateId_nameAr: {
        governorateId: idlibGovernorateId,
        nameAr: "دمشق",
      },
    },
    update: {},
    create: { governorateId: idlibGovernorateId, nameAr: "دمشق" },
  });

  for (const [index, base] of stores.entries()) {
    const store = { ...base, cityId: city.id, displayOrder: index + 1 };
    await prisma.store.upsert({
      where: { id: store.id },
      update: store,
      create: store,
    });
  }

  await prisma.user.upsert({
    where: { email: merchantEmail },
    update: {
      passwordHash: await bcrypt.hash(merchantPassword, 12),
      isActive: true,
      merchantAccount: {
        upsert: {
          update: {
            storeId: stores[0].id,
            displayLabel: "الحساب الرئيسي",
            isActive: true,
          },
          create: {
            storeId: stores[0].id,
            displayLabel: "الحساب الرئيسي",
          },
        },
      },
    },
    create: {
      role: UserRole.MERCHANT,
      email: merchantEmail,
      passwordHash: await bcrypt.hash(merchantPassword, 12),
      merchantAccount: {
        create: {
          storeId: stores[0].id,
          displayLabel: "الحساب الرئيسي",
        },
      },
    },
  });

  const products = [
    {
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      name: "رصيد اتصالات",
      costInPoints: 500n,
      iconSeed: 0,
      requiresPhoneNumber: true,
    },
    {
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      name: "قسيمة تسوق رقمية",
      costInPoints: 950n,
      iconSeed: 1,
      requiresPhoneNumber: false,
    },
    {
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      name: "اشتراك موسيقى لشهر",
      costInPoints: 700n,
      iconSeed: 2,
      requiresPhoneNumber: false,
    },
    {
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      name: "باقة إنترنت",
      costInPoints: 400n,
      iconSeed: 3,
      requiresPhoneNumber: true,
    },
  ];

  for (const product of products) {
    await prisma.digitalProduct.upsert({
      where: { id: product.id },
      update: product,
      create: product,
    });
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
