import crypto from "node:crypto";
import http from "node:http";
import TableStore from "tablestore";
import {
  Environment,
  SignedDataVerifier
} from "@apple/app-store-server-library";

const config = {
  productId: requiredEnv("REPORT_PRODUCT_ID", "admission_calculator_ai_report"),
  bundleId: requiredEnv("APPLE_BUNDLE_ID"),
  appAppleId: optionalIntegerEnv("APPLE_APPLE_ID"),
  appleEnvironment: appleEnvironment(),
  transactionSecret: requiredEnv("TRANSACTION_HMAC_SECRET"),
  dashscopeApiKey: requiredEnv("DASHSCOPE_API_KEY"),
  dashscopeBaseUrl: process.env.DASHSCOPE_BASE_URL || "https://dashscope.aliyuncs.com/compatible-mode/v1",
  dashscopeModel: process.env.DASHSCOPE_MODEL || "qwen-plus",
  otsTableName: process.env.OTS_TABLE_NAME || "admission_report_transactions",
  pendingTimeoutMs: Number(process.env.PENDING_TIMEOUT_MS || 10 * 60 * 1000),
  skipAppleVerification: process.env.SKIP_APPLE_VERIFY_FOR_LOCAL_DEV === "true"
};

const tableStoreClient = createTableStoreClient();

export async function handler(event) {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();

  try {
    const request = parseHTTPEvent(event);
    if (request.method && request.method !== "POST") {
      return jsonResponse(405, { error: "method_not_allowed", requestId });
    }

    const body = parseJSONBody(request.body);
    validateBody(body);

    const transaction = await verifyAppleTransaction(body.transaction);
    const transactionHash = hmac(transaction.transactionId);
    const originalTransactionHash = hmac(transaction.originalTransactionId || transaction.transactionId);

    const existing = await getTransaction(transactionHash);
    if (existing?.status === "used") {
      return jsonResponse(409, { error: "transaction_already_used", requestId });
    }
    if (existing?.status === "pending" && Date.now() - Number(existing.updated_at || 0) < config.pendingTimeoutMs) {
      return jsonResponse(409, { error: "transaction_pending", requestId });
    }

    await putOrUpdateTransaction({
      transactionHash,
      originalTransactionHash,
      productId: transaction.productId,
      status: "pending",
      requestId
    });

    let reportText;
    try {
      reportText = await generateReport({
        instructions: body.instructions,
        input: body.input,
        requestId
      });
    } catch (error) {
      await updateTransaction(transactionHash, {
        status: "failed",
        request_id: requestId,
        failure_code: error.code || "llm_request_failed",
        updated_at: Date.now()
      });
      throw error;
    }

    await updateTransaction(transactionHash, {
      status: "used",
      provider: "dashscope",
      model: config.dashscopeModel,
      request_id: requestId,
      updated_at: Date.now()
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
      message: error.message
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
  const response = await fetch(`${config.dashscopeBaseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${config.dashscopeApiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: config.dashscopeModel,
      messages: [
        { role: "system", content: instructions },
        { role: "user", content: input }
      ],
      temperature: 0.3
    })
  });

  const text = await response.text();
  if (!response.ok) {
    throw publicError(502, "llm_request_failed", `模型服务调用失败：${response.status}`, {
      providerStatus: response.status,
      providerRequestId: requestId
    });
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw publicError(502, "llm_invalid_json", "模型服务返回格式无法解析。");
  }
  const content = data?.choices?.[0]?.message?.content;
  if (!content || typeof content !== "string") {
    throw publicError(502, "llm_empty_response", "模型服务没有返回报告正文。");
  }
  return content;
}

async function getTransaction(transactionHash) {
  if (!tableStoreClient) {
    return undefined;
  }
  const result = await otsCall("getRow", {
    tableName: config.otsTableName,
    primaryKey: [{ transaction_hash: transactionHash }]
  });
  const columns = result?.row?.attributes || [];
  if (!columns.length) {
    return undefined;
  }
  return Object.fromEntries(columns.map((column) => [column.columnName, column.columnValue]));
}

async function putOrUpdateTransaction(row) {
  const now = Date.now();
  const attributes = {
    original_transaction_hash: row.originalTransactionHash,
    product_id: row.productId,
    status: row.status,
    provider: "dashscope",
    model: config.dashscopeModel,
    request_id: row.requestId,
    created_at: now,
    updated_at: now
  };

  if (!tableStoreClient) {
    return;
  }
  try {
    await otsCall("putRow", {
      tableName: config.otsTableName,
      condition: new TableStore.Condition(TableStore.RowExistenceExpectation.EXPECT_NOT_EXIST, null),
      primaryKey: [{ transaction_hash: row.transactionHash }],
      attributeColumns: otsAttributes(attributes)
    });
  } catch (error) {
    await updateTransaction(row.transactionHash, {
      status: "pending",
      request_id: row.requestId,
      updated_at: now
    });
  }
}

async function updateTransaction(transactionHash, attributes) {
  if (!tableStoreClient) {
    return;
  }
  await otsCall("updateRow", {
    tableName: config.otsTableName,
    condition: new TableStore.Condition(TableStore.RowExistenceExpectation.IGNORE, null),
    primaryKey: [{ transaction_hash: transactionHash }],
    updateOfAttributeColumns: [
      {
        PUT: otsAttributes(attributes)
      }
    ]
  });
}

function createTableStoreClient() {
  const endpoint = process.env.OTS_ENDPOINT;
  const instanceName = process.env.OTS_INSTANCE_NAME;
  if (!endpoint || !instanceName) {
    return undefined;
  }
  return new TableStore.Client({
    accessKeyId: process.env.ALIBABA_CLOUD_ACCESS_KEY_ID,
    secretAccessKey: process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET,
    stsToken: process.env.ALIBABA_CLOUD_SECURITY_TOKEN,
    endpoint,
    instancename: instanceName
  });
}

function otsCall(method, params) {
  return new Promise((resolve, reject) => {
    tableStoreClient[method](params, (error, data) => {
      if (error) {
        reject(error);
      } else {
        resolve(data);
      }
    });
  });
}

function otsAttributes(attributes) {
  return Object.entries(attributes)
    .filter(([, value]) => value !== undefined && value !== null)
    .map(([columnName, columnValue]) => ({ [columnName]: columnValue }));
}

function parseHTTPEvent(event) {
  if (event && typeof event === "object" && "body" in event) {
    return {
      method: event.httpMethod || event.requestContext?.http?.method,
      body: event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : event.body
    };
  }
  if (Buffer.isBuffer(event)) {
    return { body: event.toString("utf8") };
  }
  if (typeof event === "string") {
    return { body: event };
  }
  return { body: JSON.stringify(event || {}) };
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

function hmac(value) {
  return crypto
    .createHmac("sha256", config.transactionSecret)
    .update(String(value))
    .digest("hex");
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

if (process.env.LOCAL_DEV_SERVER === "true") {
  const port = Number(process.env.PORT || 8787);
  http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }
    const result = await handler({
      httpMethod: request.method,
      body: Buffer.concat(chunks).toString("utf8")
    });
    response.writeHead(result.statusCode, result.headers);
    response.end(result.body);
  }).listen(port, () => {
    console.log(`report proxy listening on http://127.0.0.1:${port}`);
  });
}
