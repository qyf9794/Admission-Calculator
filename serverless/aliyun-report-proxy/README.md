# Aliyun Report Proxy

This is the lightweight backend for paid AI reports:

- iOS buys one report through StoreKit 2.
- iOS sends the StoreKit transaction JWS plus the local report fact packet.
- This function verifies the Apple transaction, calls Alibaba Cloud Model Studio/Qwen, and returns report text.
- It does not store the student profile, high-school info, grades, selected schools, prompt body, or generated report text.
- If the model call fails after Apple has charged the user, the iOS app keeps the signed transaction locally so the user can retry without paying again.

## Required Environment Variables

```bash
REPORT_PRODUCT_ID=admission_calculator_ai_report
APPLE_BUNDLE_ID=com.qyf9794.AdmissionCalculator
APPLE_APPLE_ID=<numeric app Apple ID for production>
APPLE_ENVIRONMENT=Sandbox # use Production after App Store release
APPLE_ROOT_CERTIFICATES_PEM='<Apple root certificate PEM text>'
DASHSCOPE_API_KEY=<Aliyun Model Studio API key>
DASHSCOPE_MODEL=qwen3.7-plus
DASHSCOPE_API_MODE=multimodal # optional; qwen3.7 models select this automatically
DASHSCOPE_TIMEOUT_MS=240000
DASHSCOPE_SAFE_TIMEOUT_MS=240000
DASHSCOPE_MAX_TOKENS=3500
DASHSCOPE_MAX_RETRIES=0
DASHSCOPE_RETRY_BASE_DELAY_MS=800
MAX_INSTRUCTION_CHARACTERS=2500
MAX_INPUT_CHARACTERS=20000
MAX_REPORT_CHARACTERS=10000
ENABLE_DASHSCOPE_DIAGNOSTICS=false
```

For local connectivity tests only:

```bash
SKIP_APPLE_VERIFY_FOR_LOCAL_DEV=true
LOCAL_DEV_SERVER=true
PORT=8787
```

Never enable `SKIP_APPLE_VERIFY_FOR_LOCAL_DEV` in production.

## Function Compute Runtime Settings

Use the Node.js custom runtime/start command that runs:

```bash
node index.mjs
```

The process listens on `FC_SERVER_PORT`, `CA_PORT`, `PORT`, or `9000` in that order. Set the Function Compute timeout to `300` seconds; report generation can legitimately take longer than a normal API request, and the iOS client waits up to five minutes. Keep `DASHSCOPE_TIMEOUT_MS` below the FC timeout, for example `240000`, so the function can return a clear JSON timeout error instead of being killed by the platform. `DASHSCOPE_SAFE_TIMEOUT_MS` caps the effective model timeout even if the console environment still contains a larger value.

After deploying, open:

```text
https://<your-fc-trigger>/health
```

The health response intentionally exposes only safe configuration metadata: model, API mode, timeout limits, and Apple environment. It does not expose secrets, request bodies, student profiles, or generated report text.

For temporary connectivity debugging, set `ENABLE_DASHSCOPE_DIAGNOSTICS=true` and open `/diagnostics/dashscope`. It bypasses Apple verification and sends one tiny DashScope request, so disable it immediately after confirming whether Function Compute can reach DashScope.

This is the no-table lightweight version. It does not include TableStore, Redis, or a transaction ledger dependency. The tradeoff is that the backend no longer has a server-side duplicate-consumption ledger; the normal iOS flow still clears the pending transaction after success, but a copied valid transaction JWS could be replayed to request another report. Keep Apple verification enabled for real TestFlight and production use.

## Deploy Outline

1. Create or use an Alibaba Cloud account with real-name verification.
2. Open Model Studio (百炼) and enable a Qwen model such as `qwen-plus`.
3. Create a DashScope API key.
4. Create an Aliyun Function Compute Node.js function with an HTTP trigger.
5. Upload this folder as the function code and run `npm install` during build/deploy.
6. Configure the required environment variables above.
7. Restrict logs so request bodies are not printed.
8. Set the iOS app `REPORT_PROXY_URL` build setting to the HTTPS trigger URL before archiving for TestFlight or App Store release. The app writes that value into the generated `ReportProxyURL` Info.plist key. Debug builds may still use the process environment variable.
9. Test with `APPLE_ENVIRONMENT=Sandbox` and App Store Connect sandbox purchases.
10. Switch to `APPLE_ENVIRONMENT=Production` only after the in-app purchase product and app are live.

## Privacy Contract

Long-term backend storage:

- LLM API key and Apple verification config

Not stored:

- Transaction ledger rows
- Student profile
- High-school name or context
- Grades and test scores
- Selected-school list
- Prompt/fact packet
- Generated AI report text

If a report generation succeeds but the client loses the network response, the backend has no report copy or transaction ledger to replay from. The current privacy-first design leaves the pending transaction token on the device for retry before success; for edge cases after a successful backend response loss, handle through customer support or a compensating purchase.
