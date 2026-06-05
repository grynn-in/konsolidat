from cube import config

@config('scheduled_refresh_contexts')
def scheduled_refresh_contexts() -> list:
    return [{'securityContext': {'role': 'admin'}}]

@config('check_sql_auth')
def check_sql_auth(req, username, password) -> dict:
    """Authenticate SQL API requests (Excel/ODBC connections)."""
    import os
    expected_user = os.environ.get('CUBEJS_SQL_USER', 'epm_excel')
    expected_pass = os.environ.get('CUBEJS_SQL_PASSWORD', 'epm_excel_password')
    if username == expected_user and password == expected_pass:
        return {'password': password, 'securityContext': {'role': 'analyst'}}
    raise Exception('Invalid credentials')
