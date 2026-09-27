# Admission Report Proxy on Vercel

This service is deployed as Vercel Node.js Functions. Neither Aliyun Function Compute nor Alibaba TableStore is part of the runtime or deployment path.

- `POST /api/report` verifies the StoreKit transaction JWS, applies the transaction-retry ledger, calls OpenAI's Responses API, and returns the report text.
- `GET /api/health` returns a small health response without exposing configuration or student data.
- The ledger stores HMAC transaction identifiers and purchase/status metadata only. Student details, prompts, and report text are not stored by this service.
- OpenAI requests set `store: false`. This disables Responses API application-state storage; default API abuse-monitoring logs may still retain request content for up to 30 days. See [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data) and disclose this processing in the app's privacy materials.

## Transaction Ledger

The ledger uses Neon Postgres provisioned through the Vercel Marketplace and connected to this project. The report route creates the `admission_report_transactions` table on its first request. It atomically claims each HMAC transaction hash, allows retries after failed or timed-out attempts, and marks successful purchases as used. A request ID fences late function invocations from overwriting a newer retry's state.

The table contains transaction hashes, product ID, status, provider/model, request ID, failure code, and timestamps. Applicant facts and report text are not stored. The new database starts empty; if the former Alibaba TableStore contains previously consumed production purchases, migrate those records before enabling paid reports so they cannot be replayed.

## Vercel Project Setup

The project root is this directory: `serverless/vercel-report-proxy`. For a Git-connected Vercel project, set its **Root Directory** to that path. When deploying from the CLI, run the CLI from this directory so Vercel uses the correct root.

```bash
cd serverless/vercel-report-proxy
npm ci
vercel
```

Provision a Neon Postgres resource for this project through **Vercel Dashboard → Storage** (or `vercel integration add neon/neon`) and select the Free plan if appropriate. Connect it to Production; Vercel supplies `DATABASE_URL`. Mark credentials as sensitive. The report route reads the environment claim from the StoreKit transaction JWS, then verifies the signed transaction with Apple’s matching Sandbox or Production verifier, so TestFlight and App Store purchases can use the same endpoint. After the required values are set, deploy production with `vercel --prod`.

The iOS endpoint is:

```text
https://admission-calculator-vercel-report.vercel.app/api/report
```

The production project is `admission-calculator-vercel-report-proxy` in the `qyf9794's projects` team. Its health endpoint is `https://admission-calculator-vercel-report.vercel.app/api/health`. Set the report URL in the app's `ReportProxyURL` Info.plist build setting for production.

The production domain is live. Until the required environment variables below are configured in the Vercel project, report requests return HTTP 503; the health endpoint only confirms that the function is running.

## Environment Variables

Start from `.env.example`. Keep `.env.local` local and out of source control.

| Variable | Purpose | Sensitive |
|---|---|---|
| `REPORT_PRODUCT_ID` | StoreKit report product ID | No |
| `APPLE_BUNDLE_ID` | iOS bundle identifier | No |
| `APPLE_APPLE_ID` | Numeric App Store Connect app ID for production verification | No |
| `APPLE_ROOT_CERTIFICATES_PEM` | Apple transaction-verification root certificates | Yes |
| `TRANSACTION_HMAC_SECRET` | HMAC key for transaction identifiers | Yes |
| `OPENAI_API_KEY` | OpenAI API project key | Yes |
| `OPENAI_MODEL` | API model ID; defaults to `gpt-6-luna` | No |
| `OPENAI_REASONING_EFFORT` | Reasoning effort; defaults to `medium` | No |
| `OPENAI_BASE_URL` | Defaults to `https://api.openai.com/v1` | No |
| `OPENAI_TIMEOUT_MS` | OpenAI request timeout; defaults to `180000` | No |
| `DATABASE_URL` | Neon Postgres connection string provisioned through Vercel Marketplace | Yes |

The function fails closed when the transaction ledger is not configured. It creates the `admission_report_transactions` table on the first request, then uses atomic Postgres claims to prevent a StoreKit transaction from generating multiple reports. The Apple App Store Server Library verifies the JWS signature against Apple root certificates and requires the decoded environment to match the verifier selected from the JWS claim. Production `APPLE_APPLE_ID` is required because this endpoint accepts Production transactions. Do not deploy a production function without the database connection, Apple verification settings, and OpenAI API key. Never use a `NEXT_PUBLIC_` prefix for these values.

The requested model default is `gpt-6-luna`; confirm that exact API model ID is enabled for the OpenAI project. A model name available in Codex or ChatGPT does not by itself confirm API access. Set `OPENAI_MODEL` to the exact model ID enabled in the API project if it differs.

## Local Development and Checks

```bash
cd serverless/vercel-report-proxy
npm ci
vercel dev
```

Use Vercel's local environment flow or a local `.env.local` based on `.env.example`; never commit real credentials. `npm run check` performs JavaScript syntax checks. End-to-end report smoke tests require a valid Apple Sandbox transaction and configured test ledger/API credentials.

## Privacy and Retry Behavior

The fact packet and generated report are sent to OpenAI but are not written to Neon or server logs. The ledger stores HMAC transaction identifiers, purchase and processing status, model/provider names, request IDs, and timestamps; it does not store applicant facts or reports. The Responses request uses `store: false`; OpenAI's default abuse-monitoring retention may still apply. If generation fails after payment, the ledger marks the transaction `failed`, allowing the same signed transaction to be retried without charging again. If generation succeeds but the client loses the response, the service has no report copy to replay; support or a compensating purchase may be required for that edge case.
