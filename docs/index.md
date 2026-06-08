---
hide:
  - toc
  - navigation
---

<div class="ic-hero" markdown>

# Konsolidat

<p class="ic-tagline">Open-source Enterprise Performance Management for Dynamics 365 Finance & Operations</p>

<div class="ic-stats">
  <div class="ic-stat">
    <span class="ic-stat-num">44</span>
    <span class="ic-stat-label">dbt Models</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">26</span>
    <span class="ic-stat-label">Data Tests</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">1</span>
    <span class="ic-stat-label">Excel Function</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">6</span>
    <span class="ic-stat-label">API Endpoints</span>
  </div>
</div>

</div>

<div class="ic-pitch" markdown>

Multi-entity consolidation, Excel-native budgeting, driver-based allocations, and variance analysis — at a fraction of commercial CPM cost. Built on proven open-source infrastructure.

<div class="ic-pills">
  <span class="ic-pill">Consolidation</span>
  <span class="ic-pill">FX Translation</span>
  <span class="ic-pill">Allocations</span>
  <span class="ic-pill">Budgeting</span>
  <span class="ic-pill">Variance</span>
  <span class="ic-pill">Excel Native</span>
  <span class="ic-pill">IFRS / GAAP</span>
  <span class="ic-pill">MIT License</span>
</div>

</div>

## How It Works

<div class="ic-scenarios" markdown>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--finance">REPORTING</span>
  <h3>Excel-Native Financials</h3>
</div>

```
=EPM("USMF", 2024, "Q1", "401100")
=EPM("USMF", 2024, "FY", "601100")
=EPM("GRP", 2024, "Q1", "401100")
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--consolidation">CONSOLIDATION</span>
  <h3>Multi-Entity IFRS Close</h3>
</div>

```
Entity trial balances
  → FX translation (closing/average)
  → CTA calculation
  → NCI split (ownership %)
  → IC elimination
  → Consolidated TB
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--allocation">ALLOCATION</span>
  <h3>Driver-Based Cost Allocation</h3>
</div>

```
Step 1: IT costs   → by headcount
Step 2: Facilities → by sqm (+cascade)
Step 3: Management → by revenue (+cascade)
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--budget">BUDGET</span>
  <h3>Layered Budgeting & Variance</h3>
</div>

```
base + challenge + management + board
  → Spread profiles (even, seasonal)
  → 12 monthly periods
  → Actual vs budget variance
  → Write-back from Excel (EPMSAVE)
```

</div>

</div>

<div class="ic-arch" markdown>

## Architecture

```mermaid
graph LR
    D365[D365 F&O<br/>OData] -->|Airbyte ELT| CH[(ClickHouse<br/>Columnar DW)]
    CH -->|dbt Core| Bronze[Bronze<br/>14 models]
    Bronze --> Silver[Silver<br/>8 models]
    Silver --> Gold[Gold<br/>22 models]
    Gold -->|Frappe API| Frappe[Frappe / Konsol<br/>Settings & Auth]
    Frappe -->|HTTP JSON| Excel[Excel VBA<br/>=EPM formulas]
    Frappe -->|Office.js| Taskpane[Excel Task Pane<br/>Pipeline Control]
