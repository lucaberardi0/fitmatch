import json
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime, timezone
from fitmatch.db import Database
from fitmatch.scheduler import SyncScheduler
from fitmatch.scrapers.registry import ScraperRegistry

logger = logging.getLogger("fitmatch.admin")


def get_admin_overview(db: Database, scheduler: SyncScheduler) -> Dict[str, Any]:
    """Compile a complete real-time telemetry snapshot for the Admin Control Center."""
    # 1. Scheduler telemetry
    sched_status = scheduler.get_status()

    # 2. Database catalog statistics
    catalog_stats = db.get_stats()

    # 3. Store health & size coverage metrics
    store_health = []
    try:
        store_health = db.get_store_health_metrics()
    except Exception as e:
        logger.warning(f"[Admin] Error fetching store health metrics: {e}")

    # 4. Recent sessions
    recent_sessions = []
    try:
        recent_sessions = db.get_sync_sessions(limit=30)
    except Exception as e:
        logger.warning(f"[Admin] Error fetching recent sessions: {e}")

    # 5. Failed sessions (errors only)
    failed_sessions = []
    try:
        failed_sessions = db.get_sync_sessions(limit=10, status="failed")
    except Exception as e:
        logger.warning(f"[Admin] Error fetching failed sessions: {e}")

    # 6. Active scraper registry
    active_stores = []
    try:
        registry = ScraperRegistry()
        active_stores = [
            {"id": s.store_id, "name": s.store_name, "base_url": s.base_url}
            for s in registry.scrapers
        ]
    except Exception as e:
        logger.warning(f"[Admin] Error loading store registry: {e}")

    # Compute overall size coverage
    total_offers = catalog_stats.get("total_offers", 0)
    total_with_sizes = sum(s.get("with_sizes", 0) for s in store_health)
    size_coverage_pct = round((total_with_sizes / total_offers * 100), 1) if total_offers > 0 else 0.0

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "scheduler": sched_status,
        "catalog": catalog_stats,
        "size_metrics": {
            "total_with_sizes": total_with_sizes,
            "total_offers": total_offers,
            "overall_size_coverage_pct": size_coverage_pct
        },
        "store_health": store_health,
        "recent_sessions": recent_sessions,
        "failed_sessions": failed_sessions,
        "active_stores": active_stores,
        "version": "0.3.0"
    }


