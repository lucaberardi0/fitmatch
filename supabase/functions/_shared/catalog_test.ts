import {
  buildCatalogSearchTerms,
  buildSizeVariantsForSql,
  detectExplicitProductType,
  detectSingleProductType,
  detectSubBrand,
  extractAllBrands,
  extractBrand,
  extractExcludedBrands,
  extractExcludedStores,
  extractSpecificEntityTokens,
  extractStoreFilter,
  getBlockedCategoriesForProductType,
  isProductCompatible,
  modelFamilyKey,
  normalizeProductTypeGroup,
} from "./catalog.ts";

function assert(cond: unknown, msg: string): void {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

function assertEq<T>(actual: T, expected: T, msg: string): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  expected: ${e}\n  actual:   ${a}`);
}

Deno.test("detectExplicitProductType vs detectSingleProductType prevents false category switches on activity follow-ups", () => {
  assertEq(detectExplicitProductType("Long sleeve acg"), "long_sleeve_top", "long sleeve acg explicit");
  assertEq(detectExplicitProductType("Da corsa"), null, "'Da corsa' must NOT be an explicit product noun");
  assertEq(detectSingleProductType("Da corsa"), "shoes", "'Da corsa' infers shoes only when no prior type exists");
  assertEq(detectExplicitProductType("Per trail"), null, "'Per trail' must NOT switch away from apparel");
  assertEq(detectSingleProductType("Per trail"), "trail_shoes", "'Per trail' infers trail_shoes when fresh or refining footwear");
  assertEq(detectExplicitProductType("E invece una fascia cardio per correre?"), "heart_rate_monitor", "explicit HRM switches category");
  assertEq(detectExplicitProductType("Adidas adizero dropset shoes"), "shoes", "English 'shoes' detected explicitly");
  assertEq(detectExplicitProductType("Scarpe da trail running impermeabili"), "trail_shoes", "trail shoes detected explicitly");
  assertEq(
    normalizeProductTypeGroup("long_sleeve_top") !== normalizeProductTypeGroup("shoes"),
    true,
    "top and footwear are different groups",
  );
  assertEq(
    normalizeProductTypeGroup("trail_shoes") === normalizeProductTypeGroup("shoes"),
    true,
    "trail_shoes and shoes share footwear group",
  );
});

Deno.test("extractSpecificEntityTokens strips all price, range, store, discount and reset tokens", () => {
  assertEq(extractSpecificEntityTokens("Nike Pegasus sotto 120€", "Nike"), ["pegasus"], "strips 'sotto 120€'");
  assertEq(extractSpecificEntityTokens("Scarpe running sotto ai 150 euro", null), [], "generic price query has 0 entity tokens");
  assertEq(extractSpecificEntityTokens("Scarpe running sotto €150", null), [], "strips €150");
  assertEq(extractSpecificEntityTokens("Scarpe running < 150", null), [], "strips < 150");
  assertEq(extractSpecificEntityTokens("Scarpe running tra 100 e 150 euro", null), [], "strips range");
  assertEq(extractSpecificEntityTokens("Scarpe Nike su Cisalfa con spedizione gratuita in sconto", "Nike"), [], "strips store/shipping/sale");
  assertEq(extractSpecificEntityTokens("Rimuovi limite di prezzo", null), [], "strips reset commands");
  assertEq(extractSpecificEntityTokens("Nike long sleeve acg", "Nike"), ["acg"], "keeps ACG sub-brand token");
  assertEq(extractSpecificEntityTokens("Adidas Adizero Dropset Pro", "Adidas"), ["adizero", "dropset"], "keeps model line tokens");
});

Deno.test("extractStoreFilter recognizes partner stores", () => {
  assertEq(extractStoreFilter("Scarpe Nike su Cisalfa")?.id, "cisalfa", "cisalfa");
  assertEq(extractStoreFilter("Solo su Decathlon")?.id, "decathlon", "decathlon");
  assertEq(extractStoreFilter("Offerte Mister Running")?.id, "misterrunning", "misterrunning");
  assertEq(extractStoreFilter("Top4Running scarpe")?.id, "top4running", "top4running");
  assertEq(extractStoreFilter("Scarpe running sotto 150 euro"), null, "no store");
});

Deno.test("detectSubBrand identifies ACG and parent Nike", () => {
  assertEq(detectSubBrand("Long sleeve acg"), ["Nike", "acg"], "acg -> Nike");
  assertEq(detectSubBrand("Terrex Agravic"), ["Adidas", "terrex"], "terrex -> Adidas");
});

Deno.test("buildCatalogSearchTerms prioritizes specific apparel+entity terms and strips >> chains", () => {
  const terms = buildCatalogSearchTerms({
    rawQuery: "Nike long sleeve acg",
    keywords: ["Nike ACG", "Nike ACG manica lunga"],
    brand: "Nike",
    productType: "long_sleeve_top",
    entityTokens: ["acg"],
  });
  assert(terms.length >= 2, "produces multiple search terms");
  assert(
    /manic|long\s*sleeve|\bls\b|zip/i.test(terms[0]),
    `First term must be specific long-sleeve query, got: ${JSON.stringify(terms)}`,
  );
  assert(
    terms.every((t) => !t.includes(">>")),
    "never contains >> separator",
  );
});

Deno.test("buildSizeVariantsForSql generates shoe EU/US/UK and apparel variants", () => {
  const eu44 = buildSizeVariantsForSql("44", "Uomo") ?? [];
  assert(eu44.includes("44"), "includes 44");
  assert(eu44.includes("EU 44"), "includes EU 44");
  assert(eu44.includes("10"), "includes US 10 for men EU 44");
  const eu425 = buildSizeVariantsForSql("42.5", "Uomo") ?? [];
  assert(eu425.includes("42.5") && eu425.includes("42,5"), "includes 42.5 and 42,5");
  const sizeM = buildSizeVariantsForSql("M", null) ?? [];
  assert(sizeM.includes("M"), "includes apparel M");
});

Deno.test("isProductCompatible accepts true ACG long sleeves resiliently and rejects watches/caps/shoes", () => {
  const radicalAirflow = {
    canonical_name: "Nike Acg Radical Airflow Nxt Maglia Trail Manica Lunga",
    brand: "Nike",
    category: "trail_running", // even if misclassified!
    gender: "Uomo",
    best_price: 149.99,
    offers: [{ title: "Nike ACG Radical AirFlow NXT Maglia trail manica lunga uomo", url: "https://example.com/nike-acg-longsleeve" }],
  };
  assertEq(
    isProductCompatible(radicalAirflow, "long_sleeve_top", "nike long sleeve acg"),
    true,
    "true long sleeve accepted even with stale trail_running category",
  );

  const wolfGrid = {
    canonical_name: "Nike Polar Acg Wolf Tree",
    brand: "Nike",
    category: "top",
    gender: "Uomo",
    best_price: 95,
    offers: [{ title: "Nike Polar ACG Wolf Tree", url: "https://example.com/nike-polar-acg-wolf-tree" }],
  };
  assertEq(
    isProductCompatible(wolfGrid, "long_sleeve_top", "nike long sleeve acg"),
    true,
    "Nike Polar ACG Wolf Tree fleece accepted for long_sleeve_top",
  );

  const polarWatch = {
    canonical_name: "Polar Vantage V3",
    brand: "Polar",
    category: "gps_watch",
    gender: "Unisex",
    best_price: 499,
    offers: [{ title: "Polar Vantage V3 Orologio GPS", url: "https://example.com/polar-vantage-v3" }],
  };
  assertEq(
    isProductCompatible(polarWatch, "long_sleeve_top", "maglia manica lunga"),
    false,
    "Polar GPS watch rejected for long_sleeve_top",
  );

  const acgCap = {
    canonical_name: "Nike Acg Cappellino Trail",
    brand: "Nike",
    category: "accessories",
    gender: "Unisex",
    best_price: 35,
    offers: [{ title: "Nike ACG Cappellino", url: "https://example.com/nike-acg-cap" }],
  };
  assertEq(
    isProductCompatible(acgCap, "long_sleeve_top", "nike long sleeve acg"),
    false,
    "ACG cap rejected for long_sleeve_top",
  );
});

Deno.test("Negations: excluded brands & stores never trigger positive brand/store filters", () => {
  assertEq(extractExcludedBrands("Scarpe running non Nike"), ["Nike"], "non Nike -> excluded");
  assertEq(extractBrand("Scarpe running non Nike", null), null, "non Nike must NOT set positive brand");
  assertEq(extractAllBrands("Scarpe running non Nike"), [], "non Nike must NOT be in allBrands");
  assertEq(extractExcludedBrands("Scarpe running tranne Nike e Adidas"), ["Nike", "Adidas"], "multi-brand exclusion");
  assertEq(extractBrand("Scarpe Brooks non Nike", null), "Brooks", "positive brand kept when another brand excluded");

  assertEq(extractExcludedStores("Scarpe running escluso Decathlon").map((s) => s.id), ["decathlon"], "excluded store");
  assertEq(extractStoreFilter("Scarpe running escluso Decathlon"), null, "excluded store must NOT set positive store");
  assertEq(extractStoreFilter("Scarpe running su Cisalfa tranne Decathlon")?.id, "cisalfa", "positive store kept alongside excluded store");

  assertEq(extractSpecificEntityTokens("Scarpe running non Nike più economiche", null), [], "negation & sort words never become entity tokens");
  assertEq(extractSpecificEntityTokens("Scarpe running senza piastra in carbonio", null), [], "carbon plate negation never becomes entity tokens");
});

Deno.test("Shoes gating blocks gear/pack/bike racks and modelFamilyKey groups sub-variants cleanly", () => {
  const blockedShoes = getBlockedCategoriesForProductType("shoes") ?? [];
  assert(blockedShoes.includes("gear") && blockedShoes.includes("pack"), "shoes blocks gear and pack");
  assert((getBlockedCategoriesForProductType("headwear") ?? []).includes("shoes"), "headwear blocks shoes");
  assert((getBlockedCategoriesForProductType("basketball_shoes") ?? []).includes("gear"), "basketball_shoes blocks gear");

  const bikeRack = {
    canonical_name: "Mottez Portabici Mottez 5 Biciclette Alto Basso Barre Antifurto",
    brand: null,
    category: "gear",
    gender: "Unisex",
    best_price: 239.99,
    offers: [{ title: "Mottez Portabici 5 Biciclette", url: "https://example.com/portabici" }],
  };
  assertEq(isProductCompatible(bikeRack, "shoes", "scarpe running più economiche"), false, "bike rack rejected for shoes");

  const mysteryNonShoe = {
    canonical_name: "Bassoli Lampone Costanza",
    brand: null,
    category: "other",
    gender: "Unisex",
    best_price: 43.99,
    offers: [{ title: "Bassoli Lampone Costanza", url: "https://example.com/lampone" }],
  };
  assertEq(isProductCompatible(mysteryNonShoe, "shoes", "scarpe running più economiche"), false, "non-shoe item without shoe cue/sizes rejected");

  const dummy = (name: string) => ({
    id: name,
    canonical_name: name,
    brand: "Brooks",
    image_url: null,
    gallery_images: null,
    gender: "Uomo",
    offers: [],
    best_price: 100,
    highest_price: 100,
    cross_store_savings: null,
  });
  assertEq(modelFamilyKey(dummy("Brooks Ghost Max 3 (Uomo)")), "brooks ghost", "Ghost Max -> brooks ghost");
  assertEq(modelFamilyKey(dummy("Brooks Ghost Amp (Uomo)")), "brooks ghost", "Ghost Amp -> brooks ghost");
  assertEq(modelFamilyKey(dummy("Brooks Ghost 18 Large")), "brooks ghost", "Ghost 18 Large -> brooks ghost");
});
