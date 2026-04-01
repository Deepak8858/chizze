const fetch = globalThis.fetch;

async function run() {
  const headers = {
    'X-Appwrite-Project': '6993347c0006ead7404d',
    'X-Appwrite-Key': 'standard_bce5608cafe757835075f175595b32d446ad35dec4a7c81db5a78867ac41b52b07fc87145107dd68151c7b9e8083ae48d2dc241d1b649cebfdfc804928d410648dc475c77be9b3e35f94fda1b772b2d834a7e929b30eb83576af8bca77ed031bc5d50ae64e9c57ca613c5927dc0ada52488679d67de8b7205000ed5b79ae687d'
  };

  try {
    // 1. Search users for "prince"
    const userRes = await fetch('https://sgp.cloud.appwrite.io/v1/users?search=prince', { headers });
    let userData = await userRes.json();
    console.log("Users API:");
    console.dir(userData, {depth: null});

    // Fetch 100 orders and filter
    const oRes = await fetch('https://sgp.cloud.appwrite.io/v1/databases/chizze_db/collections/orders/documents?limit=100', { headers });
    let oData = await oRes.json();
    console.log("Found matching orders:", oData.documents?.filter(d => d.$id === 'CHZ-838777-229030' || d.order_id === 'CHZ-838777-229030'));

    // Fetch 100 users and filter
    const uRes = await fetch('https://sgp.cloud.appwrite.io/v1/databases/chizze_db/collections/users/documents?limit=100', { headers });
    let uData = await uRes.json();
    console.log("Found users named prince:", uData.documents?.filter(d => d.name?.toLowerCase().includes('prince')));

    // Fetch 100 delivery partners and filter
    const dpRes = await fetch('https://sgp.cloud.appwrite.io/v1/databases/chizze_db/collections/delivery_partners/documents?limit=100', { headers });
    let dpData = await dpRes.json();
    console.log("Found partners named prince:", dpData.documents?.filter(d => d.name?.toLowerCase().includes('prince') || d.user_name?.toLowerCase().includes('prince')));


  } catch(e) {
    console.error(e);
  }
}

run();
