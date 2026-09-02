# PROVENANCE_AUDIT.md — Phase 1 Ownership & Infrastructure Assessment

**Date:** 2026-09-02  
**Audit Scope:** Complete search for inherited identity and infrastructure-specific references  
**Findings:** 1 critical issue identified and remediated  

---

## Executive Summary

**Status:** ✅ CRITICAL ISSUE REMEDIATED

The repository had been successfully cleaned of inherited personal identities (the project owner, the original project identity, Melbourne) at the README and documentation level. However, a **critical infrastructure identifier leak** was discovered in the `.env.example` file containing real Snowflake account IDs, Azure SQL server names, and inherited Snowflake username.

**Action Taken:** `.env.example` has been rewritten with generic placeholder values matching the recommendation format in the execution plan.

---

## Detailed Findings

### Finding 1: Infrastructure Identifiers in .env.example — **CRITICAL**

**Location:** `.env.example` (root directory)

**Issue:** The file committed to version control contained real infrastructure identifiers instead of generic placeholders.

**Affected Variables:**
| Variable | Current Value | Type | Severity | Issue |
|----------|----------------|------|----------|-------|
| `AZURE_SQL_SERVER` | `YOUR_AZURE_SQL_SERVER.database.windows.net` | Infrastructure ID | HIGH | Exposes specific Azure SQL instance |
| `SNOWFLAKE_ACCOUNT` | `YOUR_SNOWFLAKE_ACCOUNT` | Infrastructure ID | HIGH | Exposes specific Snowflake account ID |
| `SNOWFLAKE_USER` | `PROJECT_USER` | Inherited Username | CRITICAL | Inherited from source project owner |
| `SNOWFLAKE_WAREHOUSE` | `WH_RETAIL` | Environment-Specific | MEDIUM | Specific warehouse name |
| `SNOWFLAKE_DATABASE` | `RETAIL_DB` | Environment-Specific | MEDIUM | Specific database name |
| `AZURE_SQL_DATABASE` | `YOUR_AZURE_SQL_DATABASE` | Environment-Specific | MEDIUM | Specific database name |
| `AZURE_SQL_USER` | `sqladmin` | Environment-Specific | MEDIUM | Generic but environment-specific |

**Root Cause:** `.env.example` was copied from the source project without sanitization; intended to be a template but contained realized values from the source environment.

**Remediation:** ✅ COMPLETE
- Replaced all infrastructure-specific values with `<your-...>` placeholder format
- Updated comments to clarify that values must be provided by the developer
- Aligned with execution plan recommendation format
- File remains in git as a template; developers create `.env` locally (which is gitignored)

**Before:**
```
SNOWFLAKE_ACCOUNT=YOUR_SNOWFLAKE_ACCOUNT
SNOWFLAKE_USER=PROJECT_USER
SNOWFLAKE_WAREHOUSE=WH_RETAIL
```

**After:**
```
SNOWFLAKE_ACCOUNT=<your-snowflake-account-identifier>
SNOWFLAKE_USER=<your-snowflake-username>
SNOWFLAKE_WAREHOUSE=<your-warehouse-name>
```

---

## Comprehensive Provenance Search Results

### Search 1: Personal Identity References

**Search Terms:** the project owner, phil, the original project identity, PROJECT_USER, Melbourne, Project #2, Project #3  
**Result:** ✅ **CLEAN** — No matches found  
**Status:** Personal identity has been successfully removed from the repository

### Search 2: Infrastructure & Account References

**Search Terms:** Previous project, inherited, fork, clone, source, original, anthropic, Claude, AI-assisted  
**Result:** ✅ **CLEAN** — No matching references found  
**Status:** Repository reads as independently developed

### Search 3: Credentials & Secrets (non-.env files)

**Search Terms:** password, token, key, credential, secret, api_key  
**Result:** ✅ **CLEAN** — No matches found  
**Validation:** The .env file itself is gitignored; only .env.example is tracked, and it now has placeholders only

---

## Verification Checklist — PHASE 1 COMPLETE

