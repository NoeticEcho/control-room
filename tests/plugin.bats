#!/usr/bin/env bats
# Checks for the Claude plugin in plugin/: what the plugin directory's
# pre-submission checklist asks for (https://claude.com/docs/plugins/pre-submission-checklist,
# read 2026-09-30), the choices of this version (no hooks, no MCP servers, no
# launchers, plain shell named from ${CLAUDE_PLUGIN_ROOT}), and that the texts
# it copies from this repository have not drifted from their originals.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PLUGIN="$ROOT/plugin"
MANIFEST="$PLUGIN/.claude-plugin/plugin.json"

# The frontmatter keys every surface accepts (the Agent Skills spec's six);
# anything else fails a claude.ai upload.
SPEC_KEYS=" name description license compatibility metadata allowed-tools "

@test "the manifest: JSON, a distinctive kebab-case name, and the fields the directory reads" {
	jq -e . "$MANIFEST" >/dev/null
	name=$(jq -r .name "$MANIFEST")
	[ "$name" = noetic-control-room ]
	[[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
	[ "${#name}" -le 64 ]
	for field in displayName description version author.name homepage repository license; do
		value=$(jq -r ".$field // empty | strings" "$MANIFEST")
		[ -n "$value" ] || { echo "no $field"; return 1; }
	done
	[ "$(jq -r .license "$MANIFEST")" = Apache-2.0 ]
	[ "$(jq -r .author.name "$MANIFEST")" = NoeticEcho ]
	[ "$(jq -r .repository "$MANIFEST")" = https://github.com/NoeticEcho/control-room ]
	[[ "$(jq -r .version "$MANIFEST")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "the version is at least the repository's latest release tag" {
	latest=$(git -C "$ROOT" tag -l 'v[0-9]*' --sort=-version:refname | sed -n '1s/^v//p')
	[ -n "$latest" ] || skip "no release tags in this checkout"
	version=$(jq -r .version "$MANIFEST")
	[ "$(printf '%s\n%s\n' "$latest" "$version" | sort -V | tail -1)" = "$version" ]
}

@test "no hooks, MCP or LSP servers, monitors, bin/ or other Claude Code-only parts in this version" {
	for key in hooks mcpServers lspServers monitors channels experimental userConfig commands agents; do
		[ "$(jq "has(\"$key\")" "$MANIFEST")" = false ] || { echo "manifest has $key"; return 1; }
	done
	for path in hooks .mcp.json .lsp.json bin monitors agents; do
		[ ! -e "$PLUGIN/$path" ] || { echo "plugin has $path"; return 1; }
	done
}

@test "hygiene: regular files only, no system files, under 512 files, each under 256 KiB" {
	[ -z "$(find "$PLUGIN" -type l)" ]
	[ -z "$(find "$PLUGIN" \( -name .DS_Store -o -name Thumbs.db -o -name desktop.ini -o -name __MACOSX \
		-o -name .gitattributes -o -name .gitmodules -o -name .npmrc -o -name bunfig.toml -o -name uv.toml \
		-o -name package.json -o -name '*.mcpb' -o -name '*.dxt' \))" ]
	[ "$(find "$PLUGIN" -type f | wc -l)" -lt 512 ]
	[ -z "$(find "$PLUGIN" -type f -size +255k)" ]
	# Committed as regular files, not LFS pointers or submodules.
	run git -C "$ROOT" ls-files -s -- plugin
	[ "$status" -eq 0 ]
	[[ "$output" != *"120000 "* ]]
	[[ "$output" != *"160000 "* ]]
	[ -z "$(git -C "$ROOT" grep -l '^version https://git-lfs' -- plugin || true)" ]
}

@test "file and folder names work on Windows and macOS" {
	cd "$ROOT"
	# Folders on the path: letters, digits, dots, hyphens, underscores.
	[ -z "$(find plugin -type d | grep -v '^[A-Za-z0-9._/-]*$' || true)" ]
	# No colon, no trailing dot or space, no device names.
	[ -z "$(find plugin | grep -E ':|[. ]$|(^|/)(con|prn|aux|nul|com[0-9]|lpt[0-9])(\.[^/]*)?$' || true)" ]
	# No two names that differ only by case.
	[ -z "$(find plugin | tr '[:upper:]' '[:lower:]' | sort | uniq -d)" ]
}

@test "README: at least 40 words outside code blocks; LICENSE is the repository's" {
	words=$(awk '/^```/ { fence = !fence; next } !fence' "$PLUGIN/README.md" | wc -w)
	[ "$words" -ge 40 ]
	cmp "$PLUGIN/LICENSE" "$ROOT/LICENSE"
}

@test "each skill: SKILL.md with spec-only frontmatter, its folder's name, and one plain description" {
	n=0
	for dir in "$PLUGIN"/skills/*/; do
		skill=$(basename "$dir")
		file="$dir/SKILL.md"
		[ -f "$file" ] || { echo "$skill: no SKILL.md"; return 1; }
		[ "$(sed -n 1p "$file")" = --- ] || { echo "$skill: frontmatter must open on line 1"; return 1; }
		front=$(sed -n '2,/^---$/p' "$file" | sed '$d')
		[ -n "$front" ]
		while IFS= read -r line; do
			key=${line%%:*}
			[[ "$SPEC_KEYS" == *" $key "* ]] || { echo "$skill: key '$key' is not in the spec"; return 1; }
			value=${line#*: }
			# A plain YAML scalar on one line: no ": " or " #" inside, no quote or
			# indicator first, so every YAML parser reads it the same way.
			[[ "$value" != *": "* && "$value" != *" #"* ]] || { echo "$skill: $key needs quoting"; return 1; }
			[[ "$value" != [\"\'\[\{\&\*\!\|\>%@\`]* ]] || { echo "$skill: $key starts with an indicator"; return 1; }
		done <<<"$front"
		[ "$(grep -c '^name: ' <<<"$front")" -eq 1 ]
		[ "$(sed -n 's/^name: //p' <<<"$front")" = "$skill" ]
		description=$(sed -n 's/^description: //p' <<<"$front")
		[ -n "$description" ]
		[ "${#description}" -le 1536 ]
		n=$((n + 1))
	done
	[ "$n" -eq 4 ]
}

@test "each skill's reference files exist, and each one is named in its SKILL.md" {
	for dir in "$PLUGIN"/skills/*/; do
		while IFS= read -r ref; do
			[ -f "$dir/$ref" ] || { echo "$dir: $ref is missing"; return 1; }
		done < <(grep -o 'references/[A-Za-z0-9._-]*' "$dir/SKILL.md" | sort -u)
		if [ -d "$dir/references" ]; then
			for ref in "$dir"/references/*; do
				grep -q "references/$(basename "$ref")" "$dir/SKILL.md" ||
					{ echo "$ref is never named"; return 1; }
			done
		fi
	done
}

@test "every \${CLAUDE_PLUGIN_ROOT} path exists; every script is used and named in the README" {
	cd "$PLUGIN"
	while IFS= read -r path; do
		[ -f "${path#\$\{CLAUDE_PLUGIN_ROOT\}/}" ] || { echo "missing: $path"; return 1; }
	done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' skills | sort -u)
	for script in scripts/*; do
		grep -rqF "\${CLAUDE_PLUGIN_ROOT}/$script" skills || { echo "$script: no skill uses it"; return 1; }
		grep -qF "$script" README.md || { echo "$script: the README does not name it"; return 1; }
	done
}

@test "the scripts are plain shell and pass shellcheck" {
	for script in "$PLUGIN"/scripts/*; do
		first=$(sed -n 1p "$script")
		[ "$first" = "#!/bin/sh" ] || [ "$first" = "#!/bin/bash" ] || { echo "$script: $first"; return 1; }
	done
	shellcheck "$PLUGIN"/scripts/*
}

@test "every git and gh command a skill names is in the README's table" {
	cd "$PLUGIN"
	# Commands as the skills write them: in inline code, or on an indented
	# code line.
	n=0
	while IFS= read -r cmd; do
		n=$((n + 1))
		case $cmd in
		"gh "*) grep -qF "\`$cmd" README.md || { echo "README does not name: $cmd"; return 1; } ;;
		"git "*) grep -qE "\`(git )?${cmd#git }\b" README.md || { echo "README does not name: $cmd"; return 1; } ;;
		esac
	done < <(grep -hoE '(`|^[[:space:]]{4,})(gh (pr|run|issue|label|api|repo) [a-z-]+|git [a-z][a-z-]+)' skills/*/SKILL.md |
		sed -E 's/^(`|[[:space:]]+)//' | sort -u)
	[ "$n" -ge 10 ]
	grep -qF '`claude -p' README.md
}

@test "no launchers, no package installs run by the plugin, no credentials anywhere" {
	cd "$PLUGIN"
	run grep -rnE '\b(npx|bunx|uvx|pnpm dlx|yarn dlx|pipx run|uv run)\b' .
	[ "$status" -eq 1 ]
	run grep -rnE 'ghp_[A-Za-z0-9]{20}|gho_[A-Za-z0-9]{20}|github_pat_|sk-ant-|AKIA[0-9A-Z]{16}|xox[baprs]-|-----BEGIN [A-Z ]*PRIVATE KEY' .
	[ "$status" -eq 1 ]
	# Never read a credential from the user's environment.
	run grep -rnE '\$\{?(GITHUB_TOKEN|GH_TOKEN|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN)' .
	[ "$status" -eq 1 ]
}

@test "no Liquid tags in the plugin's Markdown or its docs page (the site renders them)" {
	run grep -rnE '\{\{|\{%' "$PLUGIN" --include='*.md' "$ROOT/docs/plugin.md"
	[ "$status" -eq 1 ]
}

@test "the texts the plugin carries are the repository's, unchanged" {
	cmp "$PLUGIN/scripts/gh-desk" "$ROOT/desk/gh-desk"
	cmp "$PLUGIN/scripts/cloud-setup.sh" "$ROOT/runners/claude-code-cloud/setup.sh"
	cmp "$PLUGIN/skills/brief-worker/references/brief-template.md" "$ROOT/prompts/en/brief.md"
	cmp "$PLUGIN/skills/start-cloud-worker/references/worker-opening.md" "$ROOT/prompts/en/worker-opening.md"
}

@test "claude plugin validate --strict passes, when the CLI is here" {
	command -v claude >/dev/null 2>&1 || skip "no claude CLI; the plugin job in CI runs it"
	run claude plugin validate "$PLUGIN" --strict
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Validation passed"* ]]
}
