# Google Workspace access — user guide

Connecting Gmail, Calendar, Docs, and Sheets to the assistant (Open WebUI at
`agentic.overachieverlabs.com`) is a one-time, per-user step. Tokens are stored
per user — nobody else in your household sees your mail or calendar.

No admin action is needed beyond deploying the stack; users do this themselves.

## To connect your Google account

1. Log in to the assistant (`agentic.overachieverlabs.com`) in your browser.
2. Visit each of these four links, one at a time. Google will ask you to sign
   in with **your** Google account:

   - `https://agentic.overachieverlabs.com/oauth/clients/mcp:google-gmail/authorize`
   - `https://agentic.overachieverlabs.com/oauth/clients/mcp:google-calendar/authorize`
   - `https://agentic.overachieverlabs.com/oauth/clients/mcp:google-docs/authorize`
   - `https://agentic.overachieverlabs.com/oauth/clients/mcp:google-sheets/authorize`

3. The first time, Google shows *"Google hasn't verified this app"*. Click
   **Advanced → Go to Compose Yourself Assistant (unsafe)** → **Allow**. The
   app is ours; the warning appears because the OAuth consent screen isn't
   reviewed by Google.
4. Repeat for the remaining links. You will not see the consent screen again
   unless you revoke access.

If a link ever redirects to a Google error mentioning `redirect_uri_mismatch`,
tell the admin the exact URI Google displays so it can be added to the OAuth
client in Google Cloud Console.