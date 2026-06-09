# GET get_hierarchy_tree

Returns the consolidation hierarchy as a nested JSON tree (PRD-8).

## Endpoint

```
GET /api/method/konsol.api.get_hierarchy_tree
```

**Authentication**: Required (Frappe session cookie)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `consolidation_group` | string | No | Filter to a subtree rooted at this group. Omit for full tree. |

## Response

```json
{
  "message": {
    "tree": [
      {
        "name": "CG-GROUP_CORP-GBMF",
        "consolidation_group": "GROUP_CORP",
        "data_area_id": "GBMF",
        "entity_name": "GB Manufacturing",
        "parent_group": null,
        "hierarchy_level": 1,
        "ownership_pct": 100,
        "consolidation_method": "full",
        "children": [
          {
            "name": "CG-GROUP_EMEA-DEMF",
            "consolidation_group": "GROUP_EMEA",
            "data_area_id": "DEMF",
            "entity_name": "DE Manufacturing",
            "parent_group": "GROUP_CORP",
            "hierarchy_level": 2,
            "ownership_pct": 80,
            "consolidation_method": "full",
            "children": []
          }
        ]
      }
    ]
  }
}
```

## Tree Structure

Each node contains:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Frappe document name |
| `consolidation_group` | string | Group identifier |
| `data_area_id` | string | Entity/legal entity code |
| `entity_name` | string | Display name |
| `parent_group` | string/null | Parent group (null for root) |
| `hierarchy_level` | integer | Depth in tree (1 = root) |
| `ownership_pct` | number | Direct ownership percentage |
| `consolidation_method` | string | `full` or `equity` |
| `children` | array | Child nodes (recursive) |

## Examples

### Full hierarchy

```bash
curl "http://localhost:8069/api/method/konsol.api.get_hierarchy_tree" \
  -b "cookies.txt"
```

### Subtree for a specific group

```bash
curl "http://localhost:8069/api/method/konsol.api.get_hierarchy_tree?\
consolidation_group=GROUP_EMEA" \
  -b "cookies.txt"
```
