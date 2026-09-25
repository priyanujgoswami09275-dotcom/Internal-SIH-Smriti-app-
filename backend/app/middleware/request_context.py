"""Request-scoped client provenance for compliance audit records."""

from contextvars import ContextVar, Token
from typing import Optional

_request_client_ip: ContextVar[Optional[str]] = ContextVar(
    "request_client_ip",
    default=None,
)
NON_REQUEST_AUDIT_IP = "non-request"


def get_request_client_ip() -> Optional[str]:
    return _request_client_ip.get()


def bind_request_client_ip(ip_address: Optional[str]) -> Token:
    return _request_client_ip.set(ip_address)


def reset_request_client_ip(token: Token) -> None:
    _request_client_ip.reset(token)


def resolve_audit_ip(ip_address: Optional[str] = None) -> str:
    """Resolve explicit, request, or honest non-request audit provenance.

    The middleware records the transport peer address and deliberately does not
    trust a client-supplied forwarding header without proxy configuration.
    """
    if ip_address is not None:
        return ip_address
    return get_request_client_ip() or NON_REQUEST_AUDIT_IP
