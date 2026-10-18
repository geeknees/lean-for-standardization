// ABOUTME: Pins the compiler and a local, deterministic EVM for independent differential tests.
// ABOUTME: Uses no dotenv files, external RPC networks, or user wallet credentials.
export default {
  solidity: {
    version: "0.8.24",
    settings: {
      evmVersion: "shanghai",
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
  },
  networks: {
    local: {
      type: "edr-simulated",
      chainType: "l1",
      chainId: 31337,
      hardfork: "shanghai",
      initialDate: "2026-10-18T00:00:00Z",
    },
  },
};
