import re
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
from fitmatch.models import Offer, MatchedProductGroup

KNOWN_BRANDS = [
    # Top Running & Athletic Brands
    "nike", "adidas", "asics", "brooks", "hoka", "on running", "on", "saucony",
    "puma", "new balance", "mizuno", "under armour", "salomon", "altra", "la sportiva",
    "scarpa", "dynafit", "inov-8", "topo athletic", "joma", "newton", "craft", "diadora",
    "nnormal", "reebok", "veja", "scott", "merrell", "361", "karhu", "ronhill",

    # Technical Running & Outdoor Apparel Brands
    "odlo", "saysky", "maloja", "alé", "x-bionic", "xbionic", "uyn", "2xu",
    "gorewear", "cmp", "karpos", "montura", "ciele", "42k running", "42k", "otso",
    "oxsitis", "raidlight", "bv sport", "sidas", "soar", "satisfy", "tracksmith",
    "regatta", "helly hansen", "haglöfs", "haglofs", "rab", "salewa", "mammut",
    "millet", "the north face", "north face", "patagonia", "columbia", "arc'teryx", "arcteryx",
    "black diamond", "petzl", "leki", "camelbak", "osprey", "deuter", "buff", "compressport",

    # Electronics & Optics
    "garmin", "polar", "suunto", "coros", "amazfit", "wahoo", "bryton", "igpsport", "oakley", "bliz",
    "rudy project", "100%", "shokz", "aftershokz", "huawei",

    # Cycling & Helmets
    "shimano", "poc", "kask", "abus", "castelli", "sportful", "santini", "giro",
    "sidi", "sram", "campagnolo", "met", "tacx", "favero", "assioma", "elite", "chris king",

    # Padel & Tennis
    "bullpadel", "babolat", "head", "wilson", "nox", "starvie", "siux", "dunlop", "kuikma",
    "yonex", "tecnifibre", "prince", "prokennex", "k-swiss", "lotto",

    # Basketball & Team Sports
    "jordan", "air jordan", "spalding", "molten", "anta", "way of wade", "li-ning", "peak", "and1",
    "errea", "macron", "kappa", "givova", "umbro", "reusch", "uhlsport", "mikasa",

    # Winter Sports & Ski / Snow
    "atomic", "rossignol", "nordica", "fischer", "volkl", "völkl", "tecnica", "lange", "dalbello",
    "smith", "uvex", "sweet protection", "burton", "k2", "ortovox", "black crows", "blizzard",
    "dynastar", "elan", "colmar", "spyder",

    # Swim & Triathlon
    "arena", "speedo", "tyr", "jaked", "finis", "zoggs", "cressi", "aqua sphere",

    # Recovery, Fitness & Nutrition
    "therabody", "theragun", "hyperice", "compex", "enervit", "isostar", "sis", "maurten",
    "named sport", "powerbar", "ethic sport", "226ers", "leone 1947",

    # Decathlon Brands
    "decathlon", "kiprun", "evadict", "kalenji", "quechua", "forclaz", "btwin",
    "van rysel", "rockrider", "triban", "domyos", "artengo"
]

STORE_NAMES_LOWER = {
    "mister running", "misterrunning", "alltricks", "top4running", "maxi sport",
    "maxisport", "cisalfa", "cisalfa sport", "running warehouse", "runningwarehouse",
    "deporvillage", "sportler", "nencini", "nencini sport", "df sport specialist",
    "tradeinn", "decathlon", "sportit", "tennis-point", "tennis point",
    "basketball store", "basketballstore", "nonsolosport", "intersport", "intersport italia",
    "bshopzone", "generic", "none"
}

BRAND_ALIASES = {
    "on running": "On",
    "air jordan": "Jordan",
    "völkl": "Völkl",
    "volkl": "Völkl",
    "li-ning": "Li-Ning",
    "k-swiss": "K-Swiss",
    "theragun": "Therabody",
    "north face": "The North Face",
    "the-north-face": "The North Face",
    "under-armour": "Under Armour",
    "arcteryx": "Arc'teryx",
    "kiprun": "Kiprun",
    "kalenji": "Kalenji",
    "xbionic": "X-Bionic",
    "x-bionic": "X-Bionic",
    "42k running": "42K Running",
    "42k": "42K Running",
    "2xu": "2XU",
    "uyn": "UYN",
    "cmp": "CMP",
    "alé": "Alé",
    "igpsport": "iGPSPORT"
}

NON_SPORT_JUNK_PATTERNS = [
    r"\bfurygan\b", r"\bdainese\b", r"\balpinestars\b", r"\brevit\b", r"\brev'?it\b",
    r"\bd3o\s*ghost\b", r"\bmoto(?:cicl\w*|\s*cross)?\b.*\b(?:protezion[ei]|gomitier[ae]|ginocchier[ae]|paraschiena|casco|pantaloni)\b",
    r"\b(?:gomitier[ae]|ginocchier[ae]|paraschiena)\b.*\bmoto(?:cicl\w*|\s*cross)?\b",
    r"\bpantaloni\s+moto\b", r"\bcasco\s+moto\b",
    r"\bvetus\b", r"\bscambiatore\s+calore\b", r"\bmanicotto\s+dalla\s+testata\b",
    r"\bpacchetto\s+(?:gps\s+)?marino\b", r"\bmarine\b.*\b(?:vhf|ecoscandaglio|gps)\b",
    r"\bgarlando\b", r"\bcalciobalilla\b", r"\bbiliardino\b", r"\bparrucca\b", r"\batosa\b",
    r"\bdrake\s*2\s*tex\s*pants\b", r"\bfly\s*racing\b", r"\bkenny\s+(?:casco\s+moto|mascherina)\b",
    r"\bbarbie\b", r"\bbambol[ae]\b", r"\bposter\b", r"\baction\s+figure\b", r"\bfunko\b",
    r"\biphone\s*\d+\b", r"\bbirkenstock\b",
]

