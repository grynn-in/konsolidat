import streamlit as st
import os
import requests


st.set_page_config(page_title="Scenario Manager", page_icon="🎯", layout="wide")
st.title("Scenario Manager")

API_URL = os.environ.get("API_URL", "http://localhost:8080")

# List scenarios
st.subheader("Active Scenarios")
try:
    resp = requests.get(f"{API_URL}/api/v1/scenarios", timeout=5)
    if resp.status_code == 200:
        scenarios = resp.json()
        if scenarios:
            for s in scenarios:
                col1, col2, col3 = st.columns([2, 2, 1])
                col1.text(f"{s['scenario_name']} ({s['scenario_id']})")
                col2.text(f"Type: {s['scenario_type']}")
                col3.text("Active" if s.get("is_active") else "Inactive")
        else:
            st.info("No scenarios defined yet")
    else:
        st.warning("Could not fetch scenarios from API")
except Exception:
    st.warning("API not reachable")

# Create new scenario
st.subheader("Create New Scenario")
with st.form("create_scenario"):
    scenario_id = st.text_input("Scenario ID (e.g., FC_2025_Q2)")
    scenario_name = st.text_input("Scenario Name")
    scenario_type = st.selectbox("Type", ["budget", "forecast", "whatif"])
    created_by = st.text_input("Created By (email)")

    if st.form_submit_button("Create Scenario"):
        if scenario_id and scenario_name and created_by:
            try:
                resp = requests.post(
                    f"{API_URL}/api/v1/scenarios",
                    json={
                        "scenario_id": scenario_id,
                        "scenario_name": scenario_name,
                        "scenario_type": scenario_type,
                        "created_by": created_by,
                    },
                    timeout=5,
                )
                if resp.status_code == 200:
                    st.success(f"Scenario '{scenario_id}' created!")
                    st.rerun()
                else:
                    st.error(f"Error: {resp.json().get('detail', resp.text)}")
            except Exception as e:
                st.error(f"API error: {e}")
        else:
            st.warning("Please fill all fields")

# Budget data preview
st.subheader("Budget Data Preview")
preview_scenario = st.text_input("Scenario ID to preview", value="BUDGET")
if st.button("Load"):
    try:
        resp = requests.get(
            f"{API_URL}/api/v1/budget/{preview_scenario}",
            timeout=5,
        )
        if resp.status_code == 200:
            data = resp.json()
            if data:
                import pandas as pd

                st.dataframe(pd.DataFrame(data), use_container_width=True)
            else:
                st.info("No budget data for this scenario")
    except Exception as e:
        st.error(f"API error: {e}")
