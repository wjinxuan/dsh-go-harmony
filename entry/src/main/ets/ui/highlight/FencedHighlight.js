// Native token adapter for the pinned upstream highlighter; see SOURCE.json.
import hljs from './core.js';
import bash from './bash.js';
import c from './c.js';
import clojure from './clojure.js';
import cmake from './cmake.js';
import cpp from './cpp.js';
import csharp from './csharp.js';
import css from './css.js';
import dart from './dart.js';
import diff from './diff.js';
import dockerfile from './dockerfile.js';
import dos from './dos.js';
import elixir from './elixir.js';
import erlang from './erlang.js';
import fsharp from './fsharp.js';
import go from './go.js';
import gradle from './gradle.js';
import graphql from './graphql.js';
import groovy from './groovy.js';
import haskell from './haskell.js';
import http from './http.js';
import ini from './ini.js';
import java from './java.js';
import javascript from './javascript.js';
import json from './json.js';
import julia from './julia.js';
import kotlin from './kotlin.js';
import latex from './latex.js';
import less from './less.js';
import lua from './lua.js';
import makefile from './makefile.js';
import markdown from './markdown.js';
import matlab from './matlab.js';
import nginx from './nginx.js';
import nix from './nix.js';
import objectivec from './objectivec.js';
import ocaml from './ocaml.js';
import perl from './perl.js';
import php from './php.js';
import powershell from './powershell.js';
import properties from './properties.js';
import protobuf from './protobuf.js';
import python from './python.js';
import r from './r.js';
import ruby from './ruby.js';
import rust from './rust.js';
import scala from './scala.js';
import scss from './scss.js';
import shell from './shell.js';
import sql from './sql.js';
import swift from './swift.js';
import typescript from './typescript.js';
import verilog from './verilog.js';
import vim from './vim.js';
import vue from './vue.js';
import xml from './xml.js';
import yaml from './yaml.js';
const grammars = { bash, c, clojure, cmake, cpp, csharp, css, dart, diff, dockerfile, dos, elixir, erlang, fsharp, go, gradle, graphql, groovy, haskell, http, ini, java, javascript, json, julia, kotlin, latex, less, lua, makefile, markdown, matlab, nginx, nix, objectivec, ocaml, perl, php, powershell, properties, protobuf, python, r, ruby, rust, scala, scss, shell, sql, swift, typescript, verilog, vim, vue, xml, yaml };
for (const name of Object.keys(grammars)) hljs.registerLanguage(name, grammars[name]);
const aliases = {
  "js": "javascript",
  "jsx": "javascript",
  "mjs": "javascript",
  "cjs": "javascript",
  "node": "javascript",
  "ts": "typescript",
  "tsx": "typescript",
  "py": "python",
  "sh": "bash",
  "zsh": "bash",
  "fish": "bash",
  "console": "shell",
  "yml": "yaml",
  "toml": "ini",
  "html": "xml",
  "htm": "xml",
  "svg": "xml",
  "c++": "cpp",
  "cc": "cpp",
  "cxx": "cpp",
  "h": "c",
  "hpp": "cpp",
  "rs": "rust",
  "kt": "kotlin",
  "kts": "kotlin",
  "md": "markdown",
  "patch": "diff",
  "rb": "ruby",
  "docker": "dockerfile",
  "make": "makefile",
  "cs": "csharp",
  "c#": "csharp",
  "objc": "objectivec",
  "objective-c": "objectivec",
  "mm": "objectivec",
  "pl": "perl",
  "ps1": "powershell",
  "pwsh": "powershell",
  "ps": "powershell",
  "bat": "dos",
  "cmd": "dos",
  "batch": "dos",
  "tex": "latex",
  "proto": "protobuf",
  "gql": "graphql",
  "hs": "haskell",
  "ex": "elixir",
  "exs": "elixir",
  "erl": "erlang",
  "fs": "fsharp",
  "f#": "fsharp",
  "ml": "ocaml",
  "jl": "julia",
  "sass": "scss",
  "jsonc": "json",
  "json5": "json",
  "conf": "ini",
  "cfg": "ini",
  "env": "properties",
  "sv": "verilog",
  "vimscript": "vim",
  "jsonl": "json",
  "psql": "sql",
  "mysql": "sql",
  "postgresql": "sql",
  "sqlite": "sql"
};
const languageNames = Object.keys(grammars);
export function highlightLanguages() { return languageNames.slice(); }
export function normalizedLanguage(value) {
  const name = String(value || '').trim().split(/\s+/)[0].toLowerCase();
  const resolved = aliases[name] || name;
  return languageNames.includes(resolved) ? resolved : '';
}

// Same streaming boundaries and per-chunk fallback as fixed code_block.dart.
export function codeChunks(code) {
  const lines = code.match(/[^\n]*\n|[^\n]+$/g) || [];
  if (lines.length <= 200 && code.length <= 8000) return [code];
  const chunks = [];
  let start = 0, comments = 0, quote;
  for (let line = 0; line < lines.length; line++) {
    const text = lines[line], count = line - start;
    if (count >= 400 || (count >= 200 && comments === 0 && !quote &&
      !lines[line - 1].trim() && /^[A-Za-z0-9_]/.test(text))) {
      chunks.push(lines.slice(start, line).join('')); start = line;
    }
    for (let i = 0; i < text.length;) {
      if (comments > 0) {
        if (text.startsWith('/*', i)) { comments++; i += 2; }
        else if (text.startsWith('*/', i)) { comments--; i += 2; }
        else i++;
      } else if (quote) {
        if (text[i] === '\\') i += 2;
        else if (text.startsWith(quote, i)) { i += quote.length; quote = undefined; }
        else i++;
      } else if (text.startsWith('//', i) || text[i] === '#') break;
      else if (text.startsWith('/*', i)) { comments++; i += 2; }
      else if ('"\'`'.includes(text[i])) {
        quote = text.startsWith(text[i].repeat(3), i) ? text[i].repeat(3) : text[i]; i += quote.length;
      } else i++;
    }
    if (quote === '"' || quote === "'") quote = undefined;
  }
  chunks.push(lines.slice(start).join(''));
  return chunks;
}

const cache = new Map();
function highlightChunk(code, language) {
  const key = language + '\0' + code;
  if (cache.has(key)) { const value = cache.get(key); cache.delete(key); cache.set(key, value); return value; }
  let runs = [{ text: code, scopes: [] }];
  if (code.length <= 20000) {
    try {
      const result = hljs.highlight(code, { language, ignoreIllegals: true });
      const output = [];
      function visit(node, scopes) {
        if (typeof node === 'string') {
          if (node) output.push({ text: node, scopes });
        } else {
          const next = node.scope ? scopes.concat(node.scope) : scopes;
          for (const child of node.children) visit(child, next);
        }
      }
      visit(result._emitter.rootNode, []);
      if (output.map(run => run.text).join('') === code) runs = output;
    } catch { /* Keep the complete source if a grammar rejects partial input. */ }
  }
  cache.set(key, runs);
  if (cache.size > 64) cache.delete(cache.keys().next().value);
  return runs;
}

export function highlightCode(code, label) {
  const language = normalizedLanguage(label);
  if (!language) return [{ text: code, scopes: [] }];
  return codeChunks(code).flatMap(chunk => highlightChunk(chunk, language));
}
