---
hide:
  - toc
  - navigation
---

<div class="ic-hero" markdown>

# Konsolidat

<p class="ic-tagline">Open-source Enterprise Performance Management</p>

<div class="ic-stats">
  <div class="ic-stat">
    <span class="ic-stat-num">=EPM()</span>
    <span class="ic-stat-label">Excel Native</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">90%</span>
    <span class="ic-stat-label">Cost Savings</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">100%</span>
    <span class="ic-stat-label">SQL Auditable</span>
  </div>
  <div class="ic-stat">
    <span class="ic-stat-num">$0</span>
    <span class="ic-stat-label">Vendor Lock-in</span>
  </div>
</div>

</div>

<div class="ic-pitch" markdown>

For 27 years, CPM vendors have tried to move financial analysis out of Excel and into web browsers. We think they're wrong. Excellent analysis thrives on Excel — not on the web. Konsolidat keeps it there.

Multi-entity consolidation, budgeting, allocations, and variance analysis — powered by `=EPM()` in the spreadsheet your finance team already knows.

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

<a class="ic-cta" href="https://calendly.com/vinayak-nayak/30min" target="_blank">Book a Demo</a>

</div>

<div class="ic-built-on">
  <p class="ic-built-on-label">Built on Open Source Stack</p>
  <div class="ic-logo-track">
    <div class="ic-logo-card">
      <div class="ic-logo-mark" style="color: #FADB14;">CH</div>
      <strong>ClickHouse</strong>
      <span>Columnar Analytics</span>
    </div>
    <div class="ic-logo-card">
      <div class="ic-logo-mark" style="color: #615EFF;">ab</div>
      <strong>Airbyte</strong>
      <span>ELT Data Integration</span>
    </div>
    <div class="ic-logo-card">
      <div class="ic-logo-mark" style="color: #FF694A;">dbt</div>
      <strong>dbt Core</strong>
      <span>SQL Transformations</span>
    </div>
    <div class="ic-logo-card">
      <div class="ic-logo-mark" style="color: #0089FF;">F</div>
      <strong>Frappe</strong>
      <span>Web Framework & API</span>
    </div>
    <div class="ic-logo-card">
      <div class="ic-logo-mark" style="color: #FF6492;">&#9671;</div>
      <strong>Cube</strong>
      <span>Semantic Layer</span>
    </div>
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

## vs. Commercial CPM

| | **Tagetik** | **OneStream** | **Anaplan** | **Konsolidat** |
|---|---|---|---|---|
| Consolidation | Native | Native | Add-on | **Native** |
| FX + CTA + IC elim | Native | Native | Manual | **Native** |
| Budget write-back | Native | Native | Native | **Native** |
| Variance analysis | Native | Native | Native | **Native** |
| Excel-native | Plugin | Plugin | No | **=EPM()** |
| ERP integration | Connector | Connector | Via API | **Native OData** |
| Workflow/approvals | Native | Native | Native | **Native** |
| SOX / regulatory | Yes | Yes | Yes | No (not targeted) |
| Web UI | Full | Full | Full | Admin only |
| **3-Year TCO (~50 users)** | **$200–500K** | **$300–700K** | **$700K–1.4M** | **$20–55K** |

<p style="text-align: center; margin-top: 1rem;">
  <a href="evaluation/cost-comparison-vs-commercial/" style="font-size: 0.85rem;">Full comparison with pricing sources and gap analysis →</a>
</p>

<p style="text-align: center; margin-top: 1.5rem;">
  <a class="ic-cta" href="https://calendly.com/vinayak-nayak/30min" target="_blank">See How You Save 90% — Book a Call</a>
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

<p style="text-align: center; margin-top: 1.5rem;">
  <a class="ic-cta" href="https://calendly.com/vinayak-nayak/30min" target="_blank">Book a 30-Min Demo</a>
</p>

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
  <span>Full deployment with Airbyte, dbt, Frappe</span>
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

<div style="text-align: center; padding: 3rem 1rem; border-top: 1.5px solid var(--ic-border-strong); margin-top: 2.5rem;">
  <p style="font-family: 'Archivo', sans-serif; font-size: 1.3rem; font-weight: 700; margin-bottom: 0.5rem;">Ready to cut your CPM costs by 90%?</p>
  <p style="color: var(--ic-soft); margin-bottom: 1.5rem;">30-minute call. No slides. We'll show you the live stack.</p>
  <a class="ic-cta ic-cta--lg" href="https://calendly.com/vinayak-nayak/30min" target="_blank">Book Your Demo Now</a>
</div>
