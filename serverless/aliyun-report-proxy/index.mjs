import crypto from "node:crypto";
import http from "node:http";
import {
  Environment,
  SignedDataVerifier
} from "@apple/app-store-server-library";

const dashscopeModel = normalizeDashScopeModel(process.env.DASHSCOPE_MODEL);
const dashscopeApiMode = dashscopeModeForModel(dashscopeModel);

const config = {
  productId: requiredEnv("REPORT_PRODUCT_ID", "admission_calculator_ai_report"),
  bundleId: requiredEnv("APPLE_BUNDLE_ID"),
  appAppleId: optionalIntegerEnv("APPLE_APPLE_ID"),
  appleEnvironment: appleEnvironment(),
  dashscopeApiKey: requiredEnv("DASHSCOPE_API_KEY"),
  dashscopeBaseUrl: dashscopeBaseUrl(dashscopeApiMode),
  dashscopeApiMode,
  dashscopeModel,
  dashscopeTimeoutMs: safeDashScopeTimeoutMs(),
  dashscopeMaxTokens: Number(process.env.DASHSCOPE_MAX_TOKENS || 3500),
  dashscopeMaxRetries: Number(process.env.DASHSCOPE_MAX_RETRIES || 0),
  dashscopeRetryBaseDelayMs: Number(process.env.DASHSCOPE_RETRY_BASE_DELAY_MS || 800),
  maxInstructionCharacters: Number(process.env.MAX_INSTRUCTION_CHARACTERS || 2500),
  maxInputCharacters: Number(process.env.MAX_INPUT_CHARACTERS || 20_000),
  maxReportCharacters: Number(process.env.MAX_REPORT_CHARACTERS || 10_000),
  skipAppleVerification: process.env.SKIP_APPLE_VERIFY_FOR_LOCAL_DEV === "true"
};

export async function handler(event) {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();

  try {
    const request = parseHTTPEvent(event);
    if ((request.method === "GET" || request.method === "HEAD") && request.path === "/health") {
      return jsonResponse(200, healthPayload());
    }
    if (request.method === "GET" && request.path === "/diagnostics/dashscope") {
      return diagnoseDashScope(requestId);
    }
    if (request.method && request.method !== "POST") {
      return jsonResponse(405, { error: "method_not_allowed", requestId });
    }

    const body = parseJSONBody(request.body);
    validateBody(body);

    await verifyAppleTransaction(body.transaction);
    const reportText = await generateReport({
      instructions: body.instructions,
      input: body.input,
      requestId
    });

    return jsonResponse(200, {
      reportText,
      requestId,
      model: config.dashscopeModel,
      elapsedMs: Date.now() - startedAt
    });
  } catch (error) {
    const status = error.httpStatus || 500;
    const code = error.code || "report_proxy_error";
    console.error("report-proxy-error", {
      requestId,
      code,
      message: error.message,
      cause: error.cause?.message
    });
    return jsonResponse(status, {
      error: code,
      message: error.publicMessage || "报告生成失败，请稍后重试。",
      requestId
    });
  }
}

async function verifyAppleTransaction(transaction) {
  if (config.skipAppleVerification) {
    return {
      transactionId: transaction.transactionID || transaction.transactionId,
      originalTransactionId: transaction.originalTransactionID || transaction.originalTransactionId,
      productId: transaction.productID || transaction.productId
    };
  }

  const rootCertificates = appleRootCertificates();
  const verifier = new SignedDataVerifier(
    rootCertificates,
    true,
    config.appleEnvironment,
    config.bundleId,
    config.appAppleId
  );
  const decoded = await verifier.verifyAndDecodeTransaction(transaction.signedTransactionInfo);
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
  const boundedInstructions = limitText(instructions, config.maxInstructionCharacters);
  const boundedInput = limitText(input, config.maxInputCharacters);
  const payload = dashscopePayload({
    instructions: boundedInstructions,
    input: boundedInput
  });
  const { text, elapsedMs, providerRequestId } = await requestDashScopeWithRetries({
    payload,
    requestId,
    instructionCharacters: boundedInstructions.length,
    inputCharacters: boundedInput.length
  });

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    console.error("dashscope-invalid-json", {
      requestId,
      providerRequestId,
      elapsedMs,
      preview: text.slice(0, 500)
    });
    throw publicError(502, "llm_invalid_json", "模型服务返回格式无法解析。");
  }
  const content = dashscopeContent(data);
  if (!content) {
    console.error("dashscope-empty-response", {
      requestId,
      providerRequestId,
      elapsedMs,
      finishReason: dashscopeFinishReason(data),
      preview: text.slice(0, 500)
    });
    throw publicError(502, "llm_empty_response", "模型服务没有返回报告正文。");
  }
  const boundedContent = limitText(content, config.maxReportCharacters);
  console.log("dashscope-success", {
    requestId,
    providerRequestId,
    elapsedMs,
    outputCharacters: boundedContent.length,
    truncated: boundedContent.length !== content.length,
    finishReason: dashscopeFinishReason(data)
  });
  return boundedContent;
}

