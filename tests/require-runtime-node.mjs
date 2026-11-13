const [major, minor] = process.versions.node.split('.').map(Number);
if (major < 24 || (major === 24 && minor < 9)) {
  console.error(`DSH runtime tests require Node.js 24.9 or newer. Found ${process.version} at ${process.execPath}.`);
  process.exit(1);
}