ICONIC_MODEL_BRANDS = {
    # Adidas
    "supernova": "Adidas", "adizero": "Adidas", "adios": "Adidas", "boston": "Adidas",
    "takumi": "Adidas", "terrex": "Adidas", "ultraboost": "Adidas", "sl20": "Adidas", "dropset": "Adidas",
    "hyperboost": "Adidas", "evo sl": "Adidas",
    # Nike
    "pegasus": "Nike", "vomero": "Nike", "alphafly": "Nike", "vaporfly": "Nike",
    "invincible": "Nike", "streakfly": "Nike", "infinity": "Nike", "wildhorse": "Nike",
    "zegama": "Nike", "metcon": "Nike",
    # Reebok
    "nano": "Reebok", "nanoflex": "Reebok",
    # Under Armour
    "tribase": "Under Armour",
    # Puma
    "deviate nitro": "Puma", "velocity nitro": "Puma", "magnify nitro": "Puma", "magmax": "Puma", "foreverrun": "Puma", "fast-r": "Puma",
    # Asics
    "nimbus": "Asics", "cumulus": "Asics", "kayano": "Asics", "novablast": "Asics",
    "superblast": "Asics", "metaspeed": "Asics", "magic speed": "Asics", "trabuco": "Asics",
    "gt-2000": "Asics", "gt-1000": "Asics", "fujitrail": "Asics",
    # Brooks
    "ghost": "Brooks", "glycerin": "Brooks", "adrenaline": "Brooks", "hyperion": "Brooks",
    "cascadia": "Brooks", "launch": "Brooks", "catamount": "Brooks", "caldera": "Brooks",
    # Hoka
    "clifton": "Hoka", "bondi": "Hoka", "speedgoat": "Hoka", "mach": "Hoka",
    "arahi": "Hoka", "challenger": "Hoka", "cielo": "Hoka", "rocket x": "Hoka", "mafate": "Hoka",
    # Saucony
    "endorphin": "Saucony", "triumph": "Saucony", "ride": "Saucony", "guide": "Saucony",
    "kinvara": "Saucony", "peregrine": "Saucony", "tempus": "Saucony",
    # Mizuno
    "wave rider": "Mizuno", "wave inspire": "Mizuno", "wave rebellion": "Mizuno", "wave sky": "Mizuno",
    # On
    "cloudmonster": "On", "cloudsurfer": "On", "cloudrunner": "On", "cloudflow": "On",
    "cloudboom": "On", "cloudstratus": "On", "cloudtilt": "On", "cloudeclipse": "On",
    # New Balance
    "fuelcell": "New Balance", "fresh foam": "New Balance", "hierro": "New Balance",
    "sc elite": "New Balance", "supercomp": "New Balance",
    # Garmin
    "forerunner": "Garmin", "fenix": "Garmin", "epix": "Garmin", "instinct": "Garmin",
    "venu": "Garmin", "vivoactive": "Garmin", "edge": "Garmin", "hrm 200": "Garmin", "hrm 600": "Garmin", "hrm-pro": "Garmin",
    # Polar
    "vantage": "Polar", "grit x": "Polar", "pacer": "Polar", "ignite": "Polar",
    # Coros & Suunto
    "pace 3": "Coros", "pace 4": "Coros", "pace pro": "Coros", "apex 2": "Coros", "apex 4": "Coros", "vertix": "Coros",
    "suunto race": "Suunto", "suunto vertical": "Suunto", "suunto run": "Suunto",
    # Salomon
    "speedcross": "Salomon", "sense ride": "Salomon", "pulsar": "Salomon", "xa pro": "Salomon",
    "active skin": "Salomon", "adv skin": "Salomon",
    # Oakley
    "sutro": "Oakley", "radar": "Oakley", "jawbreaker": "Oakley", "encoder": "Oakley",
    # Bullpadel & Tennis
    "hack": "Bullpadel", "vertex": "Bullpadel", "flow": "Bullpadel", "indiga": "Bullpadel",
    "pure drive": "Babolat", "pure aero": "Babolat", "pure strike": "Babolat",
    "pro staff": "Wilson", "ezone": "Yonex", "vcore": "Yonex", "percept": "Yonex",
    # Basketball
    "lebron": "Nike", "giannis": "Nike", "sabrina": "Nike", "luka": "Jordan", "tatum": "Jordan",
    "harden": "Adidas", "curry": "Under Armour", "way of wade": "Li-Ning",
    # Winter Sports
    "hawx": "Atomic", "redster": "Atomic", "speedmachine": "Nordica", "promachine": "Nordica",
    # Wahoo / Tacx
    "kickr": "Wahoo", "elemnt": "Wahoo", "flux": "Tacx", "neo": "Tacx"
}

