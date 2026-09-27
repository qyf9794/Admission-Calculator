import crypto from "node:crypto";
import { neon } from "@neondatabase/serverless";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus
} from "@apple/app-store-server-library";
import { appleRootCertificates } from "../lib/apple-roots.mjs";

const config = {
  productId: configuredEnv("REPORT_PRODUCT_ID", "admission_calculator_ai_report"),
  bundleId: configuredEnv("APPLE_BUNDLE_ID"),
  appAppleId: optionalIntegerEnv("APPLE_APPLE_ID"),
  transactionSecret: configuredEnv("TRANSACTION_HMAC_SECRET"),
  databaseUrl: configuredEnv("DATABASE_URL"),
  openAIKey: configuredEnv("OPENAI_API_KEY"),
  openAIBaseUrl: (process.env.OPENAI_BASE_URL || "https://api.openai.com/v1").replace(/\/+$/, ""),
  openAIModel: process.env.OPENAI_MODEL?.trim() || "gpt-6-luna",
  openAIReasoningEffort: process.env.OPENAI_REASONING_EFFORT?.trim().toLowerCase() || "medium",
  openAITimeoutMs: Number(process.env.OPENAI_TIMEOUT_MS || 180_000),
  pendingTimeoutMs: Number(process.env.PENDING_TIMEOUT_MS || 10 * 60 * 1000),
  skipAppleVerification: process.env.SKIP_APPLE_VERIFY_FOR_LOCAL_DEV === "true"
};

let ledgerSchemaPromise;
const ledgerClient = config.databaseUrl ? neon(config.databaseUrl) : undefined;

export default async function reportProxy(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    response.statusCode = 405;
    response.setHeader("Content-Type", "application/json; charset=utf-8");
    response.end(JSON.stringify({ error: "method_not_allowed" }));
    return;
  }

  let body;
  try {
    body = await readRequestBody(request);
  } catch (error) {
    const status = error.httpStatus || 400;
    response.statusCode = status;
    response.setHeader("Content-Type", "application/json; charset=utf-8");
    response.end(JSON.stringify({
      error: error.code || "invalid_request_body",
      message: error.publicMessage || "请求内容无法读取。"
    }));
    return;
  }

  const result = await processReport({ httpMethod: request.method, body });
  response.statusCode = result.statusCode;
  for (const [name, value] of Object.entries(result.headers || {})) {
    response.setHeader(name, value);
  }
  response.end(result.body);
}

async function processReport(event) {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();

  try {
    if (event.httpMethod && event.httpMethod !== "POST") {
      return jsonResponse(405, { error: "method_not_allowed", requestId });
    }

    const body = parseJSONBody(event.body);
    validateBody(body);
    if (!ledgerClient) {
      throw publicError(503, "transaction_ledger_not_configured", "服务端交易账本尚未配置。");
    }
    if (!hasRequiredReportConfiguration()) {
      throw publicError(503, "report_service_not_configured", "服务端报告服务尚未完成配置。");
    }
    await ensureTransactionLedger(ledgerClient);

    const transaction = await verifyAppleTransaction(body.transaction, requestId);
    const transactionHash = hmac(transaction.transactionId);
    const originalTransactionHash = hmac(transaction.originalTransactionId || transaction.transactionId);

    const claim = await claimTransaction(ledgerClient, {
      transactionHash,
      originalTransactionHash,
      productId: transaction.productId,
      requestId
    });
    if (claim === "used") {
      return jsonResponse(409, { error: "transaction_already_used", requestId });
    }
    if (claim === "pending") {
      return jsonResponse(409, { error: "transaction_pending", requestId });
    }

    let reportText;
    try {
      reportText = await generateReport({
        instructions: body.instructions,
        input: body.input,
        requestId
      });
    } catch (error) {
      await updateTransaction(ledgerClient, transactionHash, requestId, {
        status: "failed",
        failure_code: error.code || "llm_request_failed",
        updated_at: Date.now()
      });
      throw error;
    }

    await updateTransaction(ledgerClient, transactionHash, requestId, {
      status: "used",
      provider: "openai",
      model: config.openAIModel,
      updated_at: Date.now()
    });

    return jsonResponse(200, {
      reportText,
      requestId,
      model: config.openAIModel,
      elapsedMs: Date.now() - startedAt
    });
  } catch (error) {
    const status = error.httpStatus || 500;
    const code = error.code || "report_proxy_error";
    console.error("report-proxy-error", {
      requestId,
      code,
      message: error.message
    });
    return jsonResponse(status, {
      error: code,
      message: error.publicMessage || "报告生成失败，请稍后重试。",
      requestId
    });
  }
}

