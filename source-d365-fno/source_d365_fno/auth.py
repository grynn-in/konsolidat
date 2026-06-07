# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""D365 F&O OAuth2 authenticator using Azure AD v2.0 client credentials."""

import time
from typing import Any, Mapping

import requests


class D365OAuth2Authenticator:
    """Acquires and caches an OAuth2 token for D365 F&O via Azure AD v2.0."""

    TOKEN_URL_TEMPLATE = (
        "https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    )

    def __init__(self, config: Mapping[str, Any]):
        self._tenant_id = config["tenant_id"]
        self._client_id = config["client_id"]
        self._client_secret = config["client_secret"]
        env_url = config["environment_url"].rstrip("/")
        self._scope = f"{env_url}/.default"
        self._token: str | None = None
        self._token_expiry: float = 0.0

    @property
    def token_url(self) -> str:
        return self.TOKEN_URL_TEMPLATE.format(tenant_id=self._tenant_id)

    def get_token(self) -> str:
        """Return a valid access token, refreshing if expired."""
        if self._token and time.time() < self._token_expiry:
            return self._token
        return self._refresh_token()

    def _refresh_token(self) -> str:
        resp = requests.post(
            self.token_url,
            data={
                "grant_type": "client_credentials",
                "client_id": self._client_id,
                "client_secret": self._client_secret,
                "scope": self._scope,
            },
            timeout=30,
        )
        resp.raise_for_status()
        payload = resp.json()
        self._token = payload["access_token"]
        # Buffer 60s before actual expiry
        self._token_expiry = time.time() + payload.get("expires_in", 3600) - 60
        return self._token

    def get_auth_header(self) -> Mapping[str, str]:
        """Return Authorization header dict."""
        return {"Authorization": f"Bearer {self.get_token()}"}

    def check_connection(self) -> tuple[bool, str | None]:
        """Validate credentials by acquiring a token."""
        try:
            self._refresh_token()
            return True, None
        except requests.exceptions.HTTPError as e:
            return False, f"Authentication failed: {e.response.status_code} {e.response.text}"
        except Exception as e:
            return False, f"Authentication error: {str(e)}"
