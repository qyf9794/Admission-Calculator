# Aliyun Report Proxy

This is the lightweight backend for paid AI reports:

- iOS buys one report through StoreKit 2.
- iOS sends the StoreKit transaction JWS plus the local report fact packet.
- This function verifies the Apple transaction, stores only a HMAC transaction ledger row, calls Alibaba Cloud Model Studio/Qwen, and returns report text.
- It does not store the student profile, high-school info, grades, selected schools, prompt body, or generated report text.
- If the model call fails after Apple has charged the user, the transaction row is marked `failed`; the same signed transaction can be submitted again so the user can retry without paying again.

## Required Environment Variables

```bash
REPORT_PRODUCT_ID=admission_calculator_ai_report
APPLE_BUNDLE_ID=com.qyf9794.AdmissionCalculator
APPLE_APPLE_ID=<numeric app Apple ID for production>
APPLE_ENVIRONMENT=Sandbox # use Production after App Store release
APPLE_ROOT_CERTIFICATES_PEM='<Apple root certificate PEM text>'
TRANSACTION_HMAC_SECRET=<long random secret>
DASHSCOPE_API_KEY=<Aliyun Model Studio API key>
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
DASHSCOPE_MODEL=qwen-plus
OTS_ENDPOINT=https://<instance>.<region>.ots.aliyuncs.com
OTS_INSTANCE_NAME=<tablestore instance>
OTS_TABLE_NAME=admission_report_transactions
```

For local connectivity tests only:

```bash
SKIP_APPLE_VERIFY_FOR_LOCAL_DEV=true
LOCAL_DEV_SERVER=true
PORT=8787
```

Never enable `SKIP_APPLE_VERIFY_FOR_LOCAL_DEV` in production.

## TableStore Schema

Create a table named `admission_report_transactions`:

```text
Primary key:
transaction_hash string

Columns:
original_transaction_hash string
product_id string
status string              # pending / used / failed / expired
provider string            # dashscope
model string
request_id string
created_at integer         # epoch milliseconds
updated_at integer         # epoch milliseconds
failure_code string        # optional
```

Only `transaction_hash` and `original_transaction_hash` are retained, both generated with `HMAC_SHA256(transactionId, TRANSACTION_HMAC_SECRET)`.

## Deploy Outline

1. Create or use an Alibaba Cloud account with real-name verification.
2. Open Model Studio (百炼) and enable a Qwen model such as `qwen-plus`.
3. Create a DashScope API key.
4. Create a TableStore instance and the transaction table above.
5. Create an Aliyun Function Compute Node.js function with an HTTP trigger.
6. Upload this folder as the function code and run `npm install` during build/deploy.
7. Configure the environment variables above.
8. Restrict logs so request bodies are not printed.
9. Set the iOS app `ReportProxyURL` Info.plist value or Debug `REPORT_PROXY_URL` to the HTTPS trigger URL.
10. Test with `APPLE_ENVIRONMENT=Sandbox` and App Store Connect sandbox purchases.
11. Switch to `APPLE_ENVIRONMENT=Production` only after the in-app purchase product and app are live.

## Privacy Contract

Long-term backend storage:

- LLM API key and Apple verification config
- Transaction HMACs
- Status, model, provider, request ID, timestamps

Not stored:

- Student profile
- High-school name or context
- Grades and test scores
- Selected-school list
- Prompt/fact packet
- Generated AI report text

If a report generation succeeds but the client loses the network response, the backend has no report copy to replay. The current privacy-first design leaves the pending transaction token on the device for retry until the backend marks the transaction as `used`; for edge cases after a successful backend response loss, handle through customer support or a compensating purchase.
