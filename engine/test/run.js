// Runs every test in this folder in turn: node engine/test/run.js (needs engine/dist/test.html: python3 engine/build.py)
const { execFileSync } = require("child_process");
const fs = require("fs"), path = require("path");
const out = path.join(require("os").tmpdir(), "pixelrealm-web");
fs.mkdirSync(out, { recursive: true });
for (const f of fs.readdirSync(__dirname).filter((f) => f.endsWith(".js") && f !== "run.js")) {
	console.log("== " + f);
	try { console.log(execFileSync("node", [path.join(__dirname, f)], { cwd: out, encoding: "utf8", timeout: 180000 })); }
	catch (e) { console.log("FAILED\n" + (e.stdout || "") + (e.stderr || "")); process.exitCode = 1; }
}
