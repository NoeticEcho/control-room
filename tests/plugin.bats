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
	run grep -rnE '\{\{|\{%' "$PLUGIN" --include='*.md' "$ROOT"/docs/plugin*.md
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

@test "the icon: a square vector SVG of at least 128 px, self-contained, named nowhere in the plugin" {
	icon="$PLUGIN/.claude-plugin/icon.svg"
	[ -f "$icon" ]
	head -c 200 "$icon" | grep -q '^<svg xmlns="http://www.w3.org/2000/svg"'
	width=$(sed -n 's/^<svg[^>]* width="\([0-9]*\)".*/\1/p' "$icon")
	height=$(sed -n 's/^<svg[^>]* height="\([0-9]*\)".*/\1/p' "$icon")
	[ -n "$width" ] && [ "$width" = "$height" ]
	[ "$width" -ge 128 ]
	grep -q "viewBox=\"0 0 $width $height\"" "$icon"
	# Vector only, no embedded raster, script, font or outside reference.
	run grep -nE '<image|data:|href=|<script|<text|<foreignObject|url\(|@import|on[a-z]+=' "$icon"
	[ "$status" -eq 1 ]
	# The checklist holds a plugin that names a bundled image in commands,
	# scripts or code; nothing needs to.
	run grep -rn 'icon\.svg' "$PLUGIN" --exclude=icon.svg
	[ "$status" -eq 1 ]
}

