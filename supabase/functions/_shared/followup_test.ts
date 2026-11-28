import {
  buildCatalogSearchTerms,
  detectExplicitProductType,
  detectProductType,
  detectSingleProductType,
  extractSpecificEntityTokens,
  isProductCompatible,
  normalizeQueryTypos,
  sanitizeEntityTokens,
} from "./catalog.ts";
import {
  guardLlmPlanFilters,
  isPureAdviceQuestion,
  parseLocalConstraints,
  reconstructPriorContext,
  resolveFollowUpTransition,
} from "./followup.ts";

function assert(cond: unknown, msg: string): void {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

function assertEq<T>(actual: T, expected: T, msg: string): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  expected: ${e}\n  actual:   ${a}`);
}

Deno.test("Regression: 'Fascia cardio' -> 'Marca Garmin con prezzo minore?' stays heart_rate_monitor, Garmin, price_asc, clean keywords", () => {
  const prior = reconstructPriorContext({
    prevContext: {
      subject_query: "Fascia cardio",
      product_type: "heart_rate_monitor",
      brand: null,
      entity_tokens: [],
    },
    contextQuery: "Fascia cardio",
    recentTurns: [{ query: "Fascia cardio" }],
    preferredSize: "43",
  });
  const local = parseLocalConstraints("Marca Garmin con prezzo minore?");
  const tr = resolveFollowUpTransition({ local, isFollowUp: true, prior });

  assertEq(tr.categorySwitched, false, "MUST NOT switch category from heart_rate_monitor to gps_watch");
  assertEq(tr.detProductType, "heart_rate_monitor", "detProductType stays heart_rate_monitor");
  assertEq(tr.currentBrand, "Garmin", "brand resolves to Garmin");
  assertEq(tr.currentEntities, [], "'marca' and 'minore' must NEVER become entity tokens");
  assertEq(local.sort_by, "price_asc", "'prezzo minore' sets sort_by = price_asc");
  assertEq(tr.pureQuestion, false, "MUST NOT be treated as pure Q&A advice");
  assertEq(tr.effectiveSubjectQuery, "Fascia cardio", "subjectQuery remains Fascia cardio");

  // Search terms must contain Garmin HRM terms and ZERO cross-brand 'polar h10' terms!
  const terms = buildCatalogSearchTerms({
    rawQuery: tr.effectiveSubjectQuery,
    keywords: [],
    brand: tr.currentBrand,
    productType: tr.detProductType,
    entityTokens: tr.currentEntities,
  });
  assert(terms.length >= 2, `Expected multiple Garmin HRM search terms, got: ${JSON.stringify(terms)}`);
  assert(
    terms.some((t) => /garmin.*fascia cardio|garmin.*hrm/i.test(t)),
    `Expected Garmin HRM search term, got: ${JSON.stringify(terms)}`,
  );
  assert(
    terms.every((t) => !/\bpolar\b/i.test(t)),
    `Cross-brand pollution ('polar') leaked into Garmin terms: ${JSON.stringify(terms)}`,
  );
});

Deno.test("Systemic: Bare multi-category brands NEVER trigger false category switches on follow-ups, while explicit switches DO", () => {
  const cases: Array<{ turn1: string; turn2: string; expectedPt: string; expectedBrand: string }> = [
    { turn1: "Fascia cardio", turn2: "Marca Garmin con prezzo minore?", expectedPt: "heart_rate_monitor", expectedBrand: "Garmin" },
    { turn1: "Fascia cardio", turn2: "E Coros?", expectedPt: "heart_rate_monitor", expectedBrand: "Coros" },
    { turn1: "Fascia cardio", turn2: "Solo Polar", expectedPt: "heart_rate_monitor", expectedBrand: "Polar" },
    { turn1: "Ciclocomputer", turn2: "Solo Garmin sotto 300 euro", expectedPt: "bike_computer", expectedBrand: "Garmin" },
    { turn1: "Ciclocomputer", turn2: "Modelli Bryton", expectedPt: "bike_computer", expectedBrand: "Bryton" },
    { turn1: "Scarpe da padel", turn2: "Marca Bullpadel", expectedPt: "padel_shoes", expectedBrand: "Bullpadel" },
    { turn1: "Giacca antivento", turn2: "Oakley", expectedPt: "jacket", expectedBrand: "Oakley" },
    { turn1: "Borraccia running", turn2: "Enervit", expectedPt: "hydration", expectedBrand: "Enervit" },
    { turn1: "Orologio GPS", turn2: "Suunto", expectedPt: "gps_watch", expectedBrand: "Suunto" },
  ];

  for (const c of cases) {
    const prior = reconstructPriorContext({
      prevContext: null,
      contextQuery: c.turn1,
      recentTurns: [{ query: c.turn1 }],
      preferredSize: null,
    });
    const local = parseLocalConstraints(c.turn2);
    const tr = resolveFollowUpTransition({ local, isFollowUp: true, prior });
    assertEq(tr.categorySwitched, false, `${c.turn1} -> ${c.turn2} must NOT switch category`);
    assertEq(tr.detProductType, c.expectedPt, `${c.turn1} -> ${c.turn2} productType`);
    assertEq(tr.currentBrand, c.expectedBrand, `${c.turn1} -> ${c.turn2} brand`);
    assertEq(tr.currentEntities, [], `${c.turn1} -> ${c.turn2} should have 0 stray entity tokens`);
  }

  // Standalone fresh bare-brand queries STILL resolve their primary default category!
  assertEq(detectSingleProductType("Garmin"), "gps_watch", "Standalone 'Garmin' defaults to gps_watch");
  assertEq(detectSingleProductType("Oakley"), "eyewear", "Standalone 'Oakley' defaults to eyewear");
  assertEq(detectSingleProductType("Bullpadel"), "padel_racket", "Standalone 'Bullpadel' defaults to padel_racket");
  assertEq(detectSingleProductType("Bryton"), "bike_computer", "Standalone 'Bryton' defaults to bike_computer");
  assertEq(detectSingleProductType("Enervit"), "nutrition", "Standalone 'Enervit' defaults to nutrition");
  assertEq(detectSingleProductType("CamelBak"), "hydration", "Standalone 'CamelBak' defaults to hydration");

  // Explicit category switches STILL work!
  const hrmPrior = reconstructPriorContext({
    prevContext: null,
    contextQuery: "Fascia cardio",
    recentTurns: [{ query: "Fascia cardio" }],
    preferredSize: null,
  });
  const watchSwitch1 = resolveFollowUpTransition({
    local: parseLocalConstraints("E invece un orologio Garmin?"),
    isFollowUp: true,
    prior: hrmPrior,
  });
  assertEq(watchSwitch1.categorySwitched, true, "'orologio Garmin' switches to gps_watch");
  assertEq(watchSwitch1.detProductType, "gps_watch", "detProductType switches to gps_watch");

  const watchSwitch2 = resolveFollowUpTransition({
    local: parseLocalConstraints("Garmin Forerunner 265"),
    isFollowUp: true,
    prior: hrmPrior,
  });
  assertEq(watchSwitch2.categorySwitched, true, "'Garmin Forerunner 265' switches to gps_watch");
  assertEq(watchSwitch2.detProductType, "gps_watch", "detProductType switches to gps_watch");

  // detectProductType(query, contextQuery) also preserves prior HRM over bare brand!
  assertEq(
    detectProductType("Marca Garmin con prezzo minore?", "Fascia cardio"),
    "heart_rate_monitor",
    "detectProductType preserves context heart_rate_monitor over bare Garmin",
  );
});

Deno.test("All 11 iOS chip-removal reset queries produce ZERO entity tokens and preserve subject", () => {
  const resetQueries = [
    "Rimuovi limite di prezzo",
    "Tutte le taglie",
    "Tutti i generi",
    "Tutti i colori",
    "Tutti i negozi",
    "Tutti i brand",
    "Rimuovi filtro spedizione",
    "Rimuovi filtro sconti",
    "Rimuovi esclusioni",
    "Ordine consigliato",
    "Rimuovi tutti i filtri",
    "Includi spedizione a pagamento",
  ];

  const prior = reconstructPriorContext({
    prevContext: {
      subject_query: "Nike long sleeve bucate",
      product_type: "long_sleeve_top",
      brand: "Nike",
      entity_tokens: [],
    },
    contextQuery: "Nike long sleeve bucate",
    recentTurns: [{ query: "Nike long sleeve bucate" }],
    preferredSize: "M",
  });

  for (const rq of resetQueries) {
    assertEq(extractSpecificEntityTokens(rq, null), [], `extractSpecificEntityTokens('${rq}') must be []`);
    const local = parseLocalConstraints(rq);
    const tr = resolveFollowUpTransition({ local, isFollowUp: true, prior });
    assertEq(tr.currentEntities, [], `transition.currentEntities for '${rq}' must be []`);
    assertEq(tr.detProductType, "long_sleeve_top", `productType preserved on '${rq}'`);
    assertEq(tr.isPureResetTurn, true, `'${rq}' detected as pure reset turn`);
    if (rq === "Tutti i brand") {
      assert(!/\bnike\b/i.test(tr.effectiveSubjectQuery), `Brand reset strips old brand from subject: '${tr.effectiveSubjectQuery}'`);
    }
  }
});

Deno.test("Real production log regressions: Italian stopwords, plurals, typos, sort phrases, brand switch, digit follow-up", () => {
  // 1. Plural 'Fasce cardio' & typo 'Fascia cardo'
  assertEq(detectExplicitProductType("Fasce cardio"), "heart_rate_monitor", "Italian plural 'Fasce cardio'");
  assertEq(detectExplicitProductType("Fascia cardo Garmin sotto i 50 euro"), "heart_rate_monitor", "Typo 'Fascia cardo'");
  assertEq(extractSpecificEntityTokens("Fascia cardo Garmin sotto i 50 euro", "Garmin"), [], "No stray 'cardo' entity");

  // 2. Bare 'maglia' maps to generic 'top' (does NOT reject long sleeves!)
  assertEq(detectExplicitProductType("Nike ACG Radical Airflow NXT maglia"), "top", "Bare 'maglia' -> top");
  assertEq(detectExplicitProductType("Maglietta running Nike"), "short_sleeve_top", "'Maglietta' -> short_sleeve_top");

  // 3. Production log stopword leaks
  assertEq(extractSpecificEntityTokens("Under armour long sleeve uomo nella mia taglia", "Under Armour"), [], "strips 'nella', 'mia'");
  assertEq(extractSpecificEntityTokens("Cosa mi consigli di orologi per nuotare", null), [], "strips 'mi'");
  assertEq(extractSpecificEntityTokens("Ci sono modelli rosa?", null), [], "strips 'ci'");
  assertEq(extractSpecificEntityTokens("Mentre cappellini ?", null), [], "strips 'mentre', 'cappellini'");
  assertEq(extractSpecificEntityTokens("Con sconti elevati", null), [], "strips 'elevati'");
  assertEq(extractSpecificEntityTokens("Quelle con prezzo più basso", null), [], "strips 'quelle'");
  assertEq(extractSpecificEntityTokens("Mentre scarpe da padel? Ci sono modelli specifici?", null), [], "strips 'mentre', 'ci', 'specifici'");
  assertEq(extractSpecificEntityTokens("Shorts under armour uomo possibilmente sotto i 25 euro", "Under Armour"), [], "strips 'possibilmente'");
  assertEq(extractSpecificEntityTokens("Mostrane altri", null), [], "strips 'mostrane'");
  assertEq(extractSpecificEntityTokens("Mente nike?", "Nike"), [], "typo 'Mente nike?' normalizes to 'mentre nike?' -> []");
  assertEq(extractSpecificEntityTokens("Saucony endorphin per tempo run", "Saucony"), ["endorphin"], "'tempo run' stripped while keeping 'endorphin'");
  assertEq(extractSpecificEntityTokens("Nike tempo shorts", "Nike"), ["tempo"], "standalone model name 'Nike Tempo' still kept!");
  assertEq(extractSpecificEntityTokens("Giacca anti vento", null), [], "'anti vento' -> antivento -> []");
  assertEq(extractSpecificEntityTokens("K way running", null), [], "'K way' -> k-way -> []");
  assertEq(extractSpecificEntityTokens("Scalda collo trail", null), [], "'Scalda collo' -> scaldacollo -> []");
  assertEq(extractSpecificEntityTokens("Scarpe hyrox sui 90 euro", null), [], "strips 'sui 90 euro'");

  // 4. Natural-language sort & approximate budget parsing
  assertEq(parseLocalConstraints("Marca Garmin con prezzo minore?").sort_by, "price_asc", "prezzo minore -> price_asc");
  assertEq(parseLocalConstraints("Quelle che costano meno").sort_by, "price_asc", "costano meno -> price_asc");
  assertEq(parseLocalConstraints("Qual è la più economica?").sort_by, "price_asc", "più economica -> price_asc");
  assertEq(isPureAdviceQuestion("Qual è la più economica?", true), false, "'Qual è la più economica?' is catalog sort, NOT pure Q&A");
  assertEq(parseLocalConstraints("Con sconti elevati").sort_by, "discount_desc", "sconti elevati -> discount_desc");
  assertEq(parseLocalConstraints("Con sconti elevati").on_sale, true, "sconti elevati -> on_sale");
  assertEq(parseLocalConstraints("Scarpe hyrox sui 90 euro").max_price, 105, "approximate budget 'sui 90 euro' -> 105 cap");

  // 5. Brand switch preserves prior product/activity subject!
  const pumaPrior = reconstructPriorContext({
    prevContext: null,
    contextQuery: "Long sleeve da corsa Puma",
    recentTurns: [{ query: "Long sleeve da corsa Puma" }],
    preferredSize: null,
  });
  const nikeSwitch = resolveFollowUpTransition({
    local: parseLocalConstraints("Mente nike?"),
    isFollowUp: true,
    prior: pumaPrior,
  });
  assertEq(nikeSwitch.brandSwitched, true, "Puma -> Nike is brandSwitched");
  assertEq(nikeSwitch.detProductType, "long_sleeve_top", "Stays long_sleeve_top");
  assertEq(nikeSwitch.effectiveSubjectQuery, "Long sleeve da corsa Nike", "Replaces old brand inside subjectQuery");

  // 6. Digit-only follow-up preserves model family ("Garmin Forerunner" -> "165")
  const frPrior = reconstructPriorContext({
    prevContext: null,
    contextQuery: "Garmin Forerunner",
    recentTurns: [{ query: "Garmin Forerunner" }],
    preferredSize: null,
  });
  const fr165 = resolveFollowUpTransition({
    local: parseLocalConstraints("165"),
    isFollowUp: true,
    prior: frPrior,
  });
  assertEq(fr165.currentEntities, ["forerunner", "165"], "Merges non-digit model family + digit version");
  assertEq(fr165.effectiveSubjectQuery, "Garmin forerunner 165", "Builds clean merged subject");

  // 7. Auto-heal poisoned legacy DB context_state!
  const healed = reconstructPriorContext({
    prevContext: {
      subject_query: "Marca Garmin con prezzo minore?",
      product_type: "gps_watch",
      brand: "Garmin",
      entity_tokens: ["marca", "minore"],
    },
    contextQuery: "Fascia cardio >> Marca Garmin con prezzo minore?",
    recentTurns: [{ query: "Fascia cardio" }, { query: "Marca Garmin con prezzo minore?" }],
    preferredSize: null,
  });
  assertEq(healed.productType, "heart_rate_monitor", "Replay auto-heals poisoned DB product_type");
  assertEq(healed.entityTokens, [], "Replay + sanitizeEntityTokens scrubs poisoned ['marca', 'minore']");
  assertEq(sanitizeEntityTokens(["marca", "minore", "brand", "hrm", "200"], "Garmin"), ["hrm", "200"], "sanitizeEntityTokens keeps real model tokens");
});

Deno.test("LLM Stage-1 hallucination guards block invented gender/price/size/color filters", () => {
  const hallucinatedPlan = {
    gender: "Uomo",
    max_price: 120,
    min_price: 50,
    size: "43",
    color: "Nero",
    brand: "Nike",
    product_type: "long_sleeve_top",
  };
  const guarded = guardLlmPlanFilters("Tutti i brand", hallucinatedPlan);
  assertEq(guarded.llmGender, null, "Hallucinated gender blocked when query has no gender cue");
  assertEq(guarded.llmMaxPrice, null, "Hallucinated max_price blocked when query has no digits");
  assertEq(guarded.llmMinPrice, null, "Hallucinated min_price blocked when query has no digits");
  assertEq(guarded.llmSize, null, "Hallucinated size blocked when query has no size cue");
  assertEq(guarded.llmColor, null, "Hallucinated color blocked when query has no color cue");

  // Legitimate indirect cues are still allowed through!
  const legit = guardLlmPlanFilters("Regalo per mia moglie sotto 120€ nero", hallucinatedPlan);
  assertEq(legit.llmGender, "Uomo", "Gender cue present allows LLM gender");
  assertEq(legit.llmMaxPrice, 120, "Digits present allow LLM max_price");
  assertEq(legit.llmColor?.key, "black", "Color cue present allows LLM color");
});

Deno.test("heart_rate_monitor compatibility accepts real Garmin/Polar/Coros HRMs and rejects straps, cables, speed sensors, smart bikes & watches", () => {
  const realHrm200 = {
    canonical_name: "Garmin Sensore Frequenza Cardiaca Hrm 200",
    brand: "Garmin",
    category: "sensor",
    gender: "Unisex",
    best_price: 63.99,
    offers: [{ title: "Garmin Sensore Frequenza Cardiaca HRM 200", url: "https://example.com/hrm-200" }],
  };
  const corosStrapCatHrm = {
    canonical_name: "Coros Sensore Cardiaco Bluetooth Hrm",
    brand: "Coros",
    category: "strap",
    gender: "Unisex",
    best_price: 89.0,
    offers: [{ title: "Coros Sensore Cardiaco Bluetooth HRM", url: "https://example.com/coros-hrm" }],
  };
  const ricambioStrap = {
    canonical_name: "Garmin Ricambio Hrm",
    brand: "Garmin",
    category: "strap",
    gender: "Unisex",
    best_price: 27.49,
    offers: [{ title: "Garmin Ricambio HRM fascia elastica", url: "https://example.com/ricambio-hrm" }],
  };
  const speedSensor = {
    canonical_name: "Garmin Bike Speed Sensor 2 And Cadense",
    brand: "Garmin",
    category: "sensor",
    gender: "Unisex",
    best_price: 69.95,
    offers: [{ title: "Garmin Bike Speed Sensor 2 and Cadense", url: "https://example.com/speed-sensor" }],
  };
  const smartBike = {
    canonical_name: "Zycle Smart Zbike 2 0 2026 Fascia Cardio Zycle Zcore",
    brand: "Zycle",
    category: "gps_watch",
    gender: "Unisex",
    best_price: 1396.0,
    offers: [{ title: "Zycle Smart Zbike 2.0 2026 + Fascia Cardio", url: "https://example.com/zbike" }],
  };
  const watch = {
    canonical_name: "Garmin Venu Sq2",
    brand: "Garmin",
    category: "gps_watch",
    gender: "Unisex",
    best_price: 179.99,
    offers: [{ title: "Garmin Venu Sq2 Smartwatch GPS", url: "https://example.com/venu-sq2" }],
  };

  assertEq(isProductCompatible(realHrm200, "heart_rate_monitor", "Fascia cardio Garmin"), true, "Garmin HRM 200 accepted");
  assertEq(isProductCompatible(corosStrapCatHrm, "heart_rate_monitor", "Fascia cardio Coros"), true, "Coros HRM accepted even in strap category");
  assertEq(isProductCompatible(ricambioStrap, "heart_rate_monitor", "Fascia cardio Garmin"), false, "Replacement strap rejected");
  assertEq(isProductCompatible(speedSensor, "heart_rate_monitor", "Fascia cardio Garmin"), false, "Cycling speed/cadence sensor rejected");
  assertEq(isProductCompatible(smartBike, "heart_rate_monitor", "Fascia cardio"), false, "Smart bike bundle rejected");
  assertEq(isProductCompatible(watch, "heart_rate_monitor", "Fascia cardio Garmin"), false, "Garmin Venu Sq2 watch rejected");
  assertEq(normalizeQueryTypos("Fascia cardo Garmin"), "fascia cardio Garmin", "Typo normalized cleanly");
});
