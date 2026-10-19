# Check a Python install command — development preview

This workflow is part of the unmerged 0.4.0 preview. The public v0.3.2 download does not contain it. Use the exact-source CI test artifact when reviewing this branch.

Terminal Helper helps you choose an interpreter without leaving the terminal. It does not validate Python runtime behavior, package installation or import success.

## Use it

1. Work in the project directory that directly contains the candidate .venv.
2. Enable Terminal Helper suggestions.
3. Type a simple command such as pip install pandas or python -m pip install pandas.
4. Press **Control-X, then Control-P**. The shortcut is installed only if available in your supported emacs/viins keymap. Existing bindings and longer sequences remain untouched; doctor explains conflicts.
5. Read the resolution evidence, environment candidate, mismatch explanation and proposed command.
6. Choose **Insert (Enter)** to replace command text, or **Dismiss (Escape)** to restore the original text and cursor. A separate deliberate Enter runs the inserted command.

The check is explicit. It does not run while typing or show a macOS dialog. Editing dismisses the pending offer while keeping your edit. Off prevents inspection; Off or changed evidence before insertion cancels a pending offer.

## Example

For an illustrative project at /project with a .venv candidate:

    Input: pip install pandas
    Resolution: pip resolves outside this project's .venv
    Environment candidate: /project/.venv
    Proposed: /project/.venv/bin/python -m pip install pandas
    Reason: invoke pip through the project's interpreter candidate
    Insert (Enter) | Dismiss (Escape)

Paths come from actual local evidence, with shell quoting preserved for spaces, Unicode and literal shell-looking names. This example is not a hardcoded path or an assertion that this interpreter is healthy.

## Supported evidence

The initial subset recognizes bare pip/pip3 install and python/python3 -m pip install with literal arguments. It uses zsh lexical handling and shell command resolution without evaluating the input or running discovered programs.

Only the current project directory is checked; there is no upward walk, recursive search, index or background scan. A small regular pyvenv.cfg file and an executable candidate at .venv/bin/python indicate a possible virtual environment. Standard environments can legitimately use interpreter symlinks. Metadata and executable permission do not establish that an executable is trustworthy, intact or functional. See the [Python virtual-environment specification](https://peps.python.org/pep-0405/).

A matching invocation path is reported as resolution evidence, not runtime proof. An external command named pip may itself be a wrapper; its behavior cannot be established without executing it, which this checker does not do.

## When it declines

The checker leaves input unchanged for unsupported or ambiguous cases: aliases/functions, wrapper command prefixes, target options, operators, substitutions, redirects, glob expressions, multiline input, missing or malformed metadata, conflicting environments, a different explicitly active environment, and detectable remote/container contexts.

Known Python/pip target or configuration overrides are declined without printing their values. The checker does not inspect all pip configuration files. pip configuration can change installation behavior, so using an explicit interpreter is not a guarantee about the final package destination. See [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/).

There is no automatic activation, installation, directory change or execution. No Python/Jupyter object introspection is provided.

## Privacy and troubleshooting

The buffer is inspected in memory for this interaction and is not logged, stored or sent anywhere. Environment values, history and project contents are not uploaded. The check performs bounded local metadata reads and built-in shell resolution only. Slow or network filesystems can still delay those reads.

Run terminal-helper doctor in the affected shell to distinguish app metadata, loaded integration and binding ownership. Keep another plugin's shortcut or deliberately choose your own binding; the helper never silently takes it. Finish or dismiss an active completion menu before checking a command.

Restart shells after installing/updating integration. No personal-Mac installation is implied by a CI pass; actual Terminal.app/iTerm2 and VoiceOver behavior remain manual checks.