def render_admin_html() -> str:
    """Return the complete standalone HTML / JS dashboard for the FitMatch Admin Center."""
    return """<!DOCTYPE html>
<html lang="it" class="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>FitMatch Control Center & Admin Panel</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            brand: {
              50: '#eef2ff',
              100: '#e0e7ff',
              500: '#6366f1',
              600: '#4f46e5',
              700: '#4338ca',
            },
            dark: {
              900: '#090d16',
              850: '#0f172a',
              800: '#1e293b',
              700: '#334155',
            }
          }
        }
      }
    }
  </script>
  <style>
    @keyframes pulse-fast {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.5; transform: scale(1.1); }
    }
    .live-pulse {
      animation: pulse-fast 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
    }
    /* Custom scrollbars */
    ::-webkit-scrollbar { width: 6px; height: 6px; }
    ::-webkit-scrollbar-track { background: #0f172a; }
    ::-webkit-scrollbar-thumb { background: #334155; border-radius: 4px; }
    ::-webkit-scrollbar-thumb:hover { background: #475569; }
  </style>
</head>
<body class="bg-dark-900 text-slate-100 min-h-screen font-sans antialiased selection:bg-brand-500 selection:text-white">

  <!-- Header -->
  <header class="sticky top-0 z-40 bg-dark-850/80 backdrop-blur-md border-b border-dark-700/60 px-6 py-4">
    <div class="max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
      
      <!-- Logo & Title -->
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-brand-600 to-indigo-400 flex items-center justify-center shadow-lg shadow-brand-500/20 text-xl font-black">
          ⚡
        </div>
        <div>
          <div class="flex items-center gap-2">
            <h1 class="text-xl font-bold tracking-tight text-white">FitMatch <span class="text-brand-500">Admin</span></h1>
            <span class="text-xs uppercase tracking-wider font-semibold px-2 py-0.5 rounded-full bg-brand-500/10 text-brand-400 border border-brand-500/20">Control Center</span>
          </div>
          <p class="text-xs text-slate-400">Monitoraggio real-time scrapers, sessioni di sincronizzazione e catalogo</p>
        </div>
      </div>

      <!-- Live Scheduler Status Badge -->
      <div class="flex items-center gap-3">
        <div id="scheduler-badge" class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-800/80 border border-slate-700 text-xs font-medium">
          <span class="w-2.5 h-2.5 rounded-full bg-slate-500"></span>
          <span id="scheduler-badge-text">Caricamento stato...</span>
        </div>

        <!-- Auto refresh toggle -->
        <div class="flex items-center gap-2 text-xs text-slate-400 bg-dark-800/80 px-3 py-1.5 rounded-lg border border-dark-700">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" id="auto-refresh-toggle" checked class="rounded border-slate-700 text-brand-500 focus:ring-0 focus:ring-offset-0 bg-dark-900">
            <span>Auto-refresh (10s)</span>
          </label>
          <button onclick="fetchOverview()" title="Ricarica ora" class="hover:text-white transition-colors">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>
          </button>
        </div>
      </div>

    </div>
  </header>

  <!-- Main Content Container -->
  <main class="max-w-7xl mx-auto px-6 py-8 space-y-8">

    <!-- Action Toolbar (Trigger Immediate Tasks) -->
    <div class="bg-gradient-to-r from-dark-850 to-slate-900/90 border border-dark-700/80 rounded-2xl p-5 shadow-xl flex flex-wrap items-center justify-between gap-4">
      <div>
        <h2 class="text-sm font-semibold text-slate-200">Azioni Rapide di Controllo</h2>
        <p class="text-xs text-slate-400">Lancia istantaneamente sincronizzazioni asincrone con tracciamento sessione</p>
      </div>

      <div class="flex flex-wrap items-center gap-2.5">
        <button onclick="triggerDiscovery()" id="btn-discovery" class="flex items-center gap-2 px-4 py-2 text-xs font-semibold rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white shadow-md shadow-indigo-600/20 transition-all active:scale-95">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
          <span>Scoperta Catalogo (200/store)</span>
        </button>

        <button onclick="triggerRefresh()" id="btn-refresh" class="flex items-center gap-2 px-4 py-2 text-xs font-semibold rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white shadow-md shadow-emerald-600/20 transition-all active:scale-95">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
          <span>Verifica Prezzi & Notifiche</span>
        </button>

        <button onclick="triggerEnrichment()" id="btn-enrich" class="flex items-center gap-2 px-4 py-2 text-xs font-semibold rounded-xl bg-amber-600 hover:bg-amber-500 text-white shadow-md shadow-amber-600/20 transition-all active:scale-95">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"/></svg>
          <span>Arricchisci Taglie Mancanti</span>
        </button>

        <button onclick="triggerRecluster()" id="btn-recluster" class="flex items-center gap-2 px-3.5 py-2 text-xs font-medium rounded-xl bg-dark-800 hover:bg-dark-700 text-slate-300 border border-dark-700 transition-all active:scale-95">
          <span>🧩 Re-cluster Entità</span>
        </button>

        <!-- Dropdown single store crawl -->
        <div class="relative inline-block text-left">
          <select id="single-store-select" onchange="crawlSingleStore(this.value)" class="text-xs bg-dark-800 border border-dark-700 text-slate-300 rounded-xl px-3 py-2 pr-8 focus:ring-1 focus:ring-brand-500 focus:outline-none cursor-pointer">
            <option value="" disabled selected>Scansiona Store Singolo...</option>
            <option value="cisalfa">Cisalfa Sport</option>
            <option value="maxisport">Maxi Sport</option>
            <option value="misterrunning">Mister Running</option>
            <option value="decathlon">Decathlon</option>
            <option value="nike">Nike Official</option>
            <option value="tradeinn">Tradeinn</option>
            <option value="df_sportspecialist">DF Sport Specialist</option>
            <option value="alltricks">Alltricks</option>
            <option value="deporvillage">Deporvillage</option>
            <option value="top4running">Top4Running</option>
            <option value="runningwarehouse">Running Warehouse</option>
            <option value="nencini">Nencini Sport</option>
            <option value="adidas">Adidas</option>
          </select>
        </div>

      </div>
    </div>

    <!-- Alert / Toast Banner -->
    <div id="toast-banner" class="hidden transition-all duration-300">
      <div id="toast-content" class="p-4 rounded-xl flex items-center justify-between text-xs font-medium border shadow-lg">
        <span id="toast-message"></span>
        <button onclick="hideToast()" class="opacity-70 hover:opacity-100 ml-4 font-bold">✕</button>
      </div>
    </div>

    <!-- Overview Counters Grid -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
      
      <!-- Counter 1: Prodotti Catalogo -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg relative overflow-hidden">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Prodotti Unici</span>
          <span class="w-8 h-8 rounded-lg bg-indigo-500/10 text-indigo-400 flex items-center justify-center font-bold text-sm">👟</span>
        </div>
        <div class="text-3xl font-extrabold text-white tracking-tight" id="cnt-products">—</div>
        <div class="text-xs text-slate-400 mt-2 flex items-center gap-1.5">
          <span class="text-emerald-400 font-semibold" id="cnt-multistore">—</span> prodotti con confronto multinegozio
        </div>
      </div>

      <!-- Counter 2: Offerte Totali -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg relative overflow-hidden">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Offerte Negozi</span>
          <span class="w-8 h-8 rounded-lg bg-emerald-500/10 text-emerald-400 flex items-center justify-center font-bold text-sm">🏷️</span>
        </div>
        <div class="text-3xl font-extrabold text-white tracking-tight" id="cnt-offers">—</div>
        <div class="text-xs text-slate-400 mt-2 flex items-center gap-1.5">
          <span class="text-slate-300 font-medium" id="cnt-stores-active">14 negozi partner</span> censiti
        </div>
      </div>

      <!-- Counter 3: Copertura Taglie Normalizzate -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg relative overflow-hidden">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Copertura Taglie</span>
          <span class="w-8 h-8 rounded-lg bg-amber-500/10 text-amber-400 flex items-center justify-center font-bold text-sm">📏</span>
        </div>
        <div class="text-3xl font-extrabold text-white tracking-tight" id="cnt-size-coverage">—</div>
        <div class="text-xs text-slate-400 mt-2 flex items-center gap-1.5">
          <span class="text-amber-400 font-medium" id="cnt-with-sizes">—</span> offerte con taglie attive
        </div>
      </div>

      <!-- Counter 4: Cicli & Errori -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg relative overflow-hidden">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Salute Sync & Cicli</span>
          <span class="w-8 h-8 rounded-lg bg-purple-500/10 text-purple-400 flex items-center justify-center font-bold text-sm">⚙️</span>
        </div>
        <div class="text-3xl font-extrabold text-white tracking-tight flex items-center gap-2">
          <span id="cnt-cycles">0</span>
          <span class="text-xs font-normal text-slate-400">cicli</span>
        </div>
        <div class="text-xs text-slate-400 mt-2 flex items-center gap-2" id="cnt-errors-wrapper">
          <span id="cnt-errors-badge" class="px-2 py-0.5 rounded font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">0 errori</span>
          <span class="text-slate-400">registrati</span>
        </div>
      </div>

    </div>

    <!-- Scheduler Live Telemetry Cards -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
      
      <!-- Discovery Task Card -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg flex flex-col justify-between">
        <div>
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-2">
              <span class="w-3 h-3 rounded-full bg-indigo-500"></span>
              <h3 class="font-bold text-slate-100 text-sm">Scoperta Catalogo (Discovery 24h)</h3>
            </div>
            <span class="text-xs font-semibold px-2.5 py-1 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20" id="discovery-interval">Ogni 24h</span>
          </div>
          <p class="text-xs text-slate-400 mb-4">Esegue il crawling massivo delle categorie running, outdoor e accessori su tutti i 14 store partner, con unificazione entità e arricchimento taglie.</p>
        </div>

        <div class="bg-dark-900/60 rounded-xl p-3 border border-dark-700/50 space-y-2 text-xs">
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Ultima esecuzione:</span>
            <span class="font-mono font-medium" id="discovery-last-run">Mai</span>
          </div>
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Prossima esecuzione:</span>
            <span class="font-mono font-medium text-indigo-400" id="discovery-next-run">Non programmata</span>
          </div>
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Ultimo risultato:</span>
            <span class="font-mono" id="discovery-last-stats">—</span>
          </div>
        </div>
      </div>

      <!-- Price Refresh Card -->
      <div class="bg-dark-850 border border-dark-700/70 rounded-2xl p-5 shadow-lg flex flex-col justify-between">
        <div>
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-2">
              <span class="w-3 h-3 rounded-full bg-emerald-500"></span>
              <h3 class="font-bold text-slate-100 text-sm">Monitor Prezzi & Notifiche (Refresh 2h)</h3>
            </div>
            <span class="text-xs font-semibold px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20" id="refresh-interval">Ogni 2h</span>
          </div>
          <p class="text-xs text-slate-400 mb-4">Controlla a rotazione le offerte dei prodotti più visti o in wishlist, aggiorna la cronologia prezzi e invia notifiche push APNs via PriceDropWatcher.</p>
        </div>

        <div class="bg-dark-900/60 rounded-xl p-3 border border-dark-700/50 space-y-2 text-xs">
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Ultima esecuzione:</span>
            <span class="font-mono font-medium" id="refresh-last-run">Mai</span>
          </div>
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Prossima esecuzione:</span>
            <span class="font-mono font-medium text-emerald-400" id="refresh-next-run">Non programmata</span>
          </div>
          <div class="flex items-center justify-between text-slate-300">
            <span class="text-slate-500">Ultimo risultato:</span>
            <span class="font-mono" id="refresh-last-stats">—</span>
          </div>
        </div>
      </div>

    </div>

    <!-- Error Banner (Visible if there are recent failed sessions) -->
    <div id="error-section" class="hidden bg-rose-950/30 border border-rose-800/60 rounded-2xl p-5 shadow-lg">
      <div class="flex items-center gap-3 mb-3 text-rose-400 font-bold text-sm">
        <svg class="w-5 h-5 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>
        <span>Errori Recenti Rilevati (<span id="error-count">0</span> sessioni fallite)</span>
      </div>
      <div id="error-list" class="space-y-2 text-xs"></div>
    </div>

    <!-- Stores Health Table -->
    <div class="bg-dark-850 border border-dark-700/70 rounded-2xl shadow-lg overflow-hidden">
      <div class="p-5 border-b border-dark-700/70 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
        <div>
          <h2 class="font-bold text-base text-white">Stato e Copertura Negozi Partner</h2>
          <p class="text-xs text-slate-400">Offerte censite, percentuale di taglie disponibili e data ultimo controllo per store</p>
        </div>
        <span class="text-xs font-mono text-slate-400" id="store-count-label">14 negozi partner</span>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead class="bg-dark-900/80 text-slate-400 uppercase tracking-wider font-semibold border-b border-dark-700/70">
            <tr>
              <th class="px-5 py-3">Store</th>
              <th class="px-5 py-3">Offerte Attive</th>
              <th class="px-5 py-3">Con Taglie</th>
              <th class="px-5 py-3">Copertura Taglie</th>
              <th class="px-5 py-3">Prezzo Medio</th>
              <th class="px-5 py-3">Sconto Medio</th>
              <th class="px-5 py-3">Ultimo Check</th>
              <th class="px-5 py-3 text-right">Azione</th>
            </tr>
          </thead>
          <tbody id="store-health-tbody" class="divide-y divide-dark-700/40 text-slate-300">
            <tr><td colspan="8" class="text-center py-6 text-slate-500">Caricamento dati negozi...</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Sync Sessions History (The Main Audit Trail) -->
    <div class="bg-dark-850 border border-dark-700/70 rounded-2xl shadow-lg overflow-hidden">
      <div class="p-5 border-b border-dark-700/70 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h2 class="font-bold text-base text-white">Registro Storico Sessioni di Sincronizzazione</h2>
          <p class="text-xs text-slate-400">Cronologia persistente di tutte le sessioni di discovery, aggiornamento prezzi e crawling</p>
        </div>

        <!-- Filter tabs -->
        <div class="flex items-center gap-1.5 bg-dark-900 p-1 rounded-xl border border-dark-700/80 text-xs font-medium">
          <button onclick="setSessionFilter('all')" id="tab-all" class="px-3 py-1.5 rounded-lg bg-brand-600 text-white transition-colors">Tutte</button>
          <button onclick="setSessionFilter('discovery')" id="tab-discovery" class="px-3 py-1.5 rounded-lg text-slate-400 hover:text-white transition-colors">Discovery</button>
          <button onclick="setSessionFilter('price_refresh')" id="tab-price_refresh" class="px-3 py-1.5 rounded-lg text-slate-400 hover:text-white transition-colors">Refresh</button>
          <button onclick="setSessionFilter('size_enrichment')" id="tab-size_enrichment" class="px-3 py-1.5 rounded-lg text-slate-400 hover:text-white transition-colors">Taglie</button>
          <button onclick="setSessionFilter('failed')" id="tab-failed" class="px-3 py-1.5 rounded-lg text-slate-400 hover:text-rose-400 transition-colors">Errori</button>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead class="bg-dark-900/80 text-slate-400 uppercase tracking-wider font-semibold border-b border-dark-700/70">
            <tr>
              <th class="px-5 py-3">ID Sessione</th>
              <th class="px-5 py-3">Tipo & Trigger</th>
              <th class="px-5 py-3">Stato</th>
              <th class="px-5 py-3">Iniziata</th>
              <th class="px-5 py-3">Durata</th>
              <th class="px-5 py-3">Articoli</th>
              <th class="px-5 py-3">Sconti / Risparmi</th>
              <th class="px-5 py-3 text-right">Dettagli</th>
            </tr>
          </thead>
          <tbody id="sessions-tbody" class="divide-y divide-dark-700/40 text-slate-300">
            <tr><td colspan="8" class="text-center py-6 text-slate-500">Caricamento sessioni...</td></tr>
          </tbody>
        </table>
      </div>
    </div>

  </main>

  <!-- Modal: Session Detail Deep-Dive -->
  <div id="session-modal" class="hidden fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="bg-dark-850 border border-dark-700 rounded-2xl max-w-2xl w-full max-h-[85vh] overflow-hidden flex flex-col shadow-2xl">
      <div class="p-5 border-b border-dark-700 flex items-center justify-between">
        <div>
          <h3 class="font-bold text-white text-base" id="modal-title">Dettaglio Sessione</h3>
          <p class="text-xs text-slate-400 font-mono" id="modal-session-id"></p>
        </div>
        <button onclick="closeModal()" class="w-8 h-8 rounded-lg bg-dark-800 text-slate-400 hover:text-white flex items-center justify-center">✕</button>
      </div>
      
      <div class="p-5 overflow-y-auto space-y-4 text-xs" id="modal-body">
        <!-- Injected via JS -->
      </div>
      
      <div class="p-4 border-t border-dark-700 bg-dark-900/60 flex justify-end">
        <button onclick="closeModal()" class="px-4 py-2 bg-dark-800 hover:bg-dark-700 rounded-xl text-slate-300 font-medium text-xs">Chiudi</button>
      </div>
    </div>
  </div>

  <!-- JavaScript Application Logic -->
  <script>
    let globalData = null;
    let currentFilter = 'all';
    let autoRefreshTimer = null;

    async function fetchOverview() {
      try {
        const res = await fetch('/api/admin/overview');
        if (!res.ok) throw new Error('HTTP ' + res.status);
        globalData = await res.json();
        renderDashboard(globalData);
      } catch (err) {
        console.error('Error fetching overview:', err);
        showToast('Errore di connessione al backend: ' + err.message, 'error');
      }
    }

    function renderDashboard(data) {
      if (!data) return;

      // 1. Scheduler status badge
      const sched = data.scheduler || {};
      const isRunning = sched.is_running;
      const currentTask = (sched.current_task || 'idle').toLowerCase();
      const badge = document.getElementById('scheduler-badge');
      const badgeText = document.getElementById('scheduler-badge-text');

      if (currentTask !== 'idle') {
        badge.className = 'flex items-center gap-2 px-3 py-1.5 rounded-full bg-indigo-500/10 border border-indigo-500/30 text-xs font-medium text-indigo-400';
        badge.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-indigo-500 live-pulse"></span><span>' + currentTask.toUpperCase() + ' in corso...</span>';
      } else if (isRunning) {
        badge.className = 'flex items-center gap-2 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-xs font-medium text-emerald-400';
        badge.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-emerald-500"></span><span>Scheduler Attivo (2h / 24h)</span>';
      } else {
        badge.className = 'flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-800 border border-slate-700 text-xs font-medium text-slate-400';
        badge.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-slate-500"></span><span>Scheduler Fermo</span>';
      }

      // 2. Counters
      const cat = data.catalog || {};
      const sizeMet = data.size_metrics || {};
      document.getElementById('cnt-products').textContent = (cat.total_products || 0).toLocaleString('it-IT');
      document.getElementById('cnt-multistore').textContent = (cat.multi_store_products || 0).toLocaleString('it-IT');
      document.getElementById('cnt-offers').textContent = (cat.total_offers || 0).toLocaleString('it-IT');
      document.getElementById('cnt-size-coverage').textContent = (sizeMet.overall_size_coverage_pct || 0) + '%';
      document.getElementById('cnt-with-sizes').textContent = (sizeMet.total_with_sizes || 0).toLocaleString('it-IT');
      document.getElementById('cnt-cycles').textContent = sched.total_cycles_completed || 0;

      // 3. Errors badge
      const failed = data.failed_sessions || [];
      const errorBadge = document.getElementById('cnt-errors-badge');
      if (failed.length > 0) {
        errorBadge.className = 'px-2 py-0.5 rounded font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20';
        errorBadge.textContent = failed.length + ' errori';
        
        // Show error section
        document.getElementById('error-section').classList.remove('hidden');
        document.getElementById('error-count').textContent = failed.length;
        renderErrorList(failed);
      } else {
        errorBadge.className = 'px-2 py-0.5 rounded font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20';
        errorBadge.textContent = '0 errori';
        document.getElementById('error-section').classList.add('hidden');
      }

      // 4. Discovery Card details
      const disc = sched.discovery || {};
      document.getElementById('discovery-interval').textContent = 'Ogni ' + (disc.interval_hours || 24) + 'h';
      document.getElementById('discovery-last-run').textContent = disc.last_run || 'Mai';
      document.getElementById('discovery-next-run').textContent = disc.next_run || 'Non programmata';
      if (disc.last_stats && disc.last_stats.total_crawled !== undefined) {
        document.getElementById('discovery-last-stats').textContent = disc.last_stats.total_crawled + ' prodotti in ' + (disc.last_stats.duration_seconds || 0) + 's';
      } else {
        document.getElementById('discovery-last-stats').textContent = 'Nessuna esecuzione';
      }

      // 5. Refresh Card details
      const ref = sched.refresh || {};
      document.getElementById('refresh-interval').textContent = 'Ogni ' + (ref.interval_hours || 2) + 'h';
      document.getElementById('refresh-last-run').textContent = ref.last_run || 'Mai';
      document.getElementById('refresh-next-run').textContent = ref.next_run || 'Non programmata';
      if (ref.last_stats && ref.last_stats.offers_checked !== undefined) {
        document.getElementById('refresh-last-stats').textContent = ref.last_stats.offers_checked + ' verificati, ' + (ref.last_stats.price_drops || 0) + ' sconti';
      } else {
        document.getElementById('refresh-last-stats').textContent = 'Nessuna esecuzione';
      }

      // 6. Store health table
      renderStoreHealth(data.store_health || []);

      // 7. Sessions table
      renderSessions(data.recent_sessions || []);
    }

    function renderStoreHealth(stores) {
      const tbody = document.getElementById('store-health-tbody');
      if (!stores || stores.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" class="text-center py-6 text-slate-500">Nessun dato store disponibile.</td></tr>';
        return;
      }

      tbody.innerHTML = stores.map(s => {
        const pct = parseFloat(s.size_coverage_pct || 0);
        let colorClass = 'bg-rose-500/10 text-rose-400 border-rose-500/20';
        if (pct >= 80) colorClass = 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20';
        else if (pct >= 30) colorClass = 'bg-amber-500/10 text-amber-400 border-amber-500/20';

        const lastCheck = s.last_checked_at ? s.last_checked_at.slice(0, 16).replace('T', ' ') : 'N/A';
        const avgPrice = s.avg_price ? '€' + parseFloat(s.avg_price).toFixed(2) : '—';
        const avgDisc = s.avg_discount ? '-' + parseFloat(s.avg_discount).toFixed(0) + '%' : '—';

        return `
          <tr class="hover:bg-dark-800/40 transition-colors">
            <td class="px-5 py-3 font-semibold text-white capitalize flex items-center gap-2">
              <span>${s.store_id}</span>
            </td>
            <td class="px-5 py-3 font-mono font-medium">${(s.total_offers || 0).toLocaleString('it-IT')}</td>
            <td class="px-5 py-3 font-mono text-slate-400">${(s.with_sizes || 0).toLocaleString('it-IT')}</td>
            <td class="px-5 py-3">
              <div class="flex items-center gap-2">
                <span class="px-2 py-0.5 rounded text-xs font-semibold border ${colorClass}">${pct}%</span>
                <div class="w-16 h-1.5 bg-dark-900 rounded-full overflow-hidden hidden sm:block">
                  <div class="h-full ${pct >= 80 ? 'bg-emerald-500' : (pct >= 30 ? 'bg-amber-500' : 'bg-rose-500')}" style="width: ${Math.min(pct, 100)}%"></div>
                </div>
              </div>
            </td>
            <td class="px-5 py-3 font-mono">${avgPrice}</td>
            <td class="px-5 py-3 font-mono text-amber-400">${avgDisc}</td>
            <td class="px-5 py-3 font-mono text-slate-400 text-xs">${lastCheck}</td>
            <td class="px-5 py-3 text-right">
              <button onclick="crawlSingleStore('${s.store_id}')" class="px-2.5 py-1 text-xs bg-dark-800 hover:bg-dark-700 text-slate-300 rounded-lg border border-dark-700 transition-colors">
                Scansiona
              </button>
            </td>
          </tr>
        `;
      }).join('');
    }

    function renderSessions(sessions) {
      const tbody = document.getElementById('sessions-tbody');
      let filtered = sessions;

      if (currentFilter === 'discovery') {
        filtered = sessions.filter(s => s.session_type === 'discovery');
      } else if (currentFilter === 'price_refresh') {
        filtered = sessions.filter(s => s.session_type === 'price_refresh');
      } else if (currentFilter === 'size_enrichment') {
        filtered = sessions.filter(s => s.session_type === 'size_enrichment');
      } else if (currentFilter === 'failed') {
        filtered = sessions.filter(s => s.status === 'failed');
      }

      if (!filtered || filtered.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" class="text-center py-6 text-slate-500">Nessuna sessione trovata per questo filtro.</td></tr>';
        return;
      }

      tbody.innerHTML = filtered.map(s => {
        const sid = String(s.id || '');
        const shortId = sid.slice(0, 8);
        const status = s.status || 'unknown';
        
        let statusBadge = '<span class="px-2 py-0.5 rounded text-xs font-semibold bg-slate-500/10 text-slate-400 border border-slate-500/20">' + status + '</span>';
        if (status === 'completed') {
          statusBadge = '<span class="px-2 py-0.5 rounded text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">Completata</span>';
        } else if (status === 'running') {
          statusBadge = '<span class="px-2 py-0.5 rounded text-xs font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 live-pulse">In corso</span>';
        } else if (status === 'failed') {
          statusBadge = '<span class="px-2 py-0.5 rounded text-xs font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20">Fallita</span>';
        }

        const started = s.started_at ? s.started_at.slice(0, 16).replace('T', ' ') : '—';
        const dur = s.duration_seconds !== null && s.duration_seconds !== undefined ? parseFloat(s.duration_seconds).toFixed(1) + 's' : '—';
        const items = (s.total_items_processed || 0).toLocaleString('it-IT');
        const drops = s.total_price_drops ? `<span class="text-emerald-400 font-semibold">${s.total_price_drops} sconti</span>` : '<span class="text-slate-500">—</span>';

        return `
          <tr class="hover:bg-dark-800/40 transition-colors">
            <td class="px-5 py-3 font-mono font-medium text-slate-300">
              <button onclick="openSessionModal('${sid}')" class="text-brand-400 hover:underline" title="Apri dettagli">${shortId}...</button>
            </td>
            <td class="px-5 py-3">
              <div class="font-medium text-white">${s.session_type || 'crawl'}</div>
              <div class="text-[11px] text-slate-500">${s.trigger_source || 'scheduler'}</div>
            </td>
            <td class="px-5 py-3">${statusBadge}</td>
            <td class="px-5 py-3 font-mono text-slate-400">${started}</td>
            <td class="px-5 py-3 font-mono text-slate-300">${dur}</td>
            <td class="px-5 py-3 font-mono text-slate-200">${items}</td>
            <td class="px-5 py-3 font-mono">${drops}</td>
            <td class="px-5 py-3 text-right">
              <button onclick="openSessionModal('${sid}')" class="px-2.5 py-1 text-xs bg-dark-800 hover:bg-dark-700 text-slate-300 rounded-lg border border-dark-700 transition-colors">
                Dettagli
              </button>
            </td>
          </tr>
        `;
      }).join('');
    }

    function renderErrorList(failed) {
      const el = document.getElementById('error-list');
      el.innerHTML = failed.map(f => `
        <div class="bg-rose-950/40 border border-rose-800/40 rounded-xl p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div>
            <div class="font-semibold text-rose-300">Sessione ${String(f.id).slice(0, 8)} (${f.session_type}) fallita il ${String(f.started_at || '').slice(0, 16).replace('T', ' ')}</div>
            <div class="text-rose-400/90 font-mono text-xs mt-1">${f.error_message || 'Nessun dettaglio errore specificato.'}</div>
          </div>
          <button onclick="openSessionModal('${f.id}')" class="px-3 py-1 bg-rose-900/60 hover:bg-rose-900 text-rose-200 rounded-lg text-xs self-start sm:self-auto font-medium">
            Esamina
          </button>
        </div>
      `).join('');
    }

    function setSessionFilter(filter) {
      currentFilter = filter;
      ['all', 'discovery', 'price_refresh', 'size_enrichment', 'failed'].forEach(f => {
        const btn = document.getElementById('tab-' + f);
        if (!btn) return;
        if (f === filter) {
          btn.className = 'px-3 py-1.5 rounded-lg bg-brand-600 text-white transition-colors';
        } else {
          btn.className = 'px-3 py-1.5 rounded-lg text-slate-400 hover:text-white transition-colors';
        }
      });
      if (globalData && globalData.recent_sessions) {
        renderSessions(globalData.recent_sessions);
      }
    }

    async function openSessionModal(sessionId) {
      const modal = document.getElementById('session-modal');
      const title = document.getElementById('modal-title');
      const idLabel = document.getElementById('modal-session-id');
      const body = document.getElementById('modal-body');

      title.textContent = 'Caricamento dettagli sessione...';
      idLabel.textContent = sessionId;
      body.innerHTML = '<div class="text-center py-8 text-slate-400">Recupero dati da Supabase...</div>';
      modal.classList.remove('hidden');

      try {
        const res = await fetch('/api/scheduler/sessions/' + sessionId);
        if (!res.ok) throw new Error('Sessione non trovata');
        const s = await res.json();

        title.textContent = 'Sessione ' + (s.session_type || 'Sync').toUpperCase();
        
        let storeStatsHtml = '';
        const stats = s.store_stats || {};
        const entries = Object.entries(stats);
        if (entries.length > 0) {
          storeStatsHtml = `
            <div class="mt-3">
              <h4 class="font-semibold text-slate-200 mb-2">Articoli per Negozio:</h4>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                ${entries.map(([store, count]) => `
                  <div class="bg-dark-900/80 p-2.5 rounded-xl border border-dark-700">
                    <div class="text-slate-400 capitalize text-xs">${store}</div>
                    <div class="text-base font-bold text-white font-mono">${typeof count === 'number' ? count.toLocaleString('it-IT') : JSON.stringify(count)}</div>
                  </div>
                `).join('')}
              </div>
            </div>
          `;
        }

        let logsHtml = '';
        const logs = s.crawl_logs || [];
        if (logs.length > 0) {
          logsHtml = `
            <div class="mt-4">
              <h4 class="font-semibold text-slate-200 mb-2">Log Crawl Negozio (${logs.length}):</h4>
              <div class="max-h-40 overflow-y-auto space-y-1 font-mono text-xs bg-dark-900/80 p-3 rounded-xl border border-dark-700">
                ${logs.map(l => `
                  <div class="flex justify-between py-1 border-b border-dark-800 last:border-0">
                    <span class="text-slate-300 capitalize">${l.store_id}</span>
                    <span class="text-slate-400">${l.items_found} items in ${parseFloat(l.duration_seconds || 0).toFixed(1)}s</span>
                  </div>
                `).join('')}
              </div>
            </div>
          `;
        }

        let errorHtml = '';
        if (s.error_message) {
          errorHtml = `
            <div class="bg-rose-950/60 border border-rose-800 rounded-xl p-3 text-rose-300 font-mono text-xs">
              <strong class="text-rose-200">Errore:</strong> ${s.error_message}
            </div>
          `;
        }

        body.innerHTML = `
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 bg-dark-900/60 p-3 rounded-xl border border-dark-700">
            <div>
              <span class="text-slate-500 block text-[11px]">Stato</span>
              <span class="font-bold text-white">${s.status}</span>
            </div>
            <div>
              <span class="text-slate-500 block text-[11px]">Durata</span>
              <span class="font-mono text-white">${parseFloat(s.duration_seconds || 0).toFixed(1)}s</span>
            </div>
            <div>
              <span class="text-slate-500 block text-[11px]">Articoli Processati</span>
              <span class="font-mono text-white">${(s.total_items_processed || 0).toLocaleString('it-IT')}</span>
            </div>
            <div>
              <span class="text-slate-500 block text-[11px]">Sconti / Drop</span>
              <span class="font-mono text-emerald-400 font-bold">${s.total_price_drops || 0}</span>
            </div>
          </div>
          ${errorHtml}
          ${storeStatsHtml}
          ${logsHtml}
        `;

      } catch (err) {
        body.innerHTML = '<div class="text-rose-400 py-4">Errore nel caricamento: ' + err.message + '</div>';
      }
    }

    function closeModal() {
      document.getElementById('session-modal').classList.add('hidden');
    }

    // --- Action Triggers ---

    async function triggerDiscovery() {
      const btn = document.getElementById('btn-discovery');
      btn.disabled = true;
      btn.classList.add('opacity-50');
      showToast('Avvio scansione discovery in background (target: 200 per negozio)...', 'info');
      try {
        const res = await fetch('/api/scheduler/run-discovery?limit_per_store=200', { method: 'POST' });
        const data = await res.json();
        showToast(data.message || 'Discovery avviata con successo!', 'success');
        setTimeout(fetchOverview, 1000);
      } catch (err) {
        showToast('Errore avvio discovery: ' + err.message, 'error');
      } finally {
        btn.disabled = false;
        btn.classList.remove('opacity-50');
      }
    }

    async function triggerRefresh() {
      const btn = document.getElementById('btn-refresh');
      btn.disabled = true;
      btn.classList.add('opacity-50');
      showToast('Avvio verifica prezzi e notifiche in background...', 'info');
      try {
        const res = await fetch('/api/scheduler/run-refresh?limit=50', { method: 'POST' });
        const data = await res.json();
        showToast(data.message || 'Verifica prezzi avviata!', 'success');
        setTimeout(fetchOverview, 1000);
      } catch (err) {
        showToast('Errore avvio refresh: ' + err.message, 'error');
      } finally {
        btn.disabled = false;
        btn.classList.remove('opacity-50');
      }
    }

    async function triggerEnrichment() {
      const btn = document.getElementById('btn-enrich');
      btn.disabled = true;
      btn.classList.add('opacity-50');
      showToast('Avvio arricchimento taglie in background...', 'info');
      try {
        const res = await fetch('/api/scheduler/run-enrichment?limit_per_store=50', { method: 'POST' });
        const data = await res.json();
        showToast(data.message || 'Arricchimento taglie avviato!', 'success');
        setTimeout(fetchOverview, 1000);
      } catch (err) {
        showToast('Errore arricchimento taglie: ' + err.message, 'error');
      } finally {
        btn.disabled = false;
        btn.classList.remove('opacity-50');
      }
    }

    async function triggerRecluster() {
      const btn = document.getElementById('btn-recluster');
      btn.disabled = true;
      btn.classList.add('opacity-50');
      showToast('Avvio riconciliazione catalogo e entity re-clustering...', 'info');
      try {
        const res = await fetch('/api/catalog/recluster', { method: 'POST' });
        const data = await res.json();
        showToast(data.message || 'Re-clustering avviato!', 'success');
        setTimeout(fetchOverview, 1500);
      } catch (err) {
        showToast('Errore re-clustering: ' + err.message, 'error');
      } finally {
        btn.disabled = false;
        btn.classList.remove('opacity-50');
      }
    }

    async function crawlSingleStore(storeId) {
      if (!storeId) return;
      document.getElementById('single-store-select').value = '';
      showToast('Avvio scansione singola per ' + storeId.toUpperCase() + '...', 'info');
      try {
        const res = await fetch('/api/crawl?store=' + encodeURIComponent(storeId) + '&limit_per_store=150', { method: 'POST' });
        const data = await res.json();
        showToast('Crawl avviato con Session ID: ' + (data.session_id ? data.session_id.slice(0, 8) : 'OK'), 'success');
        setTimeout(fetchOverview, 1500);
      } catch (err) {
        showToast('Errore crawl ' + storeId + ': ' + err.message, 'error');
      }
    }

    function showToast(message, type = 'info') {
      const banner = document.getElementById('toast-banner');
      const content = document.getElementById('toast-content');
      const msg = document.getElementById('toast-message');

      msg.textContent = message;
      if (type === 'success') {
        content.className = 'p-4 rounded-xl flex items-center justify-between text-xs font-medium border bg-emerald-950/80 border-emerald-800 text-emerald-200 shadow-xl';
      } else if (type === 'error') {
        content.className = 'p-4 rounded-xl flex items-center justify-between text-xs font-medium border bg-rose-950/80 border-rose-800 text-rose-200 shadow-xl';
      } else {
        content.className = 'p-4 rounded-xl flex items-center justify-between text-xs font-medium border bg-dark-800 border-dark-700 text-slate-200 shadow-xl';
      }
      banner.classList.remove('hidden');
    }

    function hideToast() {
      document.getElementById('toast-banner').classList.add('hidden');
    }

    // Auto-refresh handler
    document.getElementById('auto-refresh-toggle').addEventListener('change', function(e) {
      if (e.target.checked) {
        startAutoRefresh();
      } else {
        clearInterval(autoRefreshTimer);
      }
    });

    function startAutoRefresh() {
      clearInterval(autoRefreshTimer);
      autoRefreshTimer = setInterval(() => {
        fetchOverview();
      }, 10000);
    }

    // Initial load
    fetchOverview();
    startAutoRefresh();
  </script>
</body>
</html>
"""