async function requestDashScopeWithRetries({ payload, requestId, instructionCharacters, inputCharacters }) {
  let lastError;
  const maxAttempts = Math.max(1, config.dashscopeMaxRetries + 1);
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const startedAt = Date.now();
    const controller = new AbortController();
    let timer;
    try {
      console.log("dashscope-request", {
        requestId,
        attempt,
        model: config.dashscopeModel,
        apiMode: config.dashscopeApiMode,
        instructionCharacters,
        inputCharacters,
        maxTokens: config.dashscopeMaxTokens
      });
      const { response, text, providerRequestId } = await withHardTimeout((async () => {
        const response = await fetch(config.dashscopeBaseUrl, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${config.dashscopeApiKey}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(payload),
          signal: controller.signal
        });
        const text = await response.text();
        return {
          response,
          text,
          providerRequestId: providerRequestIdFrom(response)
        };
      })(), {
        timeoutMs: config.dashscopeTimeoutMs,
        onTimeout: () => controller.abort(),
        setTimer: (value) => {
          timer = value;
        }
      });
      const elapsedMs = Date.now() - startedAt;
      if (response.ok) {
        return { text, elapsedMs, providerRequestId };
      }

      const providerMessage = providerErrorMessage(text);
      console.error("dashscope-error", {
        requestId,
        attempt,
        status: response.status,
        providerRequestId,
        elapsedMs,
        providerMessage
      });
      lastError = publicError(
        response.status === 429 ? 429 : 502,
        "llm_request_failed",
        `模型服务调用失败：HTTP ${response.status}${providerMessage ? `，${providerMessage}` : ""}`,
        {
          providerStatus: response.status,
          providerRequestId
        }
      );

      if (!isRetryableProviderStatus(response.status) || attempt >= maxAttempts) {
        throw lastError;
      }
    } catch (error) {
      const elapsedMs = Date.now() - startedAt;
      if (error?.name === "AbortError") {
        lastError = publicError(504, "llm_request_timeout", `模型服务调用超过 ${config.dashscopeTimeoutMs}ms。`);
      } else if (error?.httpStatus) {
        lastError = error;
      } else {
        const message = error?.message || error?.name || "unknown network error";
        console.error("dashscope-network-error", {
          requestId,
          attempt,
          elapsedMs,
          name: error?.name,
          message
        });
        lastError = publicError(502, "llm_network_failed", `模型服务网络请求失败：${message}`, {
          cause: error
        });
      }

      if (attempt >= maxAttempts || !isRetryableProxyError(lastError)) {
        throw lastError;
      }
    } finally {
      clearTimeout(timer);
    }
    await sleep(config.dashscopeRetryBaseDelayMs * attempt);
  }
  throw lastError || publicError(502, "llm_request_failed", "模型服务调用失败。");
}

function dashscopePayload({ instructions, input }) {
  if (config.dashscopeApiMode === "multimodal") {
    return {
      model: config.dashscopeModel,
      input: {
        messages: [
          { role: "system", content: [{ text: instructions }] },
          { role: "user", content: [{ text: input }] }
        ]
      },
      parameters: {
        result_format: "message",
        temperature: 0.3,
        max_tokens: config.dashscopeMaxTokens,
        enable_thinking: false,
        thinking_budget: 0
      }
    };
  }
  return {
    model: config.dashscopeModel,
    messages: [
      { role: "system", content: instructions },
      { role: "user", content: input }
    ],
    temperature: 0.3,
    max_tokens: config.dashscopeMaxTokens
  };
}

function dashscopeContent(data) {
  if (config.dashscopeApiMode === "multimodal") {
    return textFromMessageContent(data?.output?.choices?.[0]?.message?.content)
      || textFromMessageContent(data?.output?.choices?.[0]?.message?.content?.[0])
      || textFromMessageContent(data?.output?.text);
  }
  return textFromMessageContent(data?.choices?.[0]?.message?.content);
}

