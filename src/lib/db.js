import "server-only";
import { Pool } from "pg";

function createPool() {
  const config = {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
  };
  const missingVariables = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"].filter(
    (name) =>
      process.env[name] === undefined ||
      (name !== "DB_PASSWORD" && !process.env[name]),
  );

  if (!process.env.DB_PORT) {
    missingVariables.push("DB_PORT");
  } else if (
    !Number.isInteger(config.port) ||
    config.port < 1 ||
    config.port > 65535
  ) {
    throw new Error("DB_PORT must be an integer between 1 and 65535.");
  }

  if (missingVariables.length > 0) {
    throw new Error(
      `Missing required PostgreSQL environment variables: ${missingVariables.join(", ")}`,
    );
  }

  const pool = new Pool(config);
  pool.on("error", (error) => {
    console.error("Unexpected PostgreSQL connection pool error:", error.message);
  });

  return pool;
}

function getPool() {
  if (!globalThis.__covidWarehousePool) {
    globalThis.__covidWarehousePool = createPool();
  }

  return globalThis.__covidWarehousePool;
}

export async function query(text, params = []) {
  try {
    return await getPool().query(text, params);
  } catch (error) {
    console.error(
      "PostgreSQL query failed:",
      error instanceof Error ? error.message : error,
    );
    throw error;
  }
}