@test "credentials: the scripts read no variable but their own settings, and nothing in a home directory" {
	cd "$PLUGIN/scripts"
	# Every upper-case variable a script expands; lower-case ones are its own.
	# shellcheck disable=SC2016 # the patterns are literal
	used=$(grep -ohE '\$\{?[A-Z][A-Z0-9_]*' ./* | tr -d '${' | sort -u | tr '\n' ' ')
	[ "$used" = "CLAUDE_PLUGIN_ROOT CR_PROFILE GH_DESK_NOW GH_DESK_REPO " ] ||
		[ "$used" = "CR_PROFILE GH_DESK_NOW GH_DESK_REPO " ] || { echo "reads: $used"; return 1; }
	# shellcheck disable=SC2016,SC2088 # the patterns are literal
	run grep -nE '~/|\$HOME|\.config/|\.netrc|\.git-credentials|hosts\.yml|auth (token|status)|gh auth|curl |wget ' ./*
	[ "$status" -eq 1 ]
	# ready-check needs no sign-in: it runs neither gh nor anything on the network.
	# (Comments and the messages that tell the user to fetch do not count.)
	run sh -c "grep -vE '^[[:space:]]*#|die \"|finding \"|printf ' ready-check |
		grep -nwE 'gh|curl|wget|ssh|git (fetch|push|pull|ls-remote|clone)'"
	[ "$status" -eq 1 ]
}

@test "credentials: with canary tokens in the environment, no script passes one to gh or prints it" {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	cat >"$bin/gh" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in *"issue list"*) echo '[]' ;; esac
EOS
	chmod +x "$bin/gh"
	export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
	canary='canary-f1e2d3c4b5a6'
	run env PATH="$bin:$PATH" HOME=/nonexistent GH_TOKEN=$canary GITHUB_TOKEN=$canary \
		GH_DESK_REPO=owner/repo sh "$PLUGIN/scripts/gh-desk"
	[ "$status" -eq 0 ]
	[[ "$output" != *"$canary"* ]]
	run env PATH="$bin:$PATH" HOME=/nonexistent GH_TOKEN=$canary GH_DESK_REPO=owner/repo \
		sh "$PLUGIN/scripts/gh-desk" labels
	[ "$status" -eq 0 ]
	[ -s "$GH_LOG" ]
	run grep -c "$canary" "$GH_LOG"
	[ "$output" = 0 ]
	# Every gh call names the repository it was given, and no other.
	run grep -vc -- '-R owner/repo$' "$GH_LOG"
	[ "$output" = 0 ]
}

@test "the README's Credentials section names each tool that uses a sign-in, and what it sends where" {
	section=$(awk '/^## Credentials/ { on = 1; next } /^## / { on = 0 } on' "$PLUGIN/README.md")
	[ -n "$section" ]
	# shellcheck disable=SC2016 # backticks are Markdown, not commands
	for needle in '`gh`' '`git push' '`claude -p' 'scripts/gh-desk' 'scripts/ready-check' 'no `userConfig`' 'reads no credential'; do
		[[ "$section" == *"$needle"* ]] || { echo "Credentials does not say: $needle"; return 1; }
	done
	[ "$(jq 'has("userConfig")' "$MANIFEST")" = false ]
}

@test "the listing links: https, and each page on the docs site is a page in this repository" {
	site=https://open.noeticecho.space/control-room/
	for field in homepage documentationUrl supportUrl privacyPolicyUrl termsOfServiceUrl; do
		url=$(jq -r ".$field // empty | strings" "$MANIFEST")
		[[ "$url" == https://* ]] || { echo "$field: '$url'"; return 1; }
		if [[ "$url" == "$site"* ]]; then
			page=${url#"$site"}
			[ -f "$ROOT/${page%.html}.md" ] || { echo "$field: no ${page%.html}.md for $url"; return 1; }
		fi
	done
	[ "$(jq -r .documentationUrl "$MANIFEST")" = "$(jq -r .homepage "$MANIFEST")" ]
	[ "$(jq -r .supportUrl "$MANIFEST")" = https://github.com/NoeticEcho/control-room/issues ]
}

@test "classification: an object with only the keys the portal accepts, each of its shape" {
	# The portal (2026-09-30): object_acted_on a list of strings; work_department,
	# industry, life_area and subject one string each; no other key.
	jq -e '.classification | type == "object" and length > 0' "$MANIFEST" >/dev/null
	extra=$(jq -r '.classification | keys[] | select(IN("object_acted_on", "work_department", "industry", "life_area", "subject") | not)' "$MANIFEST")
	[ -z "$extra" ] || { echo "not accepted: $extra"; return 1; }
	jq -e '.classification | (.object_acted_on // ["x"]) | type == "array" and length > 0 and all(type == "string" and length > 0)' "$MANIFEST" >/dev/null
	for key in work_department industry life_area subject; do
		jq -e --arg k "$key" '.classification | (has($k) | not) or (.[$k] | type == "string" and length > 0)' "$MANIFEST" >/dev/null ||
			{ echo "$key must be one non-empty string"; return 1; }
	done
}

@test "the privacy and terms pages say what the listing promises, and the docs page says how support works" {
	privacy=$(tr '\n' ' ' <"$ROOT/docs/plugin-privacy.md")
	for needle in "collects nothing and sends nothing to NoeticEcho" "no telemetry" "privacy statement" "privacy policy"; do
		[[ "$privacy" == *"$needle"* ]] || { echo "privacy page does not say: $needle"; return 1; }
	done
	terms=$(tr '\n' ' ' <"$ROOT/docs/plugin-terms.md")
	for needle in "Apache License 2.0" "No warranty" "section 7" "No liability" "section 8" "No service" "the licence is what counts"; do
		[[ "$terms" == *"$needle"* ]] || { echo "terms page does not say: $needle"; return 1; }
	done
	support=$(awk '/^## Support/ { on = 1; next } /^## / { on = 0 } on' "$ROOT/docs/plugin.md")
	[[ "$support" == *"https://github.com/NoeticEcho/control-room/issues"* ]]
	[[ "$support" == *"no promised response time"* ]]
}

@test "classification: every value is one the portal's taxonomy accepts" {
	# The portal's Validate (2026-10-01) drops a value outside its lists and says
	# so; these are the lists it printed. A new value is checked there first.
	objects='["code","databases","servers-cloud","logs-errors","files-documents","ai-models-agents","pipelines-jobs","websites","finances","tickets-tasks","email-messages","designs-media","reference-docs","dependencies-packages","music-podcasts","papers-articles","notes-memory","books","contacts-leads","pull-requests","problems-puzzles","courses-lessons","events-tickets","apis","claude-history","claude-settings","recipes-meals","workouts-health-records","trips"]'
	industries='["health-life-sciences","financial-services","education","nonprofit","retail-ecommerce","travel-hospitality","media-entertainment","government","legal","real-estate","energy","manufacturing","transportation-logistics","utilities","agriculture","mining","construction","telecommunications","insurance","research-academia","events","fitness-wellness","agencies-staffing","software-saas"]'
	subjects='["medicine","science","maths","languages","history","philosophy-religion","the-arts","computing","engineering","law","economics","politics-government","psychology","sociology-anthropology","geography","business-management","education"]'
	jq -e --argjson ok "$objects" '.classification.object_acted_on | all(. as $v | $ok | index($v))' "$MANIFEST" >/dev/null
	jq -e --argjson ok "$industries" '.classification | (has("industry") | not) or (.industry as $v | $ok | index($v))' "$MANIFEST" >/dev/null
	jq -e --argjson ok "$subjects" '.classification | (has("subject") | not) or (.subject as $v | $ok | index($v))' "$MANIFEST" >/dev/null
}
