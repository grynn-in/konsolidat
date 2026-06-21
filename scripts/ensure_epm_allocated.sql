-- Idempotent migration for existing ClickHouse volumes (PRD-ALLOCATED-LAYER PR1).
-- Safe to run before deploying alloc_results / alloc_audit_trail models.
CREATE DATABASE IF NOT EXISTS epm_allocated;