ARTICLE_PATTERNS: List[Tuple[str, List[str]]] = [
    ("case", [
        r"\bcustodi[ae]\b", r"\bcopertur[ae]\b", r"\bcases?\b", r"\bcovers?\b", r"\bhousse\b",
        r"\bpellicol[ae]\b", r"\bvetro temp[ea]rato\b", r"\bsalvaschermo\b",
        r"\bpanzerglass\b", r"\bprotezion[ei]\s+(?:lo\s+)?schermo\b",
        r"\bidrogel\b", r"\bhydrogel\b", r"\bsportenzia\b"
    ]),
    ("mount", [
        r"\bsupport[oi]\b", r"\bstaff[ae]\b", r"\bmounts?\b", r"\bstaffetta\b", r"\bportaborracc(?:ia|e|ie)\b",
        r"\bflush\s+out\s+front\b", r"\bextended\s+out\b"
    ]),
    ("strap", [
        r"\bcinturin[oi]\b", r"\bstraps?\b", r"\bwristband\b", r"\bbraccialetto\b", r"\bbracelet\b"
    ]),
    ("pack", [
        r"\bpacks?\b", r"\bbundles?\b", r"\bset\b", r"\bkit\b", r"\bcoppia\b", r"\bduo\b"
    ]),
    ("sensor", [
        r"\bfascia\s+cardio\b", r"\bfascia\s+hrm\b", r"\bhrm\b",
        r"\bsensore\s+(?:cardio|cardiaco|frequenza|velocit|cadenza|potenza|falcata)\b",
        r"\bspeed\s+sensor\b", r"\bcadence\s+sensor\b", r"\bheart\s+rate\s+monitor\b",
        r"\btrackr\s+hr\b", r"\btickr\b", r"\bpolar\s+(?:h10|h9|verity|oh1)\b"
    ]),
    ("cycling", [
        r"\bciclocomputer\b", r"\bbike\s+computer\b", r"\bcontachilometri\b", r"\bcontatore\b",
        r"\bgarmin\s+edge\b", r"\bedge\s+(?:130|530|540|550|830|840|1030|1040|1050|explore|mtb)\b",
        r"\bwahoo\s+elemnt\b", r"\bbryton\b", r"\bigpsport\b",
        r"\bdisco\s+freno\b", r"\bpneumatico\s+(?:da\s+)?strada\b", r"\bborsa\s+(?:da\s+)?sella\b",
        r"\bcoperton[ei]\b", r"\bbiciclett[ae]\b", r"\bgravel\b.*\b(?:bike|bici|di2|\d{2})\b",
        r"\bbike\b(?!.*\b(?:short|shirt|biking)\b)", r"\bstrada\b.*\b(?:di2|105|ultegra|dura[\s-]*ace)\b",
        r"\bcyclette\b", r"\bbici\b", r"\bmtb\b(?!.*\b(?:scarp|shoes)\b)", r"\bshimano\b.*\b(?:raggio|cassetta|freno|deragliatore|catena)\b"
    ]),
    ("gps_watch", [
        r"\bsmartwatch\b", r"\borologi[o]?\b", r"\bforerunner\b", r"\bfenix\b",
        r"\bepix\b", r"\binstinct\b", r"\bvenu\b", r"\bvivoactive\b",
        r"\bcardiofrequenzimetr[oi]\b", r"\bapple\s+watch\b",
        r"\bt[\s-]?rex\s*\d\b", r"\bamazfit\b", r"\bcoros\s+(?:pace|apex|vertix|nomad)\b",
        r"\bpolar\s+(?:vantage|pacer|grit|ignite)\b", r"\bsuunto\s+(?:race|vertical|9|peak|run)\b"
    ]),
    ("nutrition", [
        r"\bgel\s+energetic[oi]\b", r"\bbevand[ae]\s+energetic[ae]\b", r"\bisotonic[aoe]?\b", r"\bpowder\s+iso\b",
        r"\benervit\b", r"\bisocarb\b", r"\bbarrett[ae]\b",
        r"\bmaltodestrin[ae]\b", r"\bsali\s+minerali\b", r"\bmaurten\b", r"\b226ers\b",
        r"\bintegrator[ei]\b", r"\bwhey\b", r"\bproteine?\b", r"\beletr?oliti\b", r"\bcreatina\b", r"\bomega\s*3\b", r"\baminoacid[io]?\b"
    ]),
    ("hydration", [
        r"\bzain[oi]\b", r"\bbackpack\b", r"\bduffel\b", r"\bborson[ei]\b",
        r"\bactive\s+skin\b", r"\badv\s+skin\b", r"\bsoft\s*flask\b",
        r"\bflask\b", r"\bborracc(?:ia|e|ie)\b", r"\bsacca\s+idrica\b", r"\bcamelbak\b",
        r"\bbottle\b", r"\bgilet\s+(?:da\s+)?(?:trail|idratazione|running|corsa)\b"
    ]),
    ("swim", [
        r"\bocchialin[oi]\b", r"\bocchial[ie]\s*(?:da\s*)?nuoto\b", r"\bcuffi[ae]\s*(?:da\s*)?nuoto\b",
        r"\bcostum[ei]\s*(?:da\s*)?bagno\b", r"\bcostum[ei]\s*(?:da\s*)?nuoto\b", r"\bboxer\s*(?:da\s*)?bagno\b",
        r"\bslip\s*(?:da\s*)?bagno\b", r"\bfastskin\b", r"\bopenwater\b",
        r"\bcobra\s+ultra\b", r"\bpinn[ae]\s*(?:da\s*)?nuoto\b", r"\btavolett[ae]\s*(?:da\s*)?nuoto\b",
        r"\bboccaglio\b", r"\bmuta\s*(?:nuoto|triathlon|acque|vitalis)\b", r"\barena\b.*\b(?:nuoto|swim|swipe|mirror|python|tracks|air|costume)\b",
        r"\bspeedo\b.*\b(?:nuoto|swim|biofuse|futura|fastskin|vengeance|aquapulse|costume|bagno)\b",
        r"\btyr\b.*\b(?:nuoto|swim|ops)\b", r"\bnike\s+swim\b"
    ]),
    ("eyewear", [
        r"\bocchial[ie]\b", r"\bsunglasses\b", r"\blent[ie]\b", r"\bmascher[ae]\b",
        r"\bsutro\b", r"\bjawbreaker\b", r"\bradar\s+ev\b", r"\bshow\s+x\d\b"
    ]),
    ("racket", [
        r"\bpadel\b", r"\bpala\b", r"\bpalas\b", r"\bracchett[ae]\s*(?:da\s*)?padel\b",
        r"\b(?:vertex|hack|at10|ml10|metalbone|adipower|technical\s+viper|air\s+viper|counter\s+viper)\b",
        r"\btubo\s+palle\b", r"\bpall[ae]\s+padel\b", r"\bovergrip\b"
    ]),
    ("tennis", [
        r"\bracchett[ae]\s*(?:da\s*)?tennis\b", r"\bpallin[ae]\s*(?:da\s*)?tennis\b", r"\bpall[ae]\s+tennis\b",
        r"\bpure\s+(?:drive|aero|strike)\b", r"\bpro\s+staff\b", r"\bblade\s+(?:98|100|v\d)\b",
        r"\bezone\b", r"\bvcore\b", r"\bpercept\b", r"\bt-?fight\b",
        r"\bmatass[ae]\b", r"\bincordatur[ae]\b", r"\bborsone\s+tennis\b", r"\bantivibrazioni\b",
        r"^(?!.*\b(?:scarp[ae]|shoes?|sneakers?|pantaloncin[oi]|shorts|gonna|magli[ae]|canott[ae])\b).*\btennis\b"
    ]),
    ("basketball", [
        r"\b(?:pallon[ei]\s*(?:da\s*)?basket|canestro|tabellone\s+basket|spalding|molten)\b",
        r"\b(?:canott[ae]|magli[ae])\s*(?:nba|basket)\b", r"\bway\s+of\s+wade\b",
        r"^(?!.*\b(?:scarp[ae]|shoes?|sneakers?|pantaloncin[oi]|shorts|magli[ae]|felp[ae]|calz[ae])\b).*\b(?:basket(?:ball)?|pallacanestro)\b"
    ]),
    ("winter_sports", [
        r"\bsci(?:alpinismo|are)?\b", r"\bsnowboard\b", r"\bscarpon[ei]\s+(?:da\s+)?sci\b",
        r"\bmascher[ae]\s+(?:da\s+)?sci\b", r"\bcasc[oi]\s+(?:da\s+)?sci\b",
        r"\battacch[oi]\s+sci\b", r"\bciaspole\b", r"\bpelli\s+di\s+foca\b", r"\barva\b",
        r"\b(?:freeride|alpine\s+ski|hawx|redster|speedmachine|promachine|hero\s+world\s+cup)\b",
        r"\b(?:giacc[ae]|pantalon[ei]|tuta)\s+(?:da\s+)?(?:sci|neve|snow)\b"
    ]),
    ("trainer", [
        r"\brull[oi]\b", r"\bsmart trainer\b", r"\bkickr\b", r"\bflux\b", r"\bsuito\b", r"\bdireto\b"
    ]),
    ("football_boots", [
        r"\bscarp[ae]\s*(?:da\s*)?calcio\b", r"\bscarp[ae]\s*(?:da\s*)?calcetto\b",
        r"\bscarpin[oi]\b", r"\bcalcetto\b", r"\bfutsal\b",
        r"\btop\s+sala\b", r"\btop\s+flex\b",
        r"\b(?:mercurial|superfly|vapor|tiempo|phantom|predator|copa\s*(?:pure|gloro|mundial)|kaiser\s*5|future\s*[789]|magnetico|f50|king\s+(?:ultimate|pro|match))\b",
        r"\b(?:fg|ag|mg|sg|tf|turf|indoor)\b.*\b(?:calcio|futsal|match|league|academy|pro|elite|select)\b",
        r"\b(?:calcio|futsal|magnetico|predator|mercurial|tiempo|phantom|morelia)\b.*\b(?:fg|ag|mg|sg|tf|turf|indoor)\b",
    ]),
    ("jacket", [
        r"\bgiacc(?:a|he)\b", r"\bgiubbin[oi]\b", r"\bgiubbott[oi]\b", r"\bjackets?\b", r"\bjkt\b",
        r"\bantivento\b", r"\bwindbreaker\b", r"\bwindstopper\b", r"\bgilet\b", r"\bvest\b",
        r"\banorak\b", r"\bshell\b", r"\bpiumin[oi]\b", r"\bcappott[oi]\b", r"\bparka\b",
        r"\bbetter\s+sweater\b", r"\bdown\s+hooded\b", r"\b2[\.,]5\s*layer\b"
    ]),
    ("socks", [
        r"\bcalz[ae]\b", r"\bcalzin[oi]\b", r"\bsocks?\b", r"\bcopriscarpe\b",
        r"\bcushioned\s+ankle\b", r"\bgambalett[io]\b", r"\blight\s+crew\b"
    ]),
    ("pants", [
        r"\bpantalon[ie]\b", r"\bpantaloncin[oi]\b", r"\bshorts?\b", r"\btights?\b",
        r"\bleggings?\b", r"\bcapri\b", r"\bcalzamagli[ae]\b", r"\bbermuda\b", r"\bsprinter\b",
        r"\btrack\s*pants?\b", r"\bsweatpants?\b", r"\bjoggers?\b",
        r"\bsalopette\b", r"\btuta\s+gara\b", r"\bciclista\s+seamless\b", r"\bcoscial[ei]\b",
        r"\bgonn[ae]\b", r"\bskirts?\b", r"\b2\s*in\s*1\b", r"\b2in1\b",
        r"(?<![\.,\d])\b[34579]\s*(?:inch|in\b|''|\´\´)", r"\badizero\s+pacer\b"
    ]),
    ("top", [
        r"\bmagli[ae]\b", r"\bmagliett[ae]\b", r"\bt-?shirts?\b", r"\bshirts?\b", r"\bcanott[ae]\b",
        r"\bsinglets?\b", r"\bsnglt\b", r"\btank\b", r"\bcrop\b", r"\bcropped\b", r"\btee\b",
        r"\btops?\b(?!\s+(?:sala|flex|ten|gun))", r"\bfelp[ae]\b", r"\bhoodie\b", r"\blong\s*sleeve\b",
        r"\bpile\b", r"\bmaglion[ei]\b", r"\bpullover\b", r"\bsweater\b",
        r"\bshort\s*sleeve\b", r"\bsleeveless\b", r"\bmanic(?:a|he)\s+lung(?:a|he)\b",
        r"\bmanic(?:a|he)\s+cort(?:a|e)\b", r"\bjersey\b", r"\bpolo\b", r"\breggisen[oi]\b", r"\bbra\b",
        r"\b(?:home|away|3rd|third)\s+(?:replica|stadium|match)\b", r"\bsenza\s+maniche\b", r"\bbody\s+\d+\s*cm\b",
        r"\b1\s*[/\s]\s*[24]\s*zip\b", r"\bhalf\s*zip\b", r"\bquarter\s*zip\b", r"\bpolare\b", r"\bfleece\b",
        r"\btech\s+fleece\b", r"\bdri[\s-]*fit\s+park\b"
    ]),
    ("gear", [
        r"\btheragun\b", r"\bpistola\s+(?:per\s+)?massaggi\b", r"\bstimolatore\s+muscolare\b",
        r"\bcasc(?:o|hi)\b", r"\bhelmet\b", r"\bcappellin[oi]\b", r"\bcappell[oi]\b", r"\bcap\b",
        r"\bberr?ett[oi]\b", r"\bbeanie\b", r"\bvisier[ae]\b", r"\bfasci[ae]\b",
        r"\bguant[oi]\b", r"\bgloves?\b", r"\bscaldacollo\b", r"\bgirocollo\b", r"\bneckwear\b",
        r"\bscialle\b", r"\bsciarpa\b", r"\bscaldamani\b", r"\bpolsin[oi]\b", r"\bmanicotti\b", r"\bgambali\b",
        r"\btelo\b", r"\basciugaman[oi]\b", r"\bmanubri[o]?\b", r"\bkettlebell\b",
        r"\bcintur[ae]\b", r"\bbastoncini\b", r"\bshampoo\b", r"\bsterzo\b",
        r"\bpignoni\b", r"\bguarnitura\b", r"\bpedal[ei]\b",
        r"\bnippl[oi]\b", r"\btacchett[ae]\b", r"\bparastinchi\b", r"\bginocchier[ae]\b", r"\bgomitier[ae]\b",
        r"\bpallone\b", r"\bthermonet\b", r"\bmarsupi[oi]\b", r"\brun\s+belt\b", r"\btravel\s+bag\b"
    ]),
    ("shoes", [
        r"\bscarp[ae]\b", r"\bshoes?\b", r"\bsneakers?\b", r"\bcalzatur[ae]\b", r"\bfootwear\b",
        r"\bstival[ie]\b", r"\bstivalett[oi]\b", r"\bciabatt[ae]\b", r"\bchiodat[ae]\b",
        r"\bscarpon[ie]\b", r"\bscarpett[ae]\b", r"\bslide\b", r"\binfradito\b", r"\bklapki\b",
        r"\b(?:adistar|superstar|stan\s+smith|gazelle|samba|spezial|rs[\s-]*x|shox|air\s+max|air\s+force|vomero|pegasus|ultraboost|supernova|adizero|boston|duramo|galaxy|hyperboost|hyperwarp|velociti|kype|morelia|chuck\s+taylor|all\s+star|slip[\s-]*ins|suola|gel[\s-]?(?:nimbus|kayano|cumulus|pulse|excite|contend|venture|sonoma|trabuco|resolution)|gt[\s-]?(?:1000|2000)|novablast|superblast|court\s*ff|solution\s+speed|barricade|madrix|wave\s+(?:rider|sky|inspire|horizon|rebellion|daichi)|clifton|bondi|rincon|arahi|speedgoat|mach\s*\d|ghost\s*\d+|glycerin|adrenaline|cascadia|endorphin|kinvara|peregrine|triumph|cloudmonster|cloudsurfer|cloudrunner|cloudboom|cloudstratus|cloudflow|rebel\s*v\d|1080|880|860|deviate\s+nitro|velocity\s+nitro|magnify\s+nitro|foreverrun|lone\s+peak|torin|olympus|bushido|ultra\s+raptor|speedcross|sense\s+ride|alphafly|vaporfly|metaspeed|zoom\s+victory|nike\s+victory)\b"
    ])
]

