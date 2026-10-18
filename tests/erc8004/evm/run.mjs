// ABOUTME: Compares the Lean oracle with actual calls to the pinned upstream registries on a local EVM.
// ABOUTME: Adapts operation encoding and readback only, without reimplementing registry transition rules.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const project = path.join(root, ".tools/erc8004-evm");
const readJson = (filename) => JSON.parse(readFileSync(filename, "utf8"));
const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const sourceManifest = readJson(path.join(root, "specs/erc8004/manifest.json"));
const oracle = path.join(root, ".lake/build/bin/oracle");
const expectedVersions = {
  hardhat: "3.0.6", ethers: "6.15.0",
  "@openzeppelin/contracts": "5.4.0", "@openzeppelin/contracts-upgradeable": "5.4.0",
};

for (const [name, version] of Object.entries(expectedVersions)) {
  const filename = path.join(project, "node_modules", name, "package.json");
  if (!existsSync(filename)) throw new Error("Missing pinned EVM dependencies; see docs/evm-comparison.md.");
  assert.equal(readJson(filename).version, version, `${name} version differs from the pinned lock`);
}
assert.ok(existsSync(oracle), "Build the Lean oracle with lake build first.");
for (const entry of sourceManifest.files) {
  assert.equal(sha256(readFileSync(path.join(root, "specs/erc8004", entry.path))), entry.sha256);
  if (entry.path.startsWith("upstream/contracts/")) {
    assert.equal(sha256(readFileSync(path.join(project, "contracts", path.basename(entry.path)))), entry.sha256);
  }
}
for (const [source, destination] of [["Bootstrap.sol", "contracts/Bootstrap.sol"], ["hardhat.config.js", "hardhat.config.js"]]) {
  assert.equal(sha256(readFileSync(new URL(source, import.meta.url))), sha256(readFileSync(path.join(project, destination))));
}
const buildInfoDir = path.join(project, "artifacts/build-info");
assert.ok(existsSync(buildInfoDir), "Compile the staged Solidity project first.");
const buildInfos = readdirSync(buildInfoDir).filter((name) => name.endsWith(".json") && !name.endsWith(".output.json"));
assert.ok(buildInfos.length > 0, "No compiler build information found.");
const buildInfoIds = new Set();
const compiledContracts = new Set();
for (const filename of buildInfos) {
  const info = readJson(path.join(buildInfoDir, filename));
  buildInfoIds.add(info.id);
  assert.equal(info.solcVersion, "0.8.24");
  assert.equal(info.input.settings.evmVersion, "shanghai");
  assert.equal(info.input.settings.viaIR, true);
  assert.deepEqual(info.input.settings.optimizer, { enabled: true, runs: 200 });
  for (const [name, source] of Object.entries(info.input.sources)) {
    if (/^(?:project\/)?contracts\//.test(name)) {
      const local = path.join(project, name.replace(/^project\//, ""));
      assert.equal(source.content, readFileSync(local, "utf8"), `Compiled source differs: ${name}`);
      compiledContracts.add(path.basename(name));
    }
    const dependency = name.match(/^npm\/(@openzeppelin\/(?:contracts|contracts-upgradeable))@([^/]+)\/(.+)$/);
    if (dependency) {
      const [, name, version, filename] = dependency;
      assert.equal(version, expectedVersions[name]);
      assert.equal(source.content, readFileSync(path.join(project, "node_modules", name, filename), "utf8"));
    }
  }
}
for (const name of ["Bootstrap", "IdentityRegistryUpgradeable", "ReputationRegistryUpgradeable", "ValidationRegistryUpgradeable"]) {
  assert.ok(compiledContracts.has(`${name}.sol`), `Missing compiled source for ${name}`);
}

process.chdir(project);
const require = createRequire(path.join(project, "package.json"));
const ethers = require("ethers");
const hardhat = await import(pathToFileURL(require.resolve("hardhat")).href);
const network = await hardhat.network.connect("local");
const provider = new ethers.BrowserProvider(network.provider);
const accounts = await network.provider.request({ method: "eth_accounts" });
const deployer = await provider.getSigner(0);
const address = (n) => {
  assert.ok(Number.isSafeInteger(n) && n >= 0 && n <= accounts.length, "Address outside the local fixture domain");
  return n === 0 ? ethers.ZeroAddress : accounts[n - 1];
};
const abstractAddress = (value) => {
  if (value.toLowerCase() === ethers.ZeroAddress) return null;
  const index = accounts.findIndex((candidate) => candidate.toLowerCase() === value.toLowerCase());
  assert.notEqual(index, -1, "Contract returned an address outside the fixture domain");
  return index + 1;
};
const hash = (n) => ethers.toBeHex(BigInt(n), 32);
const artifacts = new Map();
async function artifact(name) {
  if (!artifacts.has(name)) {
    const data = await hardhat.artifacts.readArtifact(name);
    assert.ok(buildInfoIds.has(data.buildInfoId), `Unverified compiler build for ${name}`);
    artifacts.set(name, data);
  }
  return artifacts.get(name);
}
async function deploy(name, args = []) {
  const data = await artifact(name);
  const instance = await new ethers.ContractFactory(data.abi, data.bytecode, deployer).deploy(...args);
  await instance.waitForDeployment();
  return instance;
}
async function registries() {
  const bootstrap = await deploy("Bootstrap");
  async function proxy(name, identity = ethers.ZeroAddress) {
    const implementation = await deploy(name);
    const proxy = await deploy("RegistryProxy", [await bootstrap.getAddress(),
      bootstrap.interface.encodeFunctionData("initialize", [identity])]);
    const initial = new ethers.Contract(await proxy.getAddress(), (await artifact("Bootstrap")).abi, deployer);
    const registry = new ethers.Contract(await proxy.getAddress(), (await artifact(name)).abi, deployer);
    const initArgs = name === "IdentityRegistryUpgradeable" ? [] : [identity];
    await (await initial.upgradeToAndCall(await implementation.getAddress(),
      registry.interface.encodeFunctionData("initialize", initArgs))).wait();
    assert.equal(await registry.getVersion(), "2.0.0");
    return registry;
  }
  const identity = await proxy("IdentityRegistryUpgradeable");
  const reputation = await proxy("ReputationRegistryUpgradeable", await identity.getAddress());
  const validation = await proxy("ValidationRegistryUpgradeable", await identity.getAddress());
  return { identity, reputation, validation };
}

function leanObservation(input) {
  const result = spawnSync(oracle, ["erc8004", "-"], { input: JSON.stringify(input), encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `Lean oracle failed: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

async function evaluate(input) {
  const { identity, reputation, validation } = await registries();
  const events = [];
  const outcomes = [];
  for (const operation of input.operations) {
    assert.ok(operation.caller > 0, "Transactions from address zero are outside this adapter");
    const from = address(operation.caller);
    let call;
    try {
      switch (operation.op) {
        case "register": call = await identity["register()"].populateTransaction(); break;
        case "approve": call = await identity.approve.populateTransaction(address(operation.operator ?? 0), operation.agentId); break;
        case "setOperator": call = await identity.setApprovalForAll.populateTransaction(address(operation.operator), operation.enabled); break;
        case "transfer": call = await identity.transferFrom.populateTransaction(await identity.ownerOf(operation.agentId), address(operation.newOwner), operation.agentId); break;
        case "unsetWallet": call = await identity.unsetAgentWallet.populateTransaction(operation.agentId); break;
        case "setWallet": {
          const owner = await identity.ownerOf(operation.agentId);
          const block = await network.provider.request({ method: "eth_getBlockByNumber", params: ["latest", false] });
          const deadline = BigInt(block.timestamp) + 300n;
          let signature = "0x";
          if (operation.proofValid && operation.wallet !== 0) {
            const wallet = await provider.getSigner(operation.wallet - 1);
            signature = await wallet.signTypedData(
              { name: "ERC8004IdentityRegistry", version: "1", chainId: 31337, verifyingContract: await identity.getAddress() },
              { AgentWalletSet: [{ name: "agentId", type: "uint256" }, { name: "newWallet", type: "address" },
                { name: "owner", type: "address" }, { name: "deadline", type: "uint256" }] },
              { agentId: operation.agentId, newWallet: address(operation.wallet), owner, deadline });
          }
          call = await identity.setAgentWallet.populateTransaction(operation.agentId, address(operation.wallet), deadline, signature);
          break;
        }
        case "feedback":
          assert.ok(typeof operation.value === "string" || Number.isSafeInteger(operation.value), "Use a decimal string for a large value");
          call = await reputation.giveFeedback.populateTransaction(operation.agentId, BigInt(operation.value), operation.decimals,
            "", "", "", "", ethers.ZeroHash); break;
        case "request": call = await validation.validationRequest.populateTransaction(address(operation.validator), operation.agentId, "", hash(operation.hash)); break;
        case "respond": call = await validation.validationResponse.populateTransaction(hash(operation.hash), operation.response, "", ethers.ZeroHash, ""); break;
        default: throw new Error(`Unsupported operation ${operation.op}`);
      }
      const tx = await network.provider.request({ method: "eth_sendTransaction", params: [{
        from, to: call.to, data: call.data, gas: "0x7a1200",
      }] });
      const receipt = await network.provider.request({ method: "eth_getTransactionReceipt", params: [tx] });
      assert.equal(receipt.status, "0x1", "Unexpected mined failure without a revert diagnostic");
      outcomes.push({ status: "accepted" });
      for (const log of receipt.logs) {
        const registry = [identity, reputation, validation].find((c) => c.target.toLowerCase() === log.address.toLowerCase());
        const event = registry?.interface.parseLog(log);
        if (event) events.push(event);
      }
    } catch (error) {
      if (error.code !== "CALL_EXCEPTION" && !/reverted|VM Exception|revert reason/i.test(error.message)) throw error;
      outcomes.push({ status: "rejected", reason: error.shortMessage ?? error.message });
    }
  }
  // Read contract storage through public views; event indices only enumerate stored entries.
  const agents = [];
  for (const event of events.filter((e) => e.name === "Registered")) {
    const id = Number(event.args.agentId);
    agents.push({ id, owner: abstractAddress(await identity.ownerOf(id)),
      wallet: abstractAddress(await identity.getAgentWallet(id)),
      approved: abstractAddress(await identity.getApproved(id)) });
  }
  const feedback = [];
  for (const event of events.filter((e) => e.name === "NewFeedback")) {
    const { agentId, clientAddress, feedbackIndex } = event.args;
    const stored = await reputation.readFeedback(agentId, clientAddress, feedbackIndex);
    feedback.push({ agentId: Number(agentId), client: abstractAddress(clientAddress), index: Number(feedbackIndex),
      value: stored[0].toString(), decimals: Number(stored[1]) });
  }
  const validations = [];
  for (const event of events.filter((e) => e.name === "ValidationRequest")) {
    const requestHash = event.args.requestHash;
    const stored = await validation.getValidationStatus(requestHash);
    const hasResponse = events.some((e) => e.name === "ValidationResponse" && e.args.requestHash === requestHash);
    validations.push({ hash: Number(BigInt(requestHash)), agentId: Number(stored[1]),
      validator: abstractAddress(stored[0]), response: hasResponse ? Number(stored[2]) : null });
  }
  return { state: { nextAgent: agents.length, agents, feedback, validations }, outcomes };
}

const comparisonView = (result) => ({ state: result.state, outcomes: result.outcomes.map(({ status }) => status) });
async function minimize(operations) {
  let reduced = operations;
  const deletionChecks = [];
  for (let index = 0; index < reduced.length;) {
    const candidate = reduced.filter((_, i) => i !== index);
    const lean = leanObservation({ operations: candidate });
    const evm = await evaluate({ operations: candidate });
    const matches = isDeepStrictEqual(comparisonView(lean), comparisonView(evm));
    deletionChecks.push({ removedIndex: index, operations: candidate, matches, lean, evm });
    if (matches) index += 1;
    else { reduced = candidate; index = 0; }
  }
  return { operations: reduced, deletionChecks };
}
const cases = ["transfer-wallet", "self-feedback", "former-owner-feedback", "validation-race", "value-cap-witness"];
const reports = [];
let complete = false;
try {
  for (const name of cases) {
    const input = readJson(path.join(root, "tests/erc8004", `${name}.json`));
    const lean = leanObservation(input);
    const evm = await evaluate(input);
    const matches = isDeepStrictEqual(comparisonView(lean), comparisonView(evm));
    const expectedDivergence = name === "value-cap-witness";
    const report = { fixture: name, matches, expectedDivergence, lean, evm };
    reports.push(report);
    console.log(`${name}: ${matches ? "MATCH" : "DIVERGENCE"}`);
    if (expectedDivergence) {
      assert.equal(lean.outcomes[1].status, "accepted");
      assert.equal(evm.outcomes[1].status, "rejected");
      assert.match(evm.outcomes[1].reason, /value too large/);
      assert.equal(evm.state.feedback.length, 0);
      report.minimization = await minimize(input.operations);
      writeFileSync(path.join(project, "value-cap-minimized.json"), JSON.stringify({
        operations: report.minimization.operations,
      }, null, 2) + "\n");
      console.log(`${name}: deletion-minimal at ${report.minimization.operations.length} operations`);
    } else {
      assert.ok(matches, `Unexpected divergence in ${name}`);
    }
  }
  complete = true;
} finally {
  writeFileSync(path.join(project, "differential-report.json"), JSON.stringify({
    complete, checkedAt: new Date().toISOString(), nodeVersion: process.version,
    leanToolchain: readFileSync(path.join(root, "lean-toolchain"), "utf8").trim(),
    implementationCommit: sourceManifest.implementation.commit, specificationCommit: sourceManifest.spec.commit,
    compiler: "0.8.24", evmVersion: "shanghai", optimizer: { enabled: true, runs: 200 }, viaIR: true,
    dependencyVersions: expectedVersions, oracleSha256: sha256(readFileSync(oracle)), reports,
    runnerSha256: sha256(readFileSync(fileURLToPath(import.meta.url))),
    buildInfoSha256: Object.fromEntries(buildInfos.map((name) => [name, sha256(readFileSync(path.join(buildInfoDir, name)))])),
  }, null, 2) + "\n");
  await network.close();
}
