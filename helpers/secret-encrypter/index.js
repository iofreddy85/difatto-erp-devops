const sodium = require("libsodium-wrappers");

// https://docs.github.com/en/rest/guides/encrypting-secrets-for-the-rest-api?apiVersion=2022-11-28#example-encrypting-a-secret-using-nodejs
async function start() {
  const argsRegex = /=(?<val>.*)/;
  const realArgs = [];
  const pwd = `${process.env.PWD}`;

  process.argv.forEach(function (val) {
    if (val.indexOf("--") >= 0) {
      realArgs.push(val);
    }
  });

  let publicKey;
  let secret;

  realArgs.forEach((ra) => {
    if (ra.indexOf("--public-key") >= 0) {
      publicKey = ra.match(argsRegex).groups.val;
    } else if (ra.indexOf("--secret") >= 0) {
      secret = ra.match(argsRegex).groups.val;
    }
  });

  const key = publicKey;
  //Check if libsodium is ready and then proceed.
  await sodium.ready.then(() => {
    // Convert the secret and key to a Uint8Array.
    let binkey = sodium.from_base64(key, sodium.base64_variants.ORIGINAL);
    let binsec = sodium.from_string(secret);

    // Encrypt the secret using libsodium
    let encBytes = sodium.crypto_box_seal(binsec, binkey);

    // Convert the encrypted Uint8Array to Base64
    let output = sodium.to_base64(encBytes, sodium.base64_variants.ORIGINAL);

    // Print the output
    console.log(output);
  });
}

start().then(() => process.exit());