TECH_FABRICS = [
    "dri-fit adv", "dri-fit", "dri fit", "drifit", "aeroready", "heatgear", "coldgear",
    "iso-chill", "climalite", "therma-fit", "tech fleece", "climacool", "air zoom",
    "air", "gel", "fuelcell", "fresh foam x", "fresh foam", "super comp", "supercomp"
]

STOPWORDS = {
    "scarpe", "scarpa", "shoes", "shoe", "sneakers", "calzature", "footwear", "running", "corsa", "asfalto",
    "uomo", "donna", "unisex", "bambino", "bambina", "junior", "ragazzo", "ragazza",
    "m", "w", "men", "women", "mens", "womens", "wmns", "zm",
    "smartwatch", "orologio", "gps", "multisport", "multifunzione", "sportivo", "sportiva", "sportive", "sportivi",
    "cardiofrequenzimetro", "ciclocomputer", "neutre", "neutri", "ammortizzate", "ammortizzata",
    "pistola", "massaggi", "stimolatore", "muscolare",
    "custodia", "silicone", "housse", "cover", "pack", "bundle", "kit", "cinturino", "strap",
    "allenamento", "palestra", "training", "workout", "fitness",
    "performance", "sportswear", "originals", "athletics", "athletic", "road",
    "per", "di", "con", "e", "the", "in", "de", "ed", "da", "a", "la", "il", "le", "un", "una",
    "nero", "nera", "neri", "nere", "grigio", "grigia", "grigi", "grigie", "bianco", "bianca", "bianchi", "bianche",
    "rosso", "rossa", "rossi", "rosse", "blu", "giallo", "gialla", "gialle", "fluor", "verde", "verdi", "rosa", "viola",
    "beige", "arancione", "azzurro", "azzurra", "argento", "oro", "bordeaux", "turchese", "corallo",
    "militare", "lilla", "acqua", "oliva", "chiaro", "scuro", "multicolore", "multicolor",
    "naval", "cobalt", "whitestone", "mist", "lime", "menta",
    "silver", "white", "black", "grey", "anthracite", "smoke", "core"
}