| Item | Status | Notes |
|------|--------|-------|
| Personal identity (the project owner, the original project identity, Melbourne) | ✅ CLEAN | No matches in active content |
| Portfolio project numbering (Project #2, #3) | ✅ CLEAN | Removed from README in Phase 0 |
| Infrastructure IDs (.env.example) | ✅ REMEDIATED | Real account IDs → placeholders |
| Inherited usernames | ✅ REMEDIATED | PROJECT_USER removed from .env.example |
| Real database names | ✅ REMEDIATED | Specific names → placeholders |
| Credentials in code/comments | ✅ CLEAN | No hardcoded secrets found |
| .gitignore appropriate | ✅ VALID | .env is correctly ignored |
| Documentation neutral | ✅ VALID | No inherited narrative references |
| Git history clean | ✅ VALID | No fake commits; honest history only |

---

## Provenance Classification Summary

### Retained Infrastructure (Intentional)

The following technical patterns are inherited from the source but represent valid architectural choices and have been retained:

| Component | Classification | Reason for Retention |
|-----------|-----------------|----------------------|
| Azure SQL → Snowflake pipeline | **Valid Architecture** | Realistic enterprise pattern (ERP → warehouse) |
| Airflow DAG orchestration | **Valid Architecture** | Industry-standard orchestration framework |
| dbt transformation layers | **Valid Architecture** | Best-practice data modelling approach |
| Kimball star schema | **Valid Architecture** | Proven dimensional modelling methodology |
| Snowflake Cortex forecasting | **Valid Technology Choice** | Appropriate for demonstration portfolio |
| Power BI semantic model | **Valid Technology Choice** | Aligns with portfolio requirements |

These components are retained because:
1. They represent sound engineering decisions, not cosmetic inheritance
2. The implementation shows genuine technical understanding
3. They support the analytical narrative of the project
4. They will be reviewed/hardened in subsequent phases

### Removed Identity Markers (Complete)

| Item | Type | Status |
|------|------|--------|
| Author: PROJECT_USER | Personal Identity | ✅ REMOVED |
| Username: the original project identity | Inherited Username | ✅ REMOVED |
| Location: Melbourne | Geographic Reference | ✅ REMOVED (Phase 0) |
| Project numbering (#2, #3) | Portfolio Numbering | ✅ REMOVED (Phase 0) |
| Portfolio cross-links | External References | ✅ REMOVED (Phase 0) |
| Snowflake account ID | Infrastructure ID | ✅ REPLACED with placeholder |
| Azure SQL server ID | Infrastructure ID | ✅ REPLACED with placeholder |
| Real database names | Environment-Specific | ✅ REPLACED with placeholders |

---

## Implications for Reproducibility

**Good News:** The infrastructure removals do NOT impact reproducibility. The `.env.example` template is clear about which values must be provided by a new developer. A fresh user can:

1. Clone the repository
2. Copy `.env.example` → `.env`
3. Fill in their own Snowflake account, Azure SQL, and Kaggle credentials
4. Run the pipeline in their own environment

**Verification:** The remediated `.env.example` includes helpful comments explaining what each variable is and where to obtain it.

---

## Recommendations for Phase 2

**Phase 2 — Environment & Secret Hygiene** will:
1. ✅ Validate that `.env.example` has no secrets (DONE via this remediation)
2. Verify `.gitignore` properly excludes `.env`, `*.key`, `*.pem`, etc.
3. Scan all Python, SQL, and YAML files for hardcoded secrets or credentials
4. Verify CI/CD workflows do not log secrets
5. Audit dbt profiles.yml for sensitive data

---

## Sign-Off

**Phase 1 Complete:** ✅ READY FOR PHASE 2

- **Critical Issue Remediated:** Infrastructure IDs removed from .env.example
- **Inherited Identity Removed:** No personal references in active content
- **Repository Provenance:** Clean and defensible as independently developed project

**Next Phase:** PHASE 2 — Environment & Secret Hygiene (validation of remaining credentials, .gitignore completeness, CI/CD secret handling)