function textFromMessageContent(content) {
  if (Array.isArray(content)) {
    return content.map(textFromMessageContent).join("").trim();
  }
  if (typeof content === "string") {
    return content.trim();
  }
  if (content && typeof content === "object") {
    return textFromMessageContent(content.text || content.content || content.output_text || "");
  }
  return "";
}

function dashscopeFinishReason(data) {
  if (config.dashscopeApiMode === "multimodal") {
    return data?.output?.choices?.[0]?.finish_reason || data?.output?.finish_reason;
  }
  return data?.choices?.[0]?.finish_reason;
}

function limitText(value, maxCharacters) {
  const text = String(value || "");
  if (!Number.isFinite(maxCharacters) || maxCharacters <= 0 || text.length <= maxCharacters) {
    return text;
  }
  return `${text.slice(0, maxCharacters)}\n\n[内容已截断以控制报告生成时间]`;
}

function healthPayload() {
  return {
    ok: true,
    service: "admission-report-proxy",
    model: config.dashscopeModel,
    apiMode: config.dashscopeApiMode,
    dashscopeTimeoutMs: config.dashscopeTimeoutMs,
    dashscopeMaxTokens: config.dashscopeMaxTokens,
    dashscopeMaxRetries: config.dashscopeMaxRetries,
    maxInstructionCharacters: config.maxInstructionCharacters,
    maxInputCharacters: config.maxInputCharacters,
    maxReportCharacters: config.maxReportCharacters,
    transactionLedgerEnabled: false,
    tableStoreConfigured: false,
    appleEnvironment: process.env.APPLE_ENVIRONMENT || "Production",
    skipAppleVerification: config.skipAppleVerification
  };
}

async function diagnoseDashScope(requestId) {
  if (process.env.ENABLE_DASHSCOPE_DIAGNOSTICS !== "true") {
    return jsonResponse(404, { error: "diagnostics_disabled", requestId });
  }

  const startedAt = Date.now();
  const timeoutMs = Number(process.env.DASHSCOPE_DIAGNOSTIC_TIMEOUT_MS || 20_000);
  const controller = new AbortController();
  let timer;
  try {
    const payload = dashscopePayload({
      instructions: "你是连通性诊断助手。只输出 dashscope-ok。",
      input: "请只回复 dashscope-ok"
    });
    const { response, text, providerRequestId } = await withHardTimeout((async () => {
      const response = await fetch(config.dashscopeBaseUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${config.dashscopeApiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload),
        signal: controller.signal
      });
      const text = await response.text();
      return {
        response,
        text,
        providerRequestId: providerRequestIdFrom(response)
      };
    })(), {
      timeoutMs,
      onTimeout: () => controller.abort(),
      setTimer: (value) => {
        timer = value;
      }
    });

    let output = "";
    try {
      output = dashscopeContent(JSON.parse(text));
    } catch {}

    return jsonResponse(response.ok ? 200 : 502, {
      ok: response.ok,
      requestId,
      providerRequestId,
      status: response.status,
      elapsedMs: Date.now() - startedAt,
      model: config.dashscopeModel,
      apiMode: config.dashscopeApiMode,
      outputPreview: output.slice(0, 80),
      providerError: response.ok ? undefined : providerErrorMessage(text)
    });
  } catch (error) {
    return jsonResponse(error.httpStatus || 502, {
      ok: false,
      requestId,
      error: error.code || "dashscope_diagnostic_failed",
      message: error.publicMessage || error.message,
      elapsedMs: Date.now() - startedAt
    });
  } finally {
    clearTimeout(timer);
  }
}

function providerRequestIdFrom(response) {
  return response.headers.get("x-request-id")
    || response.headers.get("x-acs-request-id")
    || response.headers.get("request-id")
    || undefined;
}

function providerErrorMessage(text) {
  if (!text) {
    return undefined;
  }
  try {
    const data = JSON.parse(text);
    const code = data.code || data.error?.code || data.output?.code;
    const message = data.message || data.error?.message || data.output?.message;
    return [code, message].filter(Boolean).join(": ").slice(0, 500);
  } catch {
    return text.slice(0, 500);
  }
}

function isRetryableProviderStatus(status) {
  return status === 408 || status === 429 || status >= 500;
}