_AMBIGUOUS_BRANDS = {"scarpa", "elite", "on", "head", "polar"}
_PRIMARY_BRANDS = [b for b in KNOWN_BRANDS if b not in _AMBIGUOUS_BRANDS]
_PRIMARY_BRAND_PATTERNS: List[Tuple[str, re.Pattern]] = [
    (b, re.compile(rf"\b{re.escape(b)}\b")) for b in _PRIMARY_BRANDS
]
_PRIMARY_BRAND_PATTERNS_DESC: List[Tuple[str, re.Pattern]] = [
    (b, re.compile(rf"\b{re.escape(b)}\b"))
    for b in sorted(_PRIMARY_BRANDS, key=len, reverse=True)
]
_COMPILED_NON_SPORT_JUNK: List[re.Pattern] = [re.compile(p) for p in NON_SPORT_JUNK_PATTERNS]
_COMPILED_ARTICLE_PATTERNS: List[Tuple[str, List[re.Pattern]]] = [
    (atype, [re.compile(p) for p in patterns]) for atype, patterns in ARTICLE_PATTERNS
]
_TECH_FABRIC_PATTERNS: List[re.Pattern] = [
    re.compile(rf"\b{re.escape(tf)}\b")
    for tf in sorted(TECH_FABRICS, key=len, reverse=True)
    if tf not in ("super comp", "supercomp")
]

_GENDER_JUNIOR_RE = re.compile(r"\b(bambin[oi]|junior|jr|kids?|boy|girl)\b")
_GENDER_FEMALE_RE = re.compile(
    r"(?:\b(?:donna|donne|woman|women|womens|wmns|femme|lady|ladies|damen|mujer|w)\b|/(?:donna|woman|women|womens|wmns|femme)/)"
)
_GENDER_MALE_RE = re.compile(
    r"(?:\b(?:uomo|uomini|men|mens|homme|herren|hombre|m)\b|/(?:uomo|men|mens|homme)/)"
)
_SPLIT_DASH_RE = re.compile(r"\s+[-–—|]\s+")
_APPLE_WATCH_RE = re.compile(r"\bapple\s+(?:watch|series\s+\d+)\b")
_EDGE_MODEL_RE = re.compile(r"\bedge\s+(?:130|530|540|550|830|840|1030|1040|1050|explore|mtb)\b")
_FALLBACK_SHOE_HINT_RE = re.compile(
    r"\b(run|running|runner|trail|gore[\s-]*tex|gtx|maratona|crossfit|hyrox|mtb\s*boa|flat\s*pedal|gravel\s*\w*\s*lace)\b"
)
_HALF_ZIP_RE = re.compile(r"\b1\s*/\s*2\s*zip\b", flags=re.IGNORECASE)
_LONG_SLEEVE_RE = re.compile(r"\ba\s+maniche\s+lunghe\b|\bmaniche\s+lunghe\b", flags=re.IGNORECASE)
_SHORT_SLEEVE_RE = re.compile(r"\ba\s+maniche\s+corte\b|\bmaniche\s+corte\b", flags=re.IGNORECASE)
_SKU_CODE_RE = re.compile(r"\b[A-Za-z0-9]{4,10}[-_][A-Za-z0-9]{2,6}\b")
_ALNUM_WORD_RE = re.compile(r"\b[a-zA-Z0-9]+\b")
_GORETEX_RE = re.compile(r"\bgore[\s-]*tex\b|\bgoretex\b")
_SUPERCOMP_RE = re.compile(r"\bsuper\s+comp\b")
_PARENS_RE = re.compile(r"\(.*?\)")
_PUNCT_RE = re.compile(r"[^\w\s]")
_LONG_DIGITS_RE = re.compile(r"^\d{6,}$")
_ICONIC_MODEL_PATTERNS: List[Tuple[str, str, re.Pattern]] = [
    (model_sub, brand_name, re.compile(rf"\b{re.escape(model_sub)}\b"))
    for model_sub, brand_name in ICONIC_MODEL_BRANDS.items()
]
_GENERIC_TITLE_WORDS = STOPWORDS.union(
    {"running", "corsa", "trail", "asics", "nike", "adidas", "mizuno", "brooks", "hoka", "altra", "new", "balance", "saucony", "on"}
)
_DIGIT_RE = re.compile(r"\d")
_XBIONIC_RE = re.compile(r"\bx[\s-]bionic\b")
_TREX_RE = re.compile(r"\bt[\s-]rex\b")
_TSHIRT_RE = re.compile(r"\bt[\s-]shirt\b")
_WORD_SCARPA_RE = re.compile(r"\bscarpa\b")
_WORD_ELITE_RE = re.compile(r"\belite\b")
_WORD_ON_RE = re.compile(r"\bon\b")
_WORD_HEAD_RE = re.compile(r"\bhead\b")
_WORD_POLAR_RE = re.compile(r"\bpolar\b")