```

</div>

<div class="ic-stack">
  <code>D365 F&O</code>
  <code>Airbyte</code>
  <code>ClickHouse</code>
  <code>dbt Core</code>
  <code>Frappe</code>
  <code>Excel VBA</code>
  <code>Office.js</code>
</div>

## vs. Commercial CPM

| | **Tagetik** | **OneStream** | **Anaplan** | **Konsolidat** |
|---|---|---|---|---|
| Consolidation | Native | Native | Add-on | **Native** |
| FX + CTA + IC elim | Native | Native | Manual | **Native** |
| Budget write-back | Native | Native | Native | **Native** |
| Variance analysis | Native | Native | Native | **Native** |
| Excel-native | Plugin | Plugin | No | **=EPM()** |
| D365 integration | Connector | Connector | Via API | **Native OData** |
| Workflow/approvals | Native | Native | Native | **Native** |
| SOX / regulatory | Yes | Yes | Yes | No (not targeted) |
| Web UI | Full | Full | Full | Admin only |
| **3-Year TCO (~50 users)** | **$200–500K** | **$300–700K** | **$700K–1.4M** | **$20–55K** |

<p style="text-align: center; margin-top: 1rem;">
  <a href="evaluation/cost-comparison-vs-commercial/" style="font-size: 0.85rem;">Full comparison with pricing sources and gap analysis →</a>
</p>

## Security

<div class="ic-scenarios" markdown>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--finance">IDENTITY</span>
  <h3>Authentication</h3>
</div>

```
Microsoft Entra ID (Azure AD) SSO
  → OAuth2 / OpenID Connect
  → MSAL.js for Excel Add-in
  → Frappe 2FA (TOTP) per role
  → API key + Bearer token
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--consolidation">ACCESS</span>
  <h3>Role-Based Control</h3>
</div>

```
Reader     → view reports only
Planner    → submit budgets
Controller → edit rules, approve
Admin      → full config + users
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--allocation">NETWORK</span>
  <h3>Transport & Isolation</h3>
</div>

```
TLS everywhere (auto Let's Encrypt)
ClickHouse: private network only
CORS whitelist for Office 365
Rate limiting: 100 req/min/user
```

</div>

<div class="ic-scenario" markdown>
<div class="ic-scenario-header">
  <span class="ic-badge ic-badge--budget">AUDIT</span>
  <h3>Compliance & Logging</h3>
</div>

```
Field-level change tracking
Budget approval workflow trail
API access logging per user
Encryption at rest + in transit
```

</div>

</div>

## Explore the Docs

<div class="ic-nav-grid">

<a class="ic-nav-card" href="features/">
  <strong>Features</strong>
  <span>Everything Konsolidat does — consolidation, allocations, budgeting, reporting</span>
</a>

<a class="ic-nav-card" href="getting-started/quickstart/">
  <strong>Quickstart</strong>
  <span>Zero to first =EPM() value in 15 minutes</span>
</a>

<a class="ic-nav-card" href="getting-started/setup-guide/">
  <strong>Setup Guide</strong>
  <span>Full deployment with D365, Airbyte, dbt, Frappe</span>
</a>

<a class="ic-nav-card" href="getting-started/configuration-reference/">
  <strong>Configuration</strong>
  <span>All settings, env vars, dbt variables</span>
</a>

<a class="ic-nav-card" href="user-guide/excel-vba-guide/">
  <strong>Excel VBA Guide</strong>
  <span>=EPM() function, macros, report patterns</span>
</a>

<a class="ic-nav-card" href="user-guide/consolidation-guide/">
  <strong>Consolidation</strong>
  <span>FX translation, CTA, NCI, IC elimination</span>
</a>

<a class="ic-nav-card" href="api-reference/api-overview/">
  <strong>API Reference</strong>
  <span>3 endpoints — epm_value, epm_batch, health</span>
</a>

<a class="ic-nav-card" href="data-dictionary/data-dictionary-overview/">
  <strong>Data Dictionary</strong>
  <span>44 dbt models, 11 seeds, full lineage</span>
</a>

<a class="ic-nav-card" href="developer-guide/developer-overview/">
  <strong>Developer Guide</strong>
  <span>Extending models, macros, API, contributing</span>
</a>

<a class="ic-nav-card" href="admin-guide/deployment-guide/">
  <strong>Deployment</strong>
  <span>Production setup, monitoring, operations</span>
</a>

<a class="ic-nav-card" href="evaluation/cost-comparison-vs-commercial/">
  <strong>Cost Comparison</strong>
  <span>vs Tagetik, OneStream, Anaplan</span>
</a>

<a class="ic-nav-card" href="evaluation/security-architecture/">
  <strong>Security</strong>
  <span>Architecture, auth, data protection</span>
</a>

</div>
