"use client";
import { Client, Account, Databases, ID } from "appwrite";

const client = new Client()
  .setEndpoint("https://sgp.cloud.appwrite.io/v1")
  .setProject("6993347c0006ead7404d");

const account = new Account(client);
const databases = new Databases(client);

// Ping Appwrite on load to verify connectivity
client.ping().then(
  () => console.log("[Appwrite] Connected"),
  (err: unknown) => console.warn("[Appwrite] Ping failed:", err)
);

export { client, account, databases, ID };