class ProductNormalizer:
    """
    Advanced Anti-Mismatch Engine:
    Categorizes article types, extracts exact model versions, eliminates accessories
    from device clusters, and dynamically rejects price outliers.
    """

    @staticmethod
    def extract_gender(title: str, url: str = "") -> str:
        """Detect gender category from text or URL."""
        combined = f"{title} {url}".lower()
        if _GENDER_JUNIOR_RE.search(combined):
            return "Junior"
        has_female = bool(_GENDER_FEMALE_RE.search(combined))
        has_male = bool(_GENDER_MALE_RE.search(combined))
        if has_female and has_male:
            return "Uomo | Donna"
        if has_female:
            return "Donna"
        if has_male:
            return "Uomo"
        return "Unisex"

    @staticmethod
    def is_non_sport_junk(title: str) -> bool:
        """Detect non-sporting items (motorcycle armor, marine hardware, foosball tables, costumes)."""
        tl = (title or "").lower()
        return any(pat.search(tl) for pat in _COMPILED_NON_SPORT_JUNK)

    @classmethod
    def extract_brand(cls, title: str, existing_brand: Optional[str] = None) -> Optional[str]:
        """Detect standard canonical brand name from title or existing hint, avoiding false-positive collisions."""
        lower_title = (title or "").lower()
        is_junk = cls.is_non_sport_junk(lower_title)

        # 1. Check non-ambiguous known brands in the main title (before colorway dash) first, earliest position wins
        main_part = _SPLIT_DASH_RE.split(lower_title)[0]
        best_match: Optional[Tuple[int, int, str]] = None
        for b, b_pat in _PRIMARY_BRAND_PATTERNS:
            m = b_pat.search(main_part)
            if m:
                cand = (m.start(), -len(b), b)
                if best_match is None or cand < best_match:
                    best_match = cand
        if best_match:
            b = best_match[2]
            return BRAND_ALIASES.get(b, b.title())

        for b, b_pat in _PRIMARY_BRAND_PATTERNS_DESC:
            if b_pat.search(lower_title):
                return BRAND_ALIASES.get(b, b.title())

        if _APPLE_WATCH_RE.search(lower_title):
            return "Apple"

        # 2. Check existing_brand if valid and not a store name or ambiguous false positive
        if existing_brand:
            eb_lower = existing_brand.strip().lower()
            if eb_lower not in STORE_NAMES_LOWER and eb_lower not in _AMBIGUOUS_BRANDS:
                if eb_lower in BRAND_ALIASES:
                    return BRAND_ALIASES[eb_lower]
                if eb_lower in _PRIMARY_BRANDS:
                    return BRAND_ALIASES.get(eb_lower, eb_lower.title())

        # 3. Check iconic model mapping (skip if item is motorcycle/marine/bike-headset junk)
        is_bike_headset = any(w in lower_title for w in ("sterzo", "chris king", "headset", "nothreadset", "griplock", "is42"))
        if not is_junk:
            is_birkenstock_clog = any(w in lower_title for w in ("birkenstock", "suede", "oiled", "eva", "ciabatt", "zoccol"))
            for model_sub, brand_name, m_pat in _ICONIC_MODEL_PATTERNS:
                if model_sub == "dropset" and is_bike_headset:
                    continue
                if model_sub == "boston" and is_birkenstock_clog:
                    continue
                if m_pat.search(lower_title):
                    return brand_name
        if "adizero" in lower_title:
            return "Adidas"

        # 4. Disambiguate ambiguous brand names ('scarpa', 'elite', 'on', 'head')
        if _WORD_SCARPA_RE.search(lower_title):
            scarpa_models = {
                "ribelle", "mojito", "spin", "golden gate", "mescalito", "atom", "chimera",
                "drago", "phantom", "zen", "boostic", "instinct", "marmolada", "rapid", "rush",
                "kinesis", "maestrale", "alien"
            }
            if any(m in lower_title for m in scarpa_models) or any(
                w in lower_title for w in ("arrampicata", "alpinismo", "climbing", "scarpette", "scarponi")
            ):
                return "Scarpa"

        if _WORD_ELITE_RE.search(lower_title):
            elite_cycling_terms = {
                "rullo", "rulli", "trainer", "suito", "direto", "tuo", "qubo", "novo",
                "arion", "portaborraccia", "borraccia", "fly tex", "custom race", "sterzo"
            }
            if any(w in lower_title for w in elite_cycling_terms):
                return "Elite"

        if _WORD_ON_RE.search(lower_title):
            if lower_title.startswith("on ") or any(w in lower_title for w in ("cloud", "roger", "on running")):
                return "On"

        if _WORD_HEAD_RE.search(lower_title):
            if any(w in lower_title for w in ("padel", "racchetta", "pala", "speed", "extreme", "delta", "gravity", "radical", "tennis", "sci")):
                return "Head"

        if _WORD_POLAR_RE.search(lower_title):
            if not any(w in lower_title for w in ("felpa", "pile", "giacca", "fleece", "lacoste", "columbia", "cardigan", "scaldacollo", "casco", "kask", "poc", "roxy", "cappuccio", "rain", "polar white", "cinghia")):
                return "Polar"

        if existing_brand and existing_brand.strip().lower() not in STORE_NAMES_LOWER and existing_brand.strip().lower() != "elite":
            eb_low = existing_brand.strip().lower()
            if eb_low in BRAND_ALIASES:
                return BRAND_ALIASES[eb_low]
            return existing_brand.strip().capitalize()
        return None

    @classmethod
    def detect_article_type(cls, title: str) -> str:
        """Categorize item into article type (e.g. case, strap, pack, jacket, pants, top, swim, football_boots, shoes, gps_watch, gear, non_sport)."""
        tl = (title or "").lower()
        if cls.is_non_sport_junk(tl):
            return "non_sport"
        for atype, patterns in _COMPILED_ARTICLE_PATTERNS:
            for pattern in patterns:
                if pattern.search(tl):
                    return atype
        # Check if it matches any iconic shoe/watch model before defaulting
        for model_sub, brand_name, m_pat in _ICONIC_MODEL_PATTERNS:
            if m_pat.search(tl):
                if brand_name in ("Garmin", "Polar", "Coros", "Suunto"):
                    if model_sub in ("hrm 200", "hrm 600", "hrm-pro"):
                        return "sensor"
                    if model_sub == "edge":
                        if "garmin" in tl or _EDGE_MODEL_RE.search(tl):
                            return "cycling"
                        continue
                    return "gps_watch"
                if brand_name == "Oakley":
                    return "eyewear"
                if brand_name == "Bullpadel":
                    if "bullpadel" in tl or "padel" in tl or "pala" in tl or "racchett" in tl:
                        return "racket"
                    continue
                if brand_name in ("Babolat", "Wilson", "Yonex") and model_sub in ("pure drive", "pure aero", "pure strike", "pro staff", "ezone", "vcore", "percept"):
                    return "tennis"
                if model_sub in ("lebron", "giannis", "sabrina", "luka", "tatum", "harden", "curry", "way of wade"):
                    return "basketball"
                if model_sub in ("hawx", "redster", "speedmachine", "promachine"):
                    return "winter_sports"
                if brand_name in ("Wahoo", "Tacx"):
                    if brand_name.lower() in tl or "trainer" in tl or "rullo" in tl or "rulli" in tl:
                        return "trainer"
                    continue
                return "shoes"
        # Do NOT blindly dump unknown items (neckwear, bike parts, accessories) into 'shoes'
        if _FALLBACK_SHOE_HINT_RE.search(tl):
            return "shoes"
        return "gear"

    @classmethod
    def clean_title(cls, title: str, brand: Optional[str] = None) -> Tuple[str, Optional[str]]:
        """Splits off colorway/descriptions and strips noise words while preserving model version and garment type."""
        # Normalize fractions like 1/2 zip before splitting on slashes/punctuation
        norm_title = _HALF_ZIP_RE.sub("half zip", title or "")
        norm_title = _LONG_SLEEVE_RE.sub("manica lunga", norm_title)
        norm_title = _SHORT_SLEEVE_RE.sub("manica corta", norm_title)

        # Split on dash or pipe that separates model from color description or category breadcrumb
        parts = _SPLIT_DASH_RE.split(norm_title)
        base = parts[0]
        colorway = parts[-1].strip() if len(parts) > 1 else None

        # Check if parts[0] is an internal SKU/MPN code (e.g. Decathlon "NIKE FQ0912-400 — Scarpe da running uomo Nike Pegasus 41"),
        # a store name, or a generic category breadcrumb
        if len(parts) > 1:
            is_sku_code = bool(_SKU_CODE_RE.search(parts[0]))
            is_store_name = any(s in parts[0].lower() for s in ("decathlon", "cisalfa", "maxisport", "nencini", "top4running", "misterrunning"))
            tokens_0 = set(_ALNUM_WORD_RE.findall(parts[0].lower()))
            if is_sku_code or is_store_name or tokens_0.issubset(_GENERIC_TITLE_WORDS):
                best_part = None
                for p in parts[1:]:
                    p_toks = set(_ALNUM_WORD_RE.findall(p.lower()))
                    non_stop = p_toks - STOPWORDS
                    if non_stop:
                        if _DIGIT_RE.search(p) or any(k in p.lower() for k in ICONIC_MODEL_BRANDS):
                            best_part = p
                            break
                        elif best_part is None:
                            best_part = p
                if best_part:
                    base = best_part
                    colorway = parts[0].strip()

        text = base.lower()
        text = _PARENS_RE.sub("", text)
        # Preserve x-bionic and gt-2000 compounds before stripping punctuation
        text = _XBIONIC_RE.sub("xbionic", text)
        text = _TREX_RE.sub("trex", text)
        text = _TSHIRT_RE.sub("tshirt", text)
        text = _PUNCT_RE.sub(" ", text)

        # Remove all occurrences of the brand
        if brand:
            b_low = brand.lower()
            text = re.sub(rf"\b{re.escape(b_low)}\b", " ", text)
            if b_low == "x-bionic":
                text = text.replace("xbionic", " ")
            for p in b_low.split():
                if len(p) > 2:
                    text = re.sub(rf"\b{re.escape(p)}\b", " ", text)

        # Standardize known compounds
        text = _GORETEX_RE.sub("gtx", text)
        text = _SUPERCOMP_RE.sub("supercomp", text)
        for tf_pat in _TECH_FABRIC_PATTERNS:
            text = tf_pat.sub(" ", text)

        tokens = text.split()
        cleaned_tokens = []
        for idx, t in enumerate(tokens):
            if t in STOPWORDS or _LONG_DIGITS_RE.match(t) or t == "s":
                continue
            # Drop connector 'x' in "Puma x Hyrox"
            if t == "x" and idx + 1 < len(tokens) and tokens[idx + 1] == "hyrox":
                continue
            cleaned_tokens.append(t)

        # Deduplicate consecutive identical tokens
        dedup_tokens = []
        for t in cleaned_tokens:
            if not dedup_tokens or dedup_tokens[-1] != t:
                dedup_tokens.append(t)

        return " ".join(dedup_tokens).strip(), colorway

    @classmethod
    def build_canonical_display_name(cls, title: str, brand: Optional[str] = None) -> str:
        """Build a clean, complete, human-readable canonical product title from an offer title."""
        eff_brand = cls.extract_brand(title, brand)
        cleaned_base, _ = cls.clean_title(title, eff_brand)
        if not cleaned_base:
            cleaned_base = re.sub(r"\s+", " ", (title or "").strip())
        canonical = f"{eff_brand} {cleaned_base.title()}" if eff_brand and eff_brand.lower() not in cleaned_base.lower() else cleaned_base.title()
        if eff_brand:
            canonical = re.sub(r"^(" + re.escape(eff_brand) + r"\s+)+", f"{eff_brand} ", canonical, flags=re.IGNORECASE).strip()
        return canonical

    @classmethod
    def extract_cluster_key(cls, offer: Offer) -> str:
        """
        Generates a strictly partitioned cluster key:
        Prevents cases/straps/packs from sharing keys with core devices or shoes,
        and retains exact model generation numbers (e.g. 965, 55, 41, Pro 5, v14, Hyrox).
        If a clean barcode/GTIN is present, ensures 100% deterministic grouping.
        """
        if offer.barcode and len(offer.barcode.strip()) >= 8:
            return f"barcode:{offer.barcode.strip()}"

        brand = cls.extract_brand(offer.title, offer.brand) or "Generic"
        gender = cls.extract_gender(offer.title, offer.url)
        art_type = cls.detect_article_type(offer.title)
        url_lower = (offer.url or "").lower()
        if art_type != "case" and any(k in url_lower for k in ("copertura", "custodia", "silicone-case", "pellicola")):
            art_type = "case"
        cleaned_base, _ = cls.clean_title(offer.title, brand)

        tokens = cleaned_base.split()
        model_parts: List[str] = []
        i = 0

        important_qualifiers = {
            "pro", "music", "elite", "plus", "s", "x", "max", "tr", "gtx", "trail",
            "hyrox", "solar", "amp", "se", "power", "pwr", "warm", "winter"
        }

        while i < len(tokens):
            t = tokens[i]
            if t == "hyrox":
                i += 1
                continue
            model_parts.append(t)
            # Only treat digits, v+digits, or multi-char Roman numerals (ii, iii, iv, vi...) as version numbers
            # NEVER treat single 'x', 'i', 'v' as Roman numerals (fixes 'Puma x Hyrox', 'X-Bionic', etc.)
            is_num = bool(re.search(r"\d", t) or re.match(r"^(v\d+|ii|iii|iv|vi|vii|viii|ix|xi|xii|xiii|xiv|xv)$", t))
            if is_num:
                # Retain model qualifiers following a number (e.g. 'deviate nitro 4 hyrox', '1080 v15', 'adios pro 4')
                while i + 1 < len(tokens) and tokens[i + 1] in important_qualifiers:
                    if tokens[i + 1] != "hyrox":
                        model_parts.append(tokens[i + 1])
                    i += 1
                break
            elif t in ("pro", "elite", "prime", "relief") and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if re.search(r"\d", nxt) or nxt in ("plus", "max", "ultra", "v6", "v5", "v4", "trail", "hyrox"):
                    if nxt != "hyrox":
                        model_parts.append(nxt)
                    i += 1
                    break
            elif len(model_parts) >= 4:
                for rem_t in tokens[i + 1:]:
                    if (rem_t in ("gtx", "lunga", "sleeve", "warm", "merino", "zip") or bool(re.search(r"\d", rem_t))) and rem_t not in model_parts:
                        model_parts.append(rem_t)
                break
            i += 1

        if "hyrox" in tokens and "hyrox" not in model_parts:
            model_parts.append("hyrox")

        model_key = " ".join(model_parts).strip() if model_parts else "general"

        # Devices, electronics, eyewear, cycling trainers, rackets & gear are genderless
        if art_type in ("gps_watch", "cycling", "gear", "eyewear", "racket", "trainer", "sensor", "mount", "case", "strap", "pack", "nutrition", "hydration"):
            return f"{brand.lower()} {model_key} [{art_type}]"

        # Racing super-shoes (e.g. adios pro, alphafly, vaporfly, metaspeed, cielo, vanish, endorphin elite, sc elite)
        # are inherently unisex models with identical specs across genders
        is_racing_super_shoe = any(
            rw in model_key.lower() for rw in ("adios pro", "alphafly", "vaporfly", "metaspeed", "cielo", "vanish", "endorphin elite", "sc elite")
        )
        if is_racing_super_shoe:
            return f"{brand.lower()} {model_key} [{art_type}]"

        # Standard adult shoes: bridge 'Unisex' and 'Uomo' into standard adult cluster
        # (while preserving distinct 'Donna' and 'Junior' if women/kids specific)
        cluster_gender = gender
        if cluster_gender in ("Unisex", "Uomo"):
            cluster_gender = "Adult"

        return f"{brand.lower()} {model_key} [{art_type}] [{cluster_gender}]"

    @classmethod
    def partition_by_price_sanity(cls, cluster_offers: List[Offer]) -> List[List[Offer]]:
        """
        Detects extreme pricing anomalies (e.g. an €18 case mixed with €230 GPS)
        and isolates outliers into their own separate comparison cards.
        """
        if len(cluster_offers) <= 1:
            return [cluster_offers]

        sorted_offers = sorted(cluster_offers, key=lambda o: o.price)
        prices = [o.price for o in sorted_offers if o.price and o.price > 0]
        if not prices:
            return [sorted_offers]

        median_price = prices[len(prices) // 2]
        if median_price <= 0:
            return [sorted_offers]

        main_group: List[Offer] = []
        outliers: List[Offer] = []

        for o in sorted_offers:
            if not o.price:
                continue
            ratio = o.price / median_price
            # If an offer is less than 38% or more than 260% of the median, treat as outlier
            if ratio < 0.38 or ratio > 2.60:
                outliers.append(o)
            else:
                main_group.append(o)

        partitions: List[List[Offer]] = []
        if main_group:
            partitions.append(main_group)
        for out in outliers:
            partitions.append([out])

        return partitions

    @classmethod
    def group_offers(cls, offers: List[Offer]) -> List[MatchedProductGroup]:
        """Group offers from different stores into consolidated, verified matched product cards."""
        clusters: Dict[str, List[Offer]] = defaultdict(list)

        for offer in offers:
            key = cls.extract_cluster_key(offer)
            clusters[key].append(offer)

        groups: List[MatchedProductGroup] = []

        for key, raw_cluster_offers in clusters.items():
            # Apply price sanity guardrail to partition any accidental outliers
            partitions = cls.partition_by_price_sanity(raw_cluster_offers)

            for cluster_offers in partitions:
                if not cluster_offers:
                    continue

                sample_offer = max(cluster_offers, key=lambda o: len(o.title))
                brand = cls.extract_brand(sample_offer.title, sample_offer.brand)
                gender = cls.extract_gender(sample_offer.title, sample_offer.url)
                art_type = cls.detect_article_type(sample_offer.title)

                # Canonical Name Generation
                cleaned_base, _ = cls.clean_title(sample_offer.title, brand)
                canonical = f"{brand} {cleaned_base.title()}" if brand and brand.lower() not in cleaned_base.lower() else cleaned_base.title()
                if brand:
                    canonical = re.sub(r"^(" + re.escape(brand) + r"\s+)+", f"{brand} ", canonical, flags=re.IGNORECASE).strip()

                if art_type == "case" and "custodia" not in canonical.lower() and "case" not in canonical.lower():
                    canonical += " (Custodia)"
                elif art_type == "strap" and "cinturino" not in canonical.lower():
                    canonical += " (Cinturino)"
                elif art_type == "pack" and "pack" not in canonical.lower():
                    canonical += " (Bundle/Pack)"
                elif art_type == "jacket" and not any(w in canonical.lower() for w in ("giacca", "jacket", "gilet")):
                    canonical += " (Giacca)"
                elif art_type == "pants" and not any(w in canonical.lower() for w in ("pantaloni", "pantaloncini", "shorts", "tights", "leggings")):
                    canonical += " (Pantaloni/Shorts)"
                elif art_type == "top" and not any(w in canonical.lower() for w in ("maglia", "maglietta", "t-shirt", "canotta", "top")):
                    canonical += " (Maglia)"
                elif art_type == "racket" and not any(w in canonical.lower() for w in ("racchetta", "pala", "racket")):
                    canonical += " (Racchetta Padel)"
                elif art_type == "trainer" and not any(w in canonical.lower() for w in ("rullo", "trainer")):
                    canonical += " (Rullo Smart)"

                if gender in ("Donna", "Junior") and gender.lower() not in canonical.lower():
                    canonical += f" ({gender})"

                sorted_offers = sorted(cluster_offers, key=lambda o: o.price)
                image = next((o.image_url for o in cluster_offers if o.image_url), None)

                # Collect and deduplicate all distinct images across matching offers
                gallery = []
                if image:
                    gallery.append(image)
                for o in sorted_offers:
                    if o.image_url and o.image_url not in gallery:
                        gallery.append(o.image_url)
                    for g_img in o.gallery_images:
                        if g_img and g_img not in gallery:
                            gallery.append(g_img)

                groups.append(
                    MatchedProductGroup(
                        canonical_name=canonical,
                        brand=brand,
                        image_url=image,
                        gallery_images=gallery,
                        offers=sorted_offers
                    )
                )

        # Prioritize true multi-store matches, then top savings
        groups.sort(
            key=lambda g: (
                len({o.store_id for o in g.offers}) > 1,
                g.cross_store_savings or 0,
                len(g.offers)
            ),
            reverse=True
        )
        return groups
