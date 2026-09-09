# Contributing

By sending a pull request or otherwise contributing to Prompt Shell, you agree to the [CLA](CLA.md). Your contribution becomes the property of Christoffer Hallas.

If you cannot make that assignment, do not contribute. If this is work for an employer, get permission first.

Prompt Shell is licensed under the [MIT License](LICENSE).

## Getting Started

```sh
git clone https://github.com/csfh/promptshell.git
cd promptshell
npm install
```

Run locally without installing:

```sh
bin/psh.sh --help
```

## Running Tests

```sh
make test
```

The test suite uses the npm-installed Bats runner at `node_modules/bats/bin/bats`.

Run the installer smoke check:

```sh
make install-smoke
```

## Code Style

- POSIX shell for the CLI. Standalone PATH install is `install.sh` (bash) and does not require Omarchy. Omarchy plugin install is `omarchy plugin add` / `omarchy plugin install`. The bar widget launches bundled `bin/psh.sh`.
- Keep changes small and focused.
- Preserve stdin/stdout composition and scriptability.
- Use `/dev/tty` for interactive-only UI.
- Do not add build or lint commands unless the required config exists.

## Commit Messages

Use Conventional Commits, for example `feat:`, `fix:`, `docs:`, `test:`, or `chore:`.

## Pull Requests

- One concern per PR.
- Tests must pass.
- Keep the diff small.
- Include screenshots or terminal output for interactive UI changes when useful.

## Reporting Bugs

Open an issue: https://github.com/csfh/promptshell/issues
