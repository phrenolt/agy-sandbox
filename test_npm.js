const fs = require('fs');
try {
  console.log("Checking ~/.gemini:", fs.readdirSync(process.env.HOME + '/.gemini'));
} catch(e) {
  console.log("Error:", e.message);
}
