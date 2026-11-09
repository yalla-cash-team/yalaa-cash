/**
 * City names are compared by a "key" that ignores case, extra whitespace,
 * diacritics and the common Arabic letter variants (alef forms, yaa/alef
 * maqsura, taa marbuta/haa). Two names with the same key inside one
 * governorate are treated as the same city, so a typo-like variant cannot
 * silently become a second city. Names are never merged automatically.
 */
export function normalizeCityName(name: string): string {
  return name.replace(/\s+/g, " ").trim();
}

export function cityNameKey(name: string): string {
  return normalizeCityName(name)
    .toLowerCase()
    .replace(/[ً-ٰٟـ]/g, "") // tashkeel, dagger alef, tatweel
    .replace(/[أإآٱ]/g, "ا") // أ إ آ ٱ -> ا
    .replace(/ى/g, "ي") // ى -> ي
    .replace(/ة/g, "ه"); // ة -> ه
}
