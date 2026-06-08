# Service Credentials (local dev)

## ClickHouse
- Host: localhost:8123 (HTTP), localhost:9000 (native)
- User: default
- Password: open_epm_dev

## Airbyte (local Kind cluster, v2.1.0 Community)
- URL: http://localhost:8000
- Email: admin@openepm.local
- Password: EcxdTGV9LGWkIQB0m7glDcbD2Y6CyTK2
- Client-Id: 5c9a6639-a048-456e-bc43-8fd027c65149
- Client-Secret: JUb4LScMbBjsQjGe0TsSS9sINqDhkHLa
- Setup: abctl local install --low-resource-mode
- API auth: POST /api/v1/applications/token with client_id/client_secret → Bearer JWT
- Use /api/public/v1/ for REST (GET); /api/v1/ for internal (POST with workspaceId)
- Workspace: 0ef6d3f5-69f9-4fd4-85b9-5a7a4e6bdf03
- Connection: dda9723e-3415-47ce-8523-472d754185cb (D365→ClickHouse epm_raw, 9 streams)
- Note: Airbyte syncs 9 entities to epm_raw; sync_d365_odata.py syncs 15 to epm_bronze

## Cube.js
- API: http://localhost:4000
- SQL API: localhost:15432
- API Secret: open_epm_dev_secret
- SQL User: epm_excel
- SQL Password: epm_excel_password

## D365 F&O Sandbox
- Tenant: 13588042-fe43-45bb-8ce1-83b2e6dd126c
- Client ID: 63fd2986-b653-4151-a5c0-8ce53efec64d
- Client Secret: (in .env file)
- URL: https://bizapps2.sandbox.operations.dynamics.com

## FastAPI
- URL: http://localhost:8080
- No auth (local dev)

## Dagster
- URL: http://localhost:3000
- No auth (dev mode, SQLite backend at /tmp/dagster_home)
