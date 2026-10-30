# Gate commands by toolchain

Look here once you know which ecosystem the PR is in — you only need your own row.

**Read the repo's own definitions first.** `package.json` scripts, `Makefile`, `justfile`,
`Taskfile.yml`, `noxfile.py`, and above all the CI workflow (`.github/workflows/*.yml`) tell you
the command this project actually gates on. The table below is the fallback for when none exist —
a generic command that passes while the project's real gate would have failed is worse than no gate.

| Detected file | Typecheck / build | Tests |
|---|---|---|
| `tsconfig.json` | `tsc --noEmit` | `jest` / `vitest run` / `npm test` |
| `package.json`, no TS | `npm run build` (if defined) | `npm test` |
| `bun.lockb` | `bun run build` | `bun test` |
| `deno.json` | `deno check **/*.ts` | `deno test` |
| `pyproject.toml` / `setup.py` | `mypy .` / `pyright` (if configured) | `pytest` |
| `go.mod` | `go build ./... && go vet ./...` | `go test ./...` |
| `Cargo.toml` | `cargo check` (+ `cargo clippy` if in CI) | `cargo test` |
| `pom.xml` | `mvn -q compile` | `mvn -q test` |
| `build.gradle[.kts]` | `./gradlew compileJava` / `compileKotlin` | `./gradlew test` |
| `pubspec.yaml` | `dart analyze` / `flutter analyze` | `dart test` / `flutter test` |
| `Package.swift` / `*.xcodeproj` | `swift build` / `xcodebuild -quiet build` | `swift test` / `xcodebuild test` |
| `composer.json` | `phpstan analyse` / `psalm` (if configured) | `phpunit` / `php artisan test` |
| `Gemfile` | `rubocop` (if configured) | `rspec` / `rake test` |
| `*.csproj` / `*.sln` | `dotnet build` | `dotnet test` |
| `mix.exs` | `mix compile --warnings-as-errors` | `mix test` |
| `CMakeLists.txt` / `Makefile` | `cmake --build build` / `make` | `ctest` / `make test` |
| `*.tf` | `terraform validate` | `terraform plan` (read-only) |
| none of the above | — | — |

Polyglot repo (a `go.mod` service next to a Next.js app): run only the gates for the
ecosystems the changed files belong to. Running the frontend suite for a Go-only fix burns
minutes and proves nothing about the fix.

## Parallelism caps

This machine is low-spec and an uncapped suite can hang it, which costs far more time than the
suite would have taken:

| Runner | Flag |
|---|---|
| Jest | `--maxWorkers=2` |
| Vitest | `--maxWorkers=2` (Vitest 4 rejects `--poolOptions.*`; Vitest ≤3: `--pool=forks --poolOptions.forks.maxForks=2`) |
| pytest-xdist | `-n 2` |
| Gradle / Maven | `--max-workers=2` / `-T 2` |
| Go | `-p 2` |
| Cargo | `--jobs 2` |
| make / cmake | `-j2` |

## Narrowing when the full suite is impractical

Too slow, or needs services that aren't running — run only the tests reachable from the changed
files, and say so in the report. A narrowed run honestly labelled is useful; a narrowed run
reported as "all tests pass" is a false clearance.

| Runner | Narrowed form |
|---|---|
| Jest / Vitest | `--findRelatedTests <files>` / `related <files>` |
| pytest | `pytest <dir-or-file> -k <expr>` |
| Go | `go test ./<pkg>/...` |
| Cargo | `cargo test --package <crate>` |
| Gradle | `./gradlew :<module>:test --tests <pattern>` |