function isRetryableProxyError(error) {
  return ["llm_network_failed", "llm_request_failed"].includes(error?.code)
    && error?.httpStatus !== 400
    && error?.httpStatus !== 401
    && error?.httpStatus !== 403;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withHardTimeout(promise, { timeoutMs, onTimeout, setTimer }) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      try {
        onTimeout?.();
      } catch {}
      reject(publicError(504, "llm_request_timeout", `模型服务调用超过 ${timeoutMs}ms。`));
    }, timeoutMs);
    setTimer?.(timer);

    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      }
    );
  });
}

function parseHTTPEvent(event) {
  if (event && typeof event === "object" && "body" in event) {
    return {
      method: event.httpMethod || event.requestContext?.http?.method,
      path: event.path || event.rawPath || event.requestContext?.http?.path || "/",
      body: event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : event.body
    };
  }
  if (Buffer.isBuffer(event)) {
    return { path: "/", body: event.toString("utf8") };
  }
  if (typeof event === "string") {
    return { path: "/", body: event };
  }
  return { path: "/", body: JSON.stringify(event || {}) };
}

function parseJSONBody(body) {
  try {
    return typeof body === "string" ? JSON.parse(body || "{}") : body;
  } catch {
    throw publicError(400, "invalid_json", "请求 JSON 无法解析。");
  }
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

function appleRootCertificates() {
  const encoded = process.env.APPLE_ROOT_CERTIFICATES_PEM || "";
  const certificates = encoded
    .split("-----END CERTIFICATE-----")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => Buffer.from(`${part}\n-----END CERTIFICATE-----`));
  if (!certificates.length) {
    throw publicError(500, "missing_apple_roots", "服务端未配置 Apple 根证书。");
  }
  return certificates;
}

function appleEnvironment() {
  const value = (process.env.APPLE_ENVIRONMENT || "Production").toLowerCase();
  return value === "sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
}

function normalizeDashScopeModel(value) {
  if (!value) {
    return "qwen-plus";
  }
  return String(value).trim().toLowerCase().replace(/\s+/g, "");
}

function dashscopeModeForModel(model) {
  if ((process.env.DASHSCOPE_API_MODE || "").toLowerCase() === "openai") {
    return "openai";
  }
  if ((process.env.DASHSCOPE_API_MODE || "").toLowerCase() === "multimodal") {
    return "multimodal";
  }
  return model.startsWith("qwen3.7") ? "multimodal" : "openai";
}

function dashscopeBaseUrl(mode) {
  const override = process.env.DASHSCOPE_BASE_URL;
  if (mode === "multimodal") {
    if (override && !override.includes("/compatible-mode/")) {
      return override;
    }
    return "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation";
  }
  if (override?.endsWith("/chat/completions")) {
    return override;
  }
  return override
    ? `${override.replace(/\/$/, "")}/chat/completions`
    : "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
}

function safeDashScopeTimeoutMs() {
  const configured = Number(process.env.DASHSCOPE_TIMEOUT_MS || 240_000);
  const safeMaximum = Number(process.env.DASHSCOPE_SAFE_TIMEOUT_MS || 240_000);
  if (!Number.isFinite(configured) || configured <= 0) {
    return safeMaximum;
  }
  return Math.min(configured, safeMaximum);
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store"
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

function requiredEnv(name, fallback) {
  const value = process.env[name] || fallback;
  if (!value) {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
}

function optionalIntegerEnv(name) {
  const value = process.env[name];
  if (!value) {
    return undefined;
  }
  return Number(value);
}

function startHTTPServer({ host, port }) {
  const server = http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }
    const result = await handler({
      httpMethod: request.method,
      path: new URL(request.url || "/", `http://${request.headers.host || host}`).pathname,
      body: Buffer.concat(chunks).toString("utf8")
    });
    response.writeHead(result.statusCode, result.headers);
    response.end(result.body);
  });
  server.timeout = 0;
  server.keepAliveTimeout = 0;
  server.listen(port, host, () => {
    console.log(`report proxy listening on http://${host}:${port}`);
  });
}

if (process.env.LOCAL_DEV_SERVER === "true") {
  startHTTPServer({
    host: "127.0.0.1",
    port: Number(process.env.PORT || 8787)
  });
} else if (import.meta.url === `file://${process.argv[1]}`) {
  startHTTPServer({
    host: "0.0.0.0",
    port: Number(process.env.FC_SERVER_PORT || process.env.CA_PORT || process.env.PORT || 9000)
  });
}
