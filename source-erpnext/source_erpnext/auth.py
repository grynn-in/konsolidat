# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

"""ERPNext token authenticator for the Frappe REST API.

Frappe authenticates API calls with a static header
``Authorization: token <api_key>:<api_secret>`` — there is no token-exchange
step. This class builds that header and validates the credentials by calling a
lightweight authenticated endpoint.
"""

import logging
from typing import Any, Mapping

import requests

logger = logging.getLogger("airbyte")


def auth_error_message(exc: Exception) -> str:
    """Render a generic, non-sensitive auth-failure message.

    The raw server body is never echoed (it can contain request metadata); it
    is logged separately at debug level by the caller.
    """
    if isinstance(exc, requests.exceptions.HTTPError):
        status = exc.response.status_code if exc.response is not None else "unknown"
        return (
            f"Authentication failed (HTTP {status}). Check host_url, api_key "
            "and api_secret, and that the key's user has read access to the "
            "GL doctypes."
        )
    return f"Connection error: {type(exc).__name__}"


class FrappeTokenAuthenticator:
    """Builds the Frappe token header and validates credentials."""

    def __init__(self, config: Mapping[str, Any]):
        self._host_url = config["host_url"].rstrip("/")
        self._api_key = config["api_key"]
        self._api_secret = config["api_secret"]

    @property
    def host_url(self) -> str:
        return self._host_url

    def get_auth_header(self) -> Mapping[str, str]:
        """Return the Authorization header dict."""
        return {"Authorization": f"token {self._api_key}:{self._api_secret}"}

    def check_connection(self) -> tuple[bool, str | None]:
        """Validate credentials against frappe.auth.get_logged_user.

        Returns a generic, non-sensitive message to the caller. The full server
        response is logged at debug level only.
        """
        url = f"{self._host_url}/api/method/frappe.auth.get_logged_user"
        try:
            resp = requests.get(url, headers=self.get_auth_header(), timeout=30)
            resp.raise_for_status()
            return True, None
        except requests.exceptions.HTTPError as e:
            logger.debug(
                "ERPNext auth check failed (HTTP %s): %s",
                getattr(e.response, "status_code", "?"),
                getattr(e.response, "text", ""),
            )
            return False, auth_error_message(e)
        except requests.exceptions.RequestException as e:
            logger.debug("ERPNext auth check error", exc_info=True)
            return False, auth_error_message(e)
