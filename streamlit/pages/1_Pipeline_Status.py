import streamlit as st
import os
import requests
import clickhouse_connect


st.set_page_config(page_title="Pipeline Status", page_icon="🔄", layout="wide")
st.title("Pipeline Status")


def get_ch_client():
    return clickhouse_connect.get_client(
        host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
        username=os.environ.get("CLICKHOUSE_USER", "default"),
        password=os.environ.get("CLICKHOUSE_PASSWORD", "open_epm_dev"),
    )


# Data freshness
st.subheader("Data Freshness")
try:
    client = get_ch_client()
    databases = ["epm_bronze", "epm_silver", "epm_gold"]
    for db in databases:
        tables = client.query(f"SHOW TABLES FROM {db}").result_rows
        if tables:
            st.markdown(f"**{db}**: {len(tables)} tables")
            for table in tables[:5]:
                count = client.query(f"SELECT count() FROM {db}.{table[0]}").result_rows[0][0]
                st.text(f"  {table[0]}: {count:,} rows")
        else:
            st.markdown(f"**{db}**: No tables yet")
    client.close()
except Exception as e:
    st.error(f"ClickHouse connection error: {e}")

# Dagster status
st.subheader("Dagster")
dagster_url = os.environ.get("DAGSTER_URL", "http://localhost:3000")
try:
    resp = requests.get(f"{dagster_url}/server_info", timeout=5)
    if resp.status_code == 200:
        st.success("Dagster webserver is running")
    else:
        st.warning(f"Dagster returned status {resp.status_code}")
except Exception:
    st.warning("Dagster webserver not reachable")