async function verifyAppleTransaction(transaction, requestId) {
  if (config.skipAppleVerification) {
    return {
      transactionId: transaction.transactionID || transaction.transactionId,
      originalTransactionId: transaction.originalTransactionID || transaction.originalTransactionId,
      productId: transaction.productID || transaction.productId
    };
  }

  let rootCertificates;
  try {
    rootCertificates = appleRootCertificates();
  } catch {
    throw publicError(503, "invalid_apple_roots", "服务端 Apple 根证书配置无效，请稍后重试。");
  }
  const transactionEnvironment = signedTransactionEnvironment(transaction.signedTransactionInfo);
  // The unverified claim selects the verifier only; Apple signature verification below validates it.
  const verifier = new SignedDataVerifier(
    rootCertificates,
    true,
    transactionEnvironment,
    config.bundleId,
    config.appAppleId
  );
  let decoded;
  try {
    decoded = await verifier.verifyAndDecodeTransaction(transaction.signedTransactionInfo);
  } catch (error) {
    const verificationError = error instanceof VerificationException ? error : undefined;
    const cause = verificationError?.cause;
    console.error("apple-transaction-verification-failed", {
      requestId,
      environment: transactionEnvironment,
      status: verificationError ? VerificationStatus[verificationError.status] : undefined,
      statusCode: verificationError?.status,
      causeName: cause instanceof Error ? cause.name : undefined,
      causeCode: cause?.code,
      causeMessage: cause instanceof Error ? cause.message.slice(0, 200) : undefined,
      certificateChain: appleCertificateChainDiagnostics(
        transaction.signedTransactionInfo,
        rootCertificates
      )
    });
    throw publicError(400, "invalid_transaction_signature", "Apple 交易签名验证失败。");
  }
  if (decoded.environment !== transactionEnvironment) {
    throw publicError(400, "invalid_transaction_environment", "Apple 交易环境验证失败。");
  }
  const productId = decoded.productId || decoded.productID;
  const bundleId = decoded.bundleId || decoded.bundleID;
  const transactionId = String(decoded.transactionId || decoded.transactionID || "");
  const originalTransactionId = String(decoded.originalTransactionId || decoded.originalTransactionID || transactionId);

  if (!transactionId) {
    throw publicError(400, "invalid_transaction", "Apple 交易缺少 transactionId。");
  }
  if (productId !== config.productId) {
    throw publicError(400, "product_mismatch", "Apple 交易商品与报告商品不匹配。");
  }
  if (bundleId !== config.bundleId) {
    throw publicError(400, "bundle_mismatch", "Apple 交易 Bundle ID 不匹配。");
  }
  return {
    transactionId,
    originalTransactionId,
    productId
  };
}

async function generateReport({ instructions, input, requestId }) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.openAITimeoutMs);
  try {
    const response = await fetch(`${config.openAIBaseUrl}/responses`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.openAIKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: config.openAIModel,
        reasoning: { effort: config.openAIReasoningEffort },
        instructions,
        input,
        store: false
      }),
      signal: controller.signal
    });
    if (!response.ok) {
      throw publicError(502, "llm_request_failed", `OpenAI 模型服务调用失败：${response.status}`, {
        providerStatus: response.status,
        providerRequestId: response.headers.get("x-request-id") || requestId
      });
    }

    let data;
    try {
      data = await response.json();
    } catch {
      throw publicError(502, "llm_invalid_json", "OpenAI 模型服务返回格式无法解析。");
    }
    if (data?.status !== "completed") {
      throw publicError(502, "llm_incomplete_response", "OpenAI 模型服务未能完成报告生成。");
    }
    const content = responseOutputText(data);
    if (!content) {
      throw publicError(502, "llm_empty_response", "OpenAI 模型服务没有返回报告正文。");
    }
    return content;
  } catch (error) {
    if (error.httpStatus) {
      throw error;
    }
    const timeoutError = error?.name === "AbortError";
    throw publicError(
      502,
      timeoutError ? "llm_request_timed_out" : "llm_request_failed",
      timeoutError ? "模型服务请求超时，请稍后重试。" : "模型服务暂时不可用，请稍后重试。",
      { providerRequestId: requestId }
    );
  } finally {
    clearTimeout(timeout);
  }
}

