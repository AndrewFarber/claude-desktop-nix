// Injected into app.asar by package.nix.
//
// Claude Desktop downloads its own Claude Code CLI into
// ~/.config/Claude/claude-code/<version>/<hash>/claude. That is a generic glibc
// binary whose ELF interpreter is /lib64/ld-linux-*.so, which NixOS doesn't
// provide. Point the interpreter at the Nix glibc loader instead, so the
// binary runs directly and still sees itself as process.execPath (the CLI
// re-executes itself, so wrapping it in `ld.so <binary>` is not an option).
//
// Only the host CLI is touched: claude-ssh (copied to remote machines) and the
// Cowork VM binary (claude-code-vm/) must keep their generic interpreter.
globalThis.__nixClaudeCodeInterpreter = (() => {
  const loader = "@loader@";
  const patchelf = "@patchelf@";
  const hostCli = /\/claude-code\/[^/]+\/[^/]+\/claude$/;
  const done = new Set();
  return (file, dest) => {
    if (process.platform !== "linux" || done.has(file) || !hostCli.test(dest)) return;
    const { execFileSync } = require("child_process");
    try {
      const current = execFileSync(patchelf, ["--print-interpreter", file], { encoding: "utf8" }).trim();
      if (current !== loader) execFileSync(patchelf, ["--set-interpreter", loader, file]);
      done.add(file);
    } catch (e) {
      console.error(`[nix] could not set the ELF interpreter of ${file}: ${e}`);
    }
  };
})();
