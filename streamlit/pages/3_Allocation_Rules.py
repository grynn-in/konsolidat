import streamlit as st
import os
import pandas as pd
from pathlib import Path


st.set_page_config(page_title="Allocation Rules", page_icon="📊", layout="wide")
st.title("Allocation Rule Editor")

SEED_DIR = Path(os.environ.get("SEED_DIR", "../dbt_project/seeds"))
RULES_FILE = SEED_DIR / "allocation_rules.csv"
DRIVERS_FILE = SEED_DIR / "allocation_drivers_headcount.csv"

# Allocation Rules
st.subheader("Allocation Rules")
try:
    rules_df = pd.read_csv(RULES_FILE)
    edited_rules = st.data_editor(rules_df, num_rows="dynamic", use_container_width=True)

    if st.button("Save Rules"):
        edited_rules.to_csv(RULES_FILE, index=False)
        st.success("Rules saved. Run `dbt build --select gold_allocation_results` to apply.")
except FileNotFoundError:
    st.warning(f"Rules file not found at {RULES_FILE}")

# Driver Data
st.subheader("Headcount Drivers")
try:
    drivers_df = pd.read_csv(DRIVERS_FILE)
    edited_drivers = st.data_editor(drivers_df, num_rows="dynamic", use_container_width=True)

    if st.button("Save Drivers"):
        edited_drivers.to_csv(DRIVERS_FILE, index=False)
        st.success("Drivers saved. Run `dbt seed && dbt build --select gold_allocation_results` to apply.")
except FileNotFoundError:
    st.warning(f"Drivers file not found at {DRIVERS_FILE}")