function responseOutputText(response) {
  if (typeof response?.output_text === "string") {
    return response.output_text.trim();
  }
  const parts = [];
  for (const item of response?.output || []) {
    if (item?.type !== "message" || item?.role !== "assistant") {
      continue;
    }
    for (const content of item.content || []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        parts.push(content.text);
      }
    }
  }
  return parts.join("\n").trim();
}

async function ensureTransactionLedger(sql) {
  if (!ledgerSchemaPromise) {
    ledgerSchemaPromise = sql`
      CREATE TABLE IF NOT EXISTS admission_report_transactions (
        transaction_hash TEXT PRIMARY KEY,
        original_transaction_hash TEXT NOT NULL,
        product_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('pending', 'failed', 'used')),
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        request_id TEXT NOT NULL,
        failure_code TEXT,
        created_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL
      )
    `.catch((error) => {
      ledgerSchemaPromise = undefined;
      throw error;
    });
  }
  await ledgerSchemaPromise;
}

async function claimTransaction(sql, row) {
  const now = Date.now();
  const claimed = await sql`
    INSERT INTO admission_report_transactions (
      transaction_hash,
      original_transaction_hash,
      product_id,
      status,
      provider,
      model,
      request_id,
      created_at,
      updated_at
    ) VALUES (
      ${row.transactionHash},
      ${row.originalTransactionHash},
      ${row.productId},
      'pending',
      'openai',
      ${config.openAIModel},
      ${row.requestId},
      ${now},
      ${now}
    )
    ON CONFLICT (transaction_hash) DO UPDATE SET
      original_transaction_hash = EXCLUDED.original_transaction_hash,
      product_id = EXCLUDED.product_id,
      status = 'pending',
      provider = 'openai',
      model = EXCLUDED.model,
      request_id = EXCLUDED.request_id,
      failure_code = NULL,
      updated_at = EXCLUDED.updated_at
    WHERE admission_report_transactions.status = 'failed'
      OR (
        admission_report_transactions.status = 'pending'
        AND admission_report_transactions.updated_at < ${now - config.pendingTimeoutMs}
      )
    RETURNING transaction_hash
  `;
  if (claimed.length) {
    return "claimed";
  }

  const existing = await getTransaction(sql, row.transactionHash);
  if (existing?.status === "used") {
    return "used";
  }
  if (existing?.status === "pending") {
    return "pending";
  }
  throw publicError(503, "transaction_ledger_conflict", "交易账本状态冲突，请稍后重试。");
}

async function getTransaction(sql, transactionHash) {
  const rows = await sql`
    SELECT status, updated_at
    FROM admission_report_transactions
    WHERE transaction_hash = ${transactionHash}
    LIMIT 1
  `;
  return rows[0];
}

async function updateTransaction(sql, transactionHash, requestId, attributes) {
  const rows = await sql`
    UPDATE admission_report_transactions
    SET status = ${attributes.status},
        provider = ${attributes.provider || "openai"},
        model = ${attributes.model || config.openAIModel},
        failure_code = ${attributes.failure_code || null},
        updated_at = ${attributes.updated_at || Date.now()}
    WHERE transaction_hash = ${transactionHash}
      AND request_id = ${requestId}
      AND status = 'pending'
    RETURNING transaction_hash
  `;
  if (!rows.length) {
    throw publicError(503, "transaction_ledger_conflict", "交易账本状态更新失败，请稍后重试。");
  }
}

function parseJSONBody(body) {
  try {
    const value = Buffer.isBuffer(body) ? body.toString("utf8") : body;
    return typeof value === "string" ? JSON.parse(value || "{}") : value;
  } catch {
    throw publicError(400, "invalid_json", "请求 JSON 无法解析。");
  }
}

