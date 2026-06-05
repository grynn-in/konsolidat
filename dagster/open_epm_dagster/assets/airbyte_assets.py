from dagster_airbyte import AirbyteCloudResource, load_assets_from_airbyte_instance
import os


# Auto-discover Airbyte connections and create assets
# Airbyte runs via abctl (local K8s), accessed via API on localhost:8000
airbyte_resource = AirbyteCloudResource(
    api_key=os.environ.get("AIRBYTE_API_KEY", ""),
    client_id=os.environ.get("AIRBYTE_CLIENT_ID", ""),
    client_secret=os.environ.get("AIRBYTE_CLIENT_SECRET", ""),
)

# For local Airbyte (abctl), use the OSS resource:
# from dagster_airbyte import AirbyteResource
# airbyte_resource = AirbyteResource(
#     host=os.environ.get("AIRBYTE_API_URL", "localhost"),
#     port="8000",
# )

airbyte_assets = load_assets_from_airbyte_instance(
    airbyte_resource,
    key_prefix=["airbyte"],
)
