import streamlit as st
import os
import clickhouse_connect
import pandas as pd


st.set_page_config(page_title="Data Quality", page_icon="✅", layout="wide")
st.title("Data Quality")


def get_ch_client():
    return clickhouse_connect.get_client(
        host=os.environ.get("CLICKHOUSE_HOST", "localhost"),
        port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
        username=os.environ.get("CLICKHOUSE_USER", "default"),
        password=os.environ.get("CLICKHOUSE_PASSWORD", "open_epm_dev"),
    )


try:
    client = get_ch_client()

    # Row counts per layer
    st.subheader("Row Counts by Layer")
    layers = {
        "epm_bronze": "Bronze",
        "epm_silver": "Silver",
        "epm_gold": "Gold",
        "epm_staging": "Staging",
    }

    for db, label in layers.items():
        tables = client.query(f"SHOW TABLES FROM {db}").result_rows
        if tables:
            rows_data = []
            for table in tables:
                count = client.query(f"SELECT count() FROM {db}.{table[0]}").result_rows[0][0]
                rows_data.append({"Table": table[0], "Rows": count})
            st.markdown(f"### {label} Layer")
            st.dataframe(pd.DataFrame(rows_data), use_container_width=True)

    # TB Balance check
    st.subheader("Trial Balance Reconciliation")
    try:
        tb_check = client.query("""
            SELECT
                data_area_id,
                fiscal_year,
                sum(period_debit) as total_debit,
                sum(period_credit) as total_credit,
                abs(sum(period_debit) - sum(period_credit)) as imbalance
            FROM epm_gold.gold_trial_balance
            GROUP BY data_area_id, fiscal_year
            ORDER BY data_area_id, fiscal_year
        """)
        if tb_check.result_rows:
            df = pd.DataFrame(
                tb_check.result_rows,
                columns=["Entity", "Year", "Total Debit", "Total Credit", "Imbalance"],
            )
            st.dataframe(df, use_container_width=True)
        else:
            st.info("No trial balance data yet")
    except Exception:
        st.info("Gold layer not populated yet")

    client.close()
except Exception as e:
    st.error(f"ClickHouse connection error: {e}")
