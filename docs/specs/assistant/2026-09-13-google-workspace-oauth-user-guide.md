# Google Workspace access — user guide

Gmail, Calendar, Docs, and Sheets are connected through a self-hosted
workspace-mcp server using single-user server OAuth: one Google account is
authorized once, server-side, and every assistant user shares it. No admin
action is needed beyond deploying the stack.

## To connect the Google account (one-time)

1. Ask the assistant anything that needs Google (e.g. *"check my calendar
   for tomorrow"*). The first time, it replies with an **Authorization URL**.
2. Open that link in your browser, sign in with the household Google account,
   and Allow. The first time Google shows *"Google hasn't verified this
   app"*: click **Advanced → Go to ... (unsafe)** → **Allow** — the app is
   ours; the warning appears because the consent screen isn't reviewed by
   Google.
3. Tell the assistant to retry. Done — the token is stored server-side and
   refreshed automatically; you never see the consent screen again unless
   access is revoked.

If the link sits unused for a while the attempt expires ("Missing OAuth
state"); just ask again to get a fresh one.

## Using the tools

Enable **Google Workspace** in the chat's tools panel, then ask. Read and
write are both enabled (search/send email, create/edit events, edit
docs/sheets). The old per-service tools (Gmail / Calendar / Docs / Sheets)
no longer exist — re-enable **Google Workspace** once if you had the old
ones pinned per chat.

If a consent ever fails with `redirect_uri_mismatch`, tell the admin the
exact URI Google displays so it can be added to the OAuth client in Google
Cloud Console.
