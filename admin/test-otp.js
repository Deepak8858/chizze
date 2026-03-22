import { Client, Account, ID } from "appwrite";

const client = new Client()
    .setEndpoint('https://sgp.cloud.appwrite.io/v1') 
    .setProject('6993347c0006ead7404d');

const account = new Account(client);

async function run() {
  try {
    const p = process.argv[2] || '8838383383';
    console.log("Sending OTP to", p);
    const token = await account.createPhoneToken(ID.unique(), `+91${p}`);
    console.log("Token created:", token);
  } catch(e) {
    console.error("Error:", e);
  }
}

run();