async function readRequestBody(request) {
  if (request.body !== undefined) {
    return request.body;
  }

  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > 1_000_000) {
      throw publicError(413, "request_body_too_large", "报告请求内容过大。");
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function validateBody(body) {
  if (!body?.input || typeof body.input !== "string") {
    throw publicError(400, "missing_input", "缺少报告事实包。");
  }
  if (!body?.instructions || typeof body.instructions !== "string") {
    throw publicError(400, "missing_instructions", "缺少报告生成指令。");
  }
  if (!body?.transaction?.signedTransactionInfo || typeof body.transaction.signedTransactionInfo !== "string") {
    throw publicError(400, "missing_transaction", "缺少 Apple 交易凭证。");
  }
}

function hmac(value) {
  return crypto
    .createHmac("sha256", config.transactionSecret)
    .update(String(value))
    .digest("hex");
}

function appleCertificateChainDiagnostics(signedTransactionInfo, trustedRootBuffers) {
  try {
    const [encodedHeader] = signedTransactionInfo.split(".");
    const header = JSON.parse(Buffer.from(encodedHeader, "base64url").toString("utf8"));
    const chain = Array.isArray(header?.x5c) ? header.x5c : [];
    if (chain.length < 2) {
      return { presentedCertificateCount: chain.length };
    }

    const leaf = new crypto.X509Certificate(Buffer.from(chain[0], "base64"));
    const intermediate = new crypto.X509Certificate(Buffer.from(chain[1], "base64"));
    const trustedRoots = trustedRootBuffers.map((root) => new crypto.X509Certificate(root));
    const intermediateIssuerMatchesRoot = trustedRoots.filter((root) => intermediate.issuer === root.subject);

    return {
      presentedCertificateCount: chain.length,
      trustedRootCount: trustedRoots.length,
      leafIssuerMatchesIntermediate: leaf.issuer === intermediate.subject,
      leafSignatureValid: leaf.verify(intermediate.publicKey),
      intermediateIsCA: intermediate.ca,
      intermediateIssuerMatchesTrustedRoot: intermediateIssuerMatchesRoot.length > 0,
      intermediateSignatureValidForTrustedRoot: intermediateIssuerMatchesRoot.some((root) => intermediate.verify(root.publicKey)),
      leafHasAppleSigningOID: certificateHasObjectIdentifier(leaf, "1.2.840.113635.100.6.11.1"),
      intermediateHasAppleIntermediateOID: certificateHasObjectIdentifier(intermediate, "1.2.840.113635.100.6.2.1")
    };
  } catch (error) {
    return { diagnosticErrorName: error instanceof Error ? error.name : "UnknownError" };
  }
}

function certificateHasObjectIdentifier(certificate, oid) {
  const arcs = oid.split(".").map(Number);
  const encodedArcs = [arcs[0] * 40 + arcs[1], ...arcs.slice(2)];
  const encodedBody = Buffer.concat(encodedArcs.map(encodeObjectIdentifierArc));
  const encodedIdentifier = Buffer.concat([Buffer.from([0x06, encodedBody.length]), encodedBody]);
  return certificate.raw.includes(encodedIdentifier);
}

function encodeObjectIdentifierArc(value) {
  const bytes = [value & 0x7f];
  for (value = Math.floor(value / 128); value > 0; value = Math.floor(value / 128)) {
    bytes.unshift(0x80 | (value & 0x7f));
  }
  return Buffer.from(bytes);
}

function signedTransactionEnvironment(signedTransactionInfo) {
  const segments = typeof signedTransactionInfo === "string" ? signedTransactionInfo.split(".") : [];
  if (segments.length !== 3 || !segments[1]) {
    throw publicError(400, "invalid_transaction", "Apple 交易凭证格式无效。");
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(segments[1], "base64url").toString("utf8"));
  } catch {
    throw publicError(400, "invalid_transaction", "Apple 交易凭证格式无效。");
  }

  const environment = payload?.environment;
  if (environment !== Environment.PRODUCTION && environment !== Environment.SANDBOX) {
    throw publicError(400, "invalid_transaction_environment", "Apple 交易环境无效。");
  }
  return environment;
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(body)
  };
}

function publicError(httpStatus, code, publicMessage, extra = {}) {
  const error = new Error(publicMessage);
  error.httpStatus = httpStatus;
  error.code = code;
  error.publicMessage = publicMessage;
  Object.assign(error, extra);
  return error;
}

function configuredEnv(name, fallback) {
  return process.env[name]?.trim() || fallback;
}

function optionalIntegerEnv(name) {
  const value = process.env[name];
  if (!value) {
    return undefined;
  }
  return Number(value);
}

function hasRequiredReportConfiguration() {
  const hasProductionAppId = Number.isInteger(config.appAppleId) && config.appAppleId > 0;
  return Boolean(
    config.bundleId &&
    config.transactionSecret &&
    config.openAIKey &&
    (process.env.APPLE_ROOT_CERTIFICATES_BASE64?.trim() || process.env.APPLE_ROOT_CERTIFICATES_PEM?.trim()) &&
    hasProductionAppId
  );
}
