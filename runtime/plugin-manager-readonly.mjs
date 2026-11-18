// The canonical bundle inventory is needed for source ownership checks in the
// upstream native configuration bridge. The embedded engine cannot run package
// manager processes. Override every mutating / package-executing entry point.
import { PluginManager } from '@deepseek-ai/dsh-plugin-manager';
import { RemoteError } from '@deepseek-ai/dsh-typert-protocol';
function unsupported() { throw new RemoteError('plugin-manager/unsupported-platform', 'Package operations are unavailable in the embedded HarmonyOS engine'); }
export default class HarmonyPluginInventory extends PluginManager {
  harmonyReadOnly = true;
  inspect(spec, options, signal) { return unsupported(); }
  listVersions(name, options, signal) { return unsupported(); }
  updateBundle(name, version, options) { return unsupported(); }
  installBundle(spec, options) { return unsupported(); }
  removeBundle(name) { return unsupported(); }
  setPluginEnabled(id, enabled) { return unsupported(); }
  setBundleEnabled(name, enabled) { return unsupported(); }
  setVersionExemption(packageVersion, runtimeVersion, enabled, acceptRisk) { return unsupported(); }
  waitForInstall(requestId) { return unsupported(); }
  cancelInstall(requestId) { return unsupported(); }
}
