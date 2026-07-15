"""Parent notification senders.

Deliberately pluggable. The default provider is "dryrun", which renders and logs
a message but transmits nothing, so the whole approve-and-send flow can be
exercised without contacting a real parent. Point WHATSAPP_PROVIDER at a real
provider only once you trust the absent list.
"""

import re

import requests

from . import config

# E.164, e.g. +919876543210. Stored exactly as handed to the provider.
PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")


class SendError(Exception):
    pass


def render_absence(student: dict, date: str, label: str) -> str:
    return config.ABSENCE_TEMPLATE.format(
        name=student["name"],
        roll_no=student["roll_no"],
        class_name=student["class_name"] or "",
        date=date,
        label=label,
        school=config.SCHOOL_NAME,
    )


def absence_params(student: dict, date: str, label: str) -> list[str]:
    """Template variables, in the {{1}}..{{5}} order the approved template uses."""
    return [student["name"], student["roll_no"], label, date, config.SCHOOL_NAME]


class DryRunSender:
    """Transmits nothing. Every message is recorded with status 'dry_run'."""

    name = "dryrun"
    sends_for_real = False

    def send(self, to_phone: str, body: str, params: list[str] | None = None) -> str | None:
        return None


class TwilioSender:
    """WhatsApp via Twilio's official API."""

    name = "twilio"
    sends_for_real = True

    def __init__(self):
        missing = [
            k for k, v in {
                "TWILIO_ACCOUNT_SID": config.TWILIO_ACCOUNT_SID,
                "TWILIO_AUTH_TOKEN": config.TWILIO_AUTH_TOKEN,
                "WHATSAPP_FROM": config.WHATSAPP_FROM,
            }.items() if not v
        ]
        if missing:
            raise SendError(f"Twilio provider selected but not configured: {', '.join(missing)}")

    def send(self, to_phone: str, body: str, params: list[str] | None = None) -> str:
        url = f"https://api.twilio.com/2010-04-01/Accounts/{config.TWILIO_ACCOUNT_SID}/Messages.json"
        try:
            resp = requests.post(
                url,
                auth=(config.TWILIO_ACCOUNT_SID, config.TWILIO_AUTH_TOKEN),
                data={
                    "From": f"whatsapp:{config.WHATSAPP_FROM}",
                    "To": f"whatsapp:{to_phone}",
                    "Body": body,
                },
                timeout=config.WHATSAPP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise SendError(f"Could not reach Twilio: {exc}") from exc
        if resp.status_code >= 300:
            raise SendError(f"Twilio rejected the message ({resp.status_code}): {resp.text[:200]}")
        return resp.json().get("sid", "")


class MetaSender:
    """WhatsApp via Meta's official Cloud API (graph.facebook.com).

    Free path: the developer "test number" can message up to 5 verified
    recipients at no cost, which covers a pilot. Business-initiated messages
    outside a 24h reply window MUST use an approved template, so when
    META_TEMPLATE_NAME is set we send that template with the absence variables;
    with no template configured we fall back to plain text, which WhatsApp only
    delivers inside an open 24h session (i.e. after the parent messaged first).
    """

    name = "meta"
    sends_for_real = True

    def __init__(self):
        missing = [
            k for k, v in {
                "META_ACCESS_TOKEN": config.META_ACCESS_TOKEN,
                "META_PHONE_NUMBER_ID": config.META_PHONE_NUMBER_ID,
            }.items() if not v
        ]
        if missing:
            raise SendError(f"Meta provider selected but not configured: {', '.join(missing)}")

    def send(self, to_phone: str, body: str, params: list[str] | None = None) -> str:
        url = f"https://graph.facebook.com/v21.0/{config.META_PHONE_NUMBER_ID}/messages"
        payload: dict = {"messaging_product": "whatsapp", "to": to_phone}
        if config.META_TEMPLATE_NAME:
            template: dict = {
                "name": config.META_TEMPLATE_NAME,
                "language": {"code": config.META_TEMPLATE_LANG},
            }
            # hello_world (the built-in test template) takes no variables;
            # a real absence template takes them as {{1}}..{{n}} body params.
            if params and config.META_TEMPLATE_HAS_PARAMS:
                template["components"] = [{
                    "type": "body",
                    "parameters": [{"type": "text", "text": p} for p in params],
                }]
            payload.update({"type": "template", "template": template})
        else:
            payload.update({"type": "text", "text": {"body": body}})
        try:
            resp = requests.post(
                url,
                headers={"Authorization": f"Bearer {config.META_ACCESS_TOKEN}"},
                json=payload,
                timeout=config.WHATSAPP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise SendError(f"Could not reach Meta: {exc}") from exc
        if resp.status_code >= 300:
            try:
                detail = resp.json().get("error", {}).get("message", resp.text[:200])
            except ValueError:
                detail = resp.text[:200]
            raise SendError(f"Meta rejected the message ({resp.status_code}): {detail}")
        messages = resp.json().get("messages") or [{}]
        return messages[0].get("id", "")


_PROVIDERS = {"dryrun": DryRunSender, "twilio": TwilioSender, "meta": MetaSender}


def get_sender():
    """Build the configured sender. Unknown values fail closed onto dry-run."""
    provider = _PROVIDERS.get(config.WHATSAPP_PROVIDER.strip().lower())
    if provider is None:
        raise SendError(
            f"Unknown WHATSAPP_PROVIDER '{config.WHATSAPP_PROVIDER}'. "
            f"Valid options: {', '.join(_PROVIDERS)}"
        )
    return provider()
