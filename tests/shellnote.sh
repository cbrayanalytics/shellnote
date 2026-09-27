#!/usr/bin/env bash
set -eu
set -o pipefail

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
app="$project_dir/bin/shellnote"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/shellnote-tests.XXXXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
original_path=$PATH
real_nvim=$(command -v nvim)
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Shellnote Test' GIT_AUTHOR_EMAIL='test@example.invalid'
export GIT_COMMITTER_NAME='Shellnote Test' GIT_COMMITTER_EMAIL='test@example.invalid'
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_equal() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
run() {
    result=0
    "$BASH" "$app" "$@" < /dev/null > "$case_dir/stdout" 2> "$case_dir/stderr" || result=$?
}
run_input() {
    local input=$1
    shift
    result=0
    printf '%s' "$input" | "$BASH" "$app" "$@" > "$case_dir/stdout" 2> "$case_dir/stderr" || result=$?
}
captures() { find "$NOTES_DIR" -name '.capture.*'; }
run_tty() {
    result=0
    # script fails when its own stdin is a socket, as under some agent or CI runners.
    NO_COLOR=1 TERM=xterm script -q "$case_dir/tty-output" "$BASH" "$app" "$@" < /dev/null > /dev/null 2> "$case_dir/stderr" || result=$?
}
success() { [ "$result" = 0 ] || { cat "$case_dir/stderr" >&2; fail "exit $result"; }; }
failure() { [ "$result" != 0 ] || fail 'unexpected success'; }
contains() { rg -q -- "$2" "$1" || fail "missing pattern: $2"; }
notes() { find "$NOTES_DIR" -type f -name '*.md'; }
editor_args() {
    editor_values=()
    while IFS= read -r -d '' arg; do editor_values+=("$arg"); done < "$TEST_EDITOR_ARGS"
    editor_last=${editor_values[${#editor_values[@]}-1]}
}
setup() {
    case_dir="$test_root/$1"
    mkdir -m 700 "$case_dir" "$case_dir/tools"
    ln -s "$project_dir/tests/helpers/nvim" "$case_dir/tools/nvim"
    ln -s "$project_dir/tests/helpers/fzf" "$case_dir/tools/fzf"
    export NOTES_DIR="$case_dir/notes" TEST_EDITOR_ARGS="$case_dir/editor-args"
    export TEST_PICKER_ARGS="$case_dir/picker-args" TEST_PICKER_ROWS="$case_dir/picker-rows"
    export NVIM_LOG_FILE="$case_dir/nvim.log"
    export PATH="$case_dir/tools:$original_path"
    unset TEST_EDITOR_STATUS TEST_EDITOR_CHMOD NOTE_EMOJI NO_COLOR
    unset TEST_EDITOR_REPLACE_PARENT
    unset TEST_PICKER_MODE TEST_PICKER_MATCH FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND RIPGREP_CONFIG_PATH
}

test_init_permissions() {
    run init; success
    assert_equal 700 "$(mode "$NOTES_DIR")"
}
test_new_note() {
    run new 'Meeting notes'; success
    editor_args
    assert_equal 600 "$(mode "$editor_last")"
    assert_equal '# Meeting notes' "$(head -n 1 "$editor_last")"
    case "$editor_last" in "$NOTES_DIR"/*.md) ;; *) fail 'note outside storage';; esac
}
test_repeated_title() {
    run new repeat; success
    editor_args; first_note=$editor_last
    printf 'Keep this\n' >> "$first_note"
    run new repeat; success
    editor_args
    [ "$first_note" != "$editor_last" ] || fail 'filename collision'
    contains "$first_note" 'Keep this'
}
test_unquoted_words() {
    run new case 04512 nginx 502s; success
    editor_args
    assert_equal '# case 04512 nginx 502s' "$(head -n 1 "$editor_last")"
}
test_command_options() {
    run new -h; success
    contains "$case_dir/stdout" 'usage: shellnote new'
    run find --help; success
    run new --bogus title; failure
    contains "$case_dir/stderr" 'unknown option'
    run list --print; failure
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'option was treated as a title'
    [ ! -e "$NOTES_DIR" ] || fail 'option handling created storage'
}
test_unicode_title() {
    run new 'Café 🌱'; success
    editor_args
    assert_equal '# Café 🌱' "$(head -n 1 "$editor_last")"
}
test_editor_arguments() {
    # Literal shell syntax must reach the heading without execution.
    # shellcheck disable=SC2016
    title='-Meeting "quotes" $(touch PWNED) `touch PWNED`'
    run new -- "$title"; success
    editor_args
    assert_equal "# $title" "$(head -n 1 "$editor_last")"
    [ ! -e "$NOTES_DIR/PWNED" ] || fail 'executed title'
    printf '%s\n' "${editor_values[@]}" | rg -q '^--$' || fail 'missing option boundary'
    printf '%s\n' "${editor_values[@]}" | rg -q 'noundofile' || fail 'persistent undo enabled'
}
test_editor_failure_preserves_note() {
    export TEST_EDITOR_STATUS=7 TEST_EDITOR_CHMOD=1
    run new retained
    assert_equal 7 "$result"
    editor_args
    [ -f "$editor_last" ] || fail 'lost note'
    assert_equal 600 "$(mode "$editor_last")"
}
test_storage_symlink_rejected() {
    mkdir -m 700 "$case_dir/target"
    ln -s "$case_dir/target" "$NOTES_DIR"
    run new blocked; failure
    contains "$case_dir/stderr" 'symlink'
    [ -z "$(find "$case_dir/target" -type f)" ] || fail 'wrote through symlink'
}
test_permissive_storage_rejected() {
    mkdir -m 755 "$NOTES_DIR"
    run init; failure
    contains "$case_dir/stderr" '0700|700'
    assert_equal 755 "$(mode "$NOTES_DIR")"
}
test_help_without_dependencies() {
    export PATH="$case_dir/tools"
    run --help; success
    [ ! -e "$NOTES_DIR" ] || fail 'help created storage'
}
test_invalid_arguments() {
    run new ''; failure
    run new $'two\nlines'; failure
    run init unexpected; failure
    run unknown; failure
    contains "$case_dir/stderr" 'unknown command'
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'invalid command edited a note'
}
test_real_nvim_privacy() {
    ln -sf "$project_dir/tests/helpers/nvim-real" "$case_dir/tools/nvim"
    export TEST_REAL_NVIM="$real_nvim" TEST_NVIM_CONFIG="$project_dir/tests/helpers/privacy.vim"
    export TEST_NVIM_RESULT="$case_dir/nvim-result"
    run new Real; success
    assert_equal $'0\n0\n0\n0' "$(head -n 4 "$TEST_NVIM_RESULT")"
    assert_equal '' "$(sed -n '5p' "$TEST_NVIM_RESULT")"
    assert_equal 1 "$(sed -n '6p' "$TEST_NVIM_RESULT")"
    assert_equal 1 "$(find "$NOTES_DIR" -type f | wc -l | tr -d ' ')"
}
test_missing_editor_creates_nothing() {
    rm "$case_dir/tools/nvim"
    export PATH="$case_dir/tools"
    run new Missing; failure
    [ ! -e "$NOTES_DIR" ] || fail 'missing editor created storage'
    export PATH="$original_path"
    contains "$case_dir/stderr" 'nvim'
}
fixture_note() {
    mkdir -p "$NOTES_DIR"
    chmod 700 "$NOTES_DIR"
    printf '%s\n' "$2" > "$NOTES_DIR/$1"
    chmod 600 "$NOTES_DIR/$1"
}
test_browse_selection() {
    fixture_note first.md 'First note'
    fixture_note second.md 'Second note'
    export TEST_PICKER_MATCH=second.md
    run; success; editor_args
    assert_equal "$NOTES_DIR/second.md" "$editor_last"
}
test_list_notes() {
    fixture_note first.md $'# First note\n#work'
    fixture_note second.md $'# Second note\n#home'
    touch -t 202601010000 "$NOTES_DIR/first.md"
    touch -t 202602010000 "$NOTES_DIR/second.md"
    run list; success
    assert_equal $'Second note\tsecond.md\nFirst note\tfirst.md' "$(cat "$case_dir/stdout")"
    run list --tag work; success
    assert_equal $'First note\tfirst.md' "$(cat "$case_dir/stdout")"
    run list -t work; success
    assert_equal $'First note\tfirst.md' "$(cat "$case_dir/stdout")"
    run list --tag absent; success
    assert_equal '' "$(cat "$case_dir/stdout")"
}
test_browse_recent_titles() {
    fixture_note a.md '# Older case'
    fixture_note b.md 'untitled'
    touch -t 202601010000 "$NOTES_DIR/a.md"
    touch -t 202602010000 "$NOTES_DIR/b.md"
    export TEST_PICKER_MATCH=nothing
    run; success
    assert_equal $'1\tb.md\n2\tOlder case  (a.md)' "$(cat "$TEST_PICKER_ROWS")"
}
test_list_empty() {
    run list; success
    assert_equal '' "$(cat "$case_dir/stdout")"
}
test_literal_search() {
    fixture_note one.md $'No match\nDeploy [v1].*\nOther'
    fixture_note two.md 'Deploy v123'
    run find '[v1].*'; success; editor_args
    assert_equal "$NOTES_DIR/one.md" "$editor_last"
    printf '%s\n' "${editor_values[@]}" | rg -q '^\+2$' || fail 'wrong matching line'
    [ "$(wc -l < "$TEST_PICKER_ROWS" | tr -d ' ')" = 1 ] || fail 'regex search instead of literal'
}
test_print_search() {
    fixture_note one.md $'No match\nneedle here'
    fixture_note two.md 'needle too'
    run find --print needle; success
    assert_equal $'one.md:2: needle here\ntwo.md:1: needle too' "$(cat "$case_dir/stdout")"
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'print search opened editor'
}
test_smart_case_search() {
    fixture_note one.md 'Connection Refused on port 22'
    run find --print connection refused; success
    assert_equal 'one.md:1: Connection Refused on port 22' "$(cat "$case_dir/stdout")"
    run find -p Connection refused; success
    assert_equal '' "$(cat "$case_dir/stdout")"
    fixture_note two.md 'run --force now'
    run find -p -- --force; success
    assert_equal 'two.md:1: run --force now' "$(cat "$case_dir/stdout")"
}
test_piped_search_prints() {
    fixture_note one.md 'needle here'
    result=0
    "$BASH" "$app" find needle < /dev/null 2> "$case_dir/stderr" | cat > "$case_dir/stdout" || result=$?
    success
    assert_equal 'one.md:1: needle here' "$(cat "$case_dir/stdout")"
    [ ! -e "$TEST_PICKER_ARGS" ] || fail 'piped search opened picker'
}
test_short_commands() {
    fixture_note a.md $'# Case 04512 nginx\nneedle'
    run s 04512; success
    contains "$case_dir/stdout" 'Case 04512 nginx'
    run f -p needle; success
    assert_equal 'a.md:2: needle' "$(cat "$case_dir/stdout")"
    run l; success
    assert_equal $'Case 04512 nginx\ta.md' "$(cat "$case_dir/stdout")"
    run e nginx; success; editor_args
    assert_equal "$NOTES_DIR/a.md" "$editor_last"
    run_input 'out' a 04512; success
    contains "$NOTES_DIR/a.md" '^out$'
}
test_completion_words() {
    run __complete titles; success
    assert_equal '' "$(cat "$case_dir/stdout")"
    [ ! -e "$NOTES_DIR" ] || fail 'completion created storage'
    fixture_note a.md $'# Alpha\n#work #home'
    fixture_note b.md 'untitled #work'
    touch -t 202601010000 "$NOTES_DIR/a.md"
    touch -t 202602010000 "$NOTES_DIR/b.md"
    run __complete titles; success
    assert_equal $'b.md\nAlpha' "$(cat "$case_dir/stdout")"
    run __complete tags; success
    assert_equal $'home\nwork' "$(cat "$case_dir/stdout")"
}
# Literal $(...) titles must never run during completion.
# shellcheck disable=SC2016
test_bash_completion() {
    fixture_note a.md $'# Case 04512 $(touch PWNED) nginx\n#work'
    fixture_note b.md $'# Other\n#home'
    export PATH="$project_dir/bin:$PATH"
    # shellcheck source=completions/shellnote.bash
    . "$project_dir/completions/shellnote.bash"
    COMP_WORDS=(sn sy); COMP_CWORD=1; _shellnote
    assert_equal sync "${COMPREPLY[*]}"
    COMP_WORDS=(sn e 04512); COMP_CWORD=2; _shellnote
    assert_equal 1 "${#COMPREPLY[@]}"
    assert_equal '# Case 04512 $(touch PWNED) nginx' "# $(eval "printf '%s' ${COMPREPLY[0]}")"
    COMP_WORDS=(sn e 'case\ 04'); COMP_CWORD=2; _shellnote
    assert_equal 1 "${#COMPREPLY[@]}"
    COMP_WORDS=(sn l -t ''); COMP_CWORD=3; _shellnote
    assert_equal 'home work' "${COMPREPLY[*]}"
    COMP_WORDS=(sn t w); COMP_CWORD=2; _shellnote
    assert_equal work "${COMPREPLY[*]}"
    COMP_WORDS=(sn f -); COMP_CWORD=2; _shellnote
    assert_equal '-p --print' "${COMPREPLY[*]}"
    [ ! -e "$NOTES_DIR/PWNED" ] && [ ! -e PWNED ] || fail 'completion executed a title'
}
test_zsh_completion_syntax() {
    command -v zsh >/dev/null || return 0
    zsh -n "$project_dir/completions/_shellnote" || fail 'zsh completion syntax'
}
test_print_search_tty() {
    fixture_note one.md $'# One\n\n## Cleanup\nneedle here'
    fixture_note two.md 'needle too'
    run_tty find --print needle; success
    contains "$case_dir/tty-output" '# One'
    contains "$case_dir/tty-output" '## Cleanup'
    contains "$case_dir/tty-output" '  4  needle here'
    if rg -q 'one.md:4:' "$case_dir/tty-output"; then fail 'tty search repeated the path'; fi
    run_tty find --print Cleanup; success
    contains "$case_dir/tty-output" '## Cleanup'
    if rg -q '  3  ## Cleanup' "$case_dir/tty-output"; then fail 'tty search repeated a section heading'; fi
    fixture_note three.md $'needle\033]52;c;payload\007 end'
    run_tty find --print needle; success
    if LC_ALL=C rg -q $'[\033\007]' "$case_dir/tty-output"; then fail 'tty search emitted terminal controls'; fi
}
test_show_note() {
    fixture_note one.md $'# One\n\nVisible text'
    run show one.md; success
    assert_equal $'# One\n\nVisible text' "$(cat "$case_dir/stdout")"
    run show ../outside.md; failure
}
test_new_from_pipe() {
    run_input $'Active: failed\n```inner```' new case 04512 status; success
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'piped new opened editor'
    note=$(notes)
    assert_equal 600 "$(mode "$note")"
    assert_equal $'# case 04512 status\n\n````\nActive: failed\n```inner```\n````' "$(cat "$note")"
    contains "$case_dir/stdout" 'Created: '
    run_input '' new empty; failure
    contains "$case_dir/stderr" 'no input'
    assert_equal 1 "$(notes | wc -l | tr -d ' ')"
    assert_equal '' "$(captures)"
}
test_add_from_pipe() {
    fixture_note a.md '# Case 04512 nginx'
    fixture_note b.md $'# Case 04513 disk\nno newline'
    printf 'tail' >> "$NOTES_DIR/b.md"
    touch -t 202601010000 "$NOTES_DIR/a.md"
    touch -t 202602010000 "$NOTES_DIR/b.md"
    run_input $'df output\n' add; success
    assert_equal $'# Case 04513 disk\nno newline\ntail\n\n```\ndf output\n```' "$(cat "$NOTES_DIR/b.md")"
    contains "$case_dir/stdout" 'Added to: Case 04513 disk'
    run_input 'nginx -t' add 04512; success
    assert_equal $'# Case 04512 nginx\n\n```\nnginx -t\n```' "$(cat "$NOTES_DIR/a.md")"
    run add 04512; failure
    contains "$case_dir/stderr" 'COMMAND \| shellnote add'
    run_input 'x' add absent; failure
    run_input '' add 04512; failure
    assert_equal $'# Case 04512 nginx\n\n```\nnginx -t\n```' "$(cat "$NOTES_DIR/a.md")"
    assert_equal 600 "$(mode "$NOTES_DIR/a.md")"
    assert_equal '' "$(captures)"
}
test_last_note() {
    run last; failure
    fixture_note a.md '# Older'
    fixture_note b.md '# Newer'
    touch -t 202601010000 "$NOTES_DIR/a.md"
    touch -t 202602010000 "$NOTES_DIR/b.md"
    run last; success; editor_args
    assert_equal "$NOTES_DIR/b.md" "$editor_last"
    printf '%s\n' "${editor_values[@]}" | rg -qx '\+\$' || fail 'last did not open at the end'
    [ ! -e "$TEST_PICKER_ROWS" ] || fail 'last opened picker'
}
test_match_notes() {
    fixture_note 20260101T000000Z-case.a.md $'# Case 04512 nginx 502s\nbody'
    fixture_note 20260102T000000Z-case.b.md '# Case 04513 disk full'
    run show 04512 NGINX; success
    assert_equal $'# Case 04512 nginx 502s\nbody' "$(cat "$case_dir/stdout")"
    run show 04513 nginx; failure
    contains "$case_dir/stderr" 'no note matches'
    run edit disk; success; editor_args
    assert_equal "$NOTES_DIR/20260102T000000Z-case.b.md" "$editor_last"
    [ ! -e "$TEST_PICKER_ROWS" ] || fail 'unique match opened picker'
    export TEST_PICKER_MATCH=04512
    run edit case; success; editor_args
    assert_equal "$NOTES_DIR/20260101T000000Z-case.a.md" "$editor_last"
    assert_equal 2 "$(wc -l < "$TEST_PICKER_ROWS" | tr -d ' ')"
}
test_tags_exact() {
    fixture_note work.md $'# Heading\n#work, #work #work\n```\n#code\n```'
    fixture_note other.md '#workshop #Work email#work #work-extra'
    run tags work; success; editor_args
    assert_equal "$NOTES_DIR/work.md" "$editor_last"
    assert_equal 1 "$(wc -l < "$TEST_PICKER_ROWS" | tr -d ' ')"
    run tags code; success; editor_args
    assert_equal "$NOTES_DIR/work.md" "$editor_last"
    run tags; success
    contains "$TEST_PICKER_ROWS" '#Work'
    if rg -q '#Heading' "$TEST_PICKER_ROWS"; then fail 'heading treated as tag'; fi
}
test_empty_and_cancelled_picker() {
    run; success
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'empty picker opened editor'
    fixture_note one.md 'Text'
    run find absent; success
    export TEST_PICKER_MODE=cancel
    run; success
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'cancel opened editor'
}
test_unusual_filenames() {
    filename=$'-odd\tline\n"quote" $(touch PWNED).md'
    fixture_note "$filename" 'needle'
    run find needle; success; editor_args
    assert_equal "$NOTES_DIR/$filename" "$editor_last"
    assert_equal 1 "$(wc -l < "$TEST_PICKER_ROWS" | tr -d ' ')"
    [ ! -e "$NOTES_DIR/PWNED" ] || fail 'filename executed'
}
test_private_search_only() {
    fixture_note good.md 'visible'
    fixture_note bad.md 'hidden'
    chmod 644 "$NOTES_DIR/bad.md"
    run find hidden; failure
    [ ! -e "$TEST_PICKER_ROWS" ] || fail 'private check came after picker'
    rm "$NOTES_DIR/bad.md"
    mkdir -m 700 "$case_dir/outside" "$NOTES_DIR/.git"
    printf 'hidden\n' > "$case_dir/outside/secret.md"
    printf 'hidden\n' > "$NOTES_DIR/.git/secret.md"
    ln -s "$case_dir/outside/secret.md" "$NOTES_DIR/link.md"
    ln -s "$case_dir/outside" "$NOTES_DIR/linked"
    run find hidden; success
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'opened hidden or linked file'
}
test_sanitized_preview() {
    fixture_note one.md $'safe\033]52;c;payload\007\nnext'
    printf '%s\0%s\0' "$NOTES_DIR/one.md" 1 > "$case_dir/map"
    chmod 600 "$case_dir/map"
    run __preview "$case_dir/map" 1; success
    contains "$case_dir/stdout" safe
    if LC_ALL=C rg -q $'[\033\007]' "$case_dir/stdout"; then fail 'terminal controls emitted'; fi
}
test_environment_isolation() {
    fixture_note one.md 'needle'
    printf '%s\n' '--glob=*.excluded' > "$case_dir/rg-config"
    export RIPGREP_CONFIG_PATH="$case_dir/rg-config"
    export FZF_DEFAULT_OPTS='--history=/tmp/unwanted-shellnote-history' FZF_DEFAULT_COMMAND='false'
    export FZF_DEFAULT_OPTS_FILE="$case_dir/nonexistent-fzf-options"
    run find needle; success; editor_args
    assert_equal "$NOTES_DIR/one.md" "$editor_last"
}
test_no_color() {
    export NO_COLOR=1
    run init; success
    if LC_ALL=C rg -q $'\033' "$case_dir/stdout"; then fail 'color on redirected output'; fi
    fixture_note one.md text
    run; success
    tr '\0' '\n' < "$TEST_PICKER_ARGS" | rg -q -- '--no-color' || fail 'picker color enabled'
}
test_optional_emoji() {
    run init; success
    if rg -q '📝' "$case_dir/stdout"; then fail 'emoji on by default'; fi
    export NOTE_EMOJI=1
    run init; success
    contains "$case_dir/stdout" '📝'
}
test_picker_failure() {
    fixture_note one.md text
    export TEST_PICKER_MODE=fail
    run; failure
    contains "$case_dir/stderr" 'picker'
    [ ! -e "$TEST_EDITOR_ARGS" ] || fail 'failed picker opened editor'
}
test_editor_replaced_parent() {
    fixture_note seed.md seed
    mkdir -m 700 "$NOTES_DIR/sub" "$case_dir/outside"
    printf 'inside\n' > "$NOTES_DIR/sub/note.md"
    chmod 600 "$NOTES_DIR/sub/note.md"
    printf 'outside\n' > "$case_dir/outside/note.md"
    chmod 644 "$case_dir/outside/note.md"
    export TEST_PICKER_MATCH=sub/note.md TEST_EDITOR_REPLACE_PARENT="$case_dir/outside"
    run; failure
    assert_equal 644 "$(mode "$case_dir/outside/note.md")"
    assert_equal outside "$(cat "$case_dir/outside/note.md")"
}
test_editor_replaced_root() {
    fixture_note note.md inside
    mkdir -m 700 "$case_dir/outside"
    printf 'outside\n' > "$case_dir/outside/note.md"
    chmod 644 "$case_dir/outside/note.md"
    export TEST_EDITOR_REPLACE_PARENT="$case_dir/outside"
    run; failure
    assert_equal 644 "$(mode "$case_dir/outside/note.md")"
}
git_notes() { git -C "$NOTES_DIR" "$@"; }
test_git_init() {
    run init --git; success
    assert_equal "$NOTES_DIR" "$(git_notes rev-parse --show-toplevel)"
    assert_equal 700 "$(mode "$NOTES_DIR/.git")"
    assert_equal 600 "$(mode "$NOTES_DIR/.gitignore")"
    git_notes check-ignore -q example.swp || fail 'swap file not ignored'
    printf 'custom\n' > "$NOTES_DIR/.gitignore"
    run init --git; success
    assert_equal custom "$(cat "$NOTES_DIR/.gitignore")"
}
test_commit_notes() {
    run init --git; success
    fixture_note one.md '# One'
    fixture_note removed.md '# Removed'
    run commit 'First'; success
    assert_equal '# One' "$(git_notes show HEAD:one.md)"
    printf '# Updated\n' > "$NOTES_DIR/one.md"
    rm "$NOTES_DIR/removed.md"
    fixture_note 'literal[*].md' '# Literal'
    run commit 'Second'; success
    assert_equal '# Updated' "$(git_notes show HEAD:one.md)"
    assert_equal '# Literal' "$(git_notes show 'HEAD:literal[*].md')"
    if git_notes cat-file -e HEAD:removed.md 2>/dev/null; then fail 'deletion not committed'; fi
    assert_equal 2 "$(git_notes rev-list --count HEAD)"
    run commit 'No changes'; success
    assert_equal 2 "$(git_notes rev-list --count HEAD)"
    printf 'more\n' >> "$NOTES_DIR/one.md"
    run commit; success
    git_notes log -1 --format=%s | rg -q '^Notes [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC$' || fail 'missing default message'
}
test_sync_notes() {
    run init --git; success
    fixture_note one.md '# One'
    git init --bare -q "$case_dir/remote.git"
    git_notes remote add origin "$case_dir/remote.git"
    run sync; failure
    assert_equal 1 "$(git_notes rev-list --count HEAD)"
    branch=$(git_notes symbolic-ref --short HEAD)
    git_notes config "branch.$branch.remote" origin
    git_notes config "branch.$branch.merge" "refs/heads/$branch"
    run sync; success
    assert_equal "$(git_notes rev-parse HEAD)" "$(git --git-dir="$case_dir/remote.git" rev-parse "refs/heads/$branch")"
    printf 'two\n' >> "$NOTES_DIR/one.md"
    run sync second pass; success
    assert_equal 'second pass' "$(git --git-dir="$case_dir/remote.git" log -1 --format=%s "refs/heads/$branch")"
}
test_unrelated_staged_refused() {
    run init --git; success
    fixture_note one.md '# One'
    printf 'unrelated\n' > "$NOTES_DIR/private.txt"
    git_notes add private.txt
    run commit blocked; failure
    contains "$case_dir/stderr" 'unrelated'
    assert_equal private.txt "$(git_notes diff --cached --name-only)"
    if git_notes rev-parse --verify HEAD >/dev/null 2>&1; then fail 'committed unrelated file'; fi
}
test_untracked_unrelated_ignored() {
    run init --git; success
    fixture_note one.md '# One'
    printf 'unrelated\n' > "$NOTES_DIR/private.txt"
    run commit Notes; success
    assert_equal '?? private.txt' "$(git_notes status --short -- private.txt)"
}
test_parent_repository_rejected() {
    git init -q "$case_dir"
    run init; success
    run commit blocked; failure
    contains "$case_dir/stderr" 'root|init --git'
    run push; failure
    [ ! -e "$case_dir/.git/index" ] || fail 'modified parent index'
}
test_git_environment_isolation() {
    git init -q "$case_dir/outside"
    run init --git; success
    fixture_note one.md '# One'
    export GIT_DIR="$case_dir/outside/.git" GIT_WORK_TREE="$case_dir/outside"
    export GIT_INDEX_FILE="$case_dir/alternate-index"
    run commit Isolated; success
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    assert_equal '# One' "$(git_notes show HEAD:one.md)"
    [ ! -e "$case_dir/alternate-index" ] || fail 'used alternate index'
    [ ! -e "$case_dir/outside/.git/index" ] || fail 'modified outside repository'
}
test_push_local_remote() {
    run init --git; success
    fixture_note one.md '# One'
    run commit First; success
    git init --bare -q "$case_dir/remote.git"
    git_notes remote add origin "$case_dir/remote.git"
    branch=$(git_notes symbolic-ref --short HEAD)
    git_notes config "branch.$branch.remote" origin
    git_notes config "branch.$branch.merge" "refs/heads/$branch"
    run push; success
    assert_equal "$(git_notes rev-parse HEAD)" "$(git --git-dir="$case_dir/remote.git" rev-parse "refs/heads/$branch")"
}
test_push_missing_upstream() {
    run init --git; success
    fixture_note one.md '# One'
    run commit First; success
    run push; failure
    [ -z "$(git_notes remote)" ] || fail 'invented remote'
}
test_staged_symlink_refused() {
    run init --git; success
    fixture_note good.md '# Good'
    printf 'outside\n' > "$case_dir/outside"
    ln -s "$case_dir/outside" "$NOTES_DIR/link.md"
    git_notes add link.md
    run commit blocked; failure
    contains "$case_dir/stderr" 'symlink'
    if git_notes rev-parse --verify HEAD >/dev/null 2>&1; then fail 'committed symlink'; fi
}
test_unrelated_rename_refused() {
    run init --git; success
    printf 'Unrelated original\n' > "$NOTES_DIR/original.txt"
    chmod 600 "$NOTES_DIR/original.txt"
    git_notes add original.txt
    git_notes commit -qm Original
    git_notes mv original.txt renamed.md
    run commit blocked; failure
    contains "$case_dir/stderr" 'unrelated'
    assert_equal 1 "$(git_notes rev-list --count HEAD)"
}
test_git_literal_pathspec_environment() {
    run init --git; success
    fixture_note one.md '# One'
    export GIT_LITERAL_PATHSPECS=1
    run commit Literal; success
    assert_equal '# One' "$(git_notes show HEAD:one.md)"
}
test_git_icase_pathspec_environment() {
    run init --git; success
    fixture_note note.md '# Lower'
    git_notes config core.ignorecase false
    git_notes add note.md
    upper_blob=$(printf '# Upper\n' | git_notes hash-object -w --stdin)
    git_notes update-index --add --cacheinfo "100644,$upper_blob,note.MD"
    git_notes commit -qm Original
    printf '# Changed\n' > "$NOTES_DIR/note.md"
    export GIT_ICASE_PATHSPECS=1
    run commit Scoped; success
    assert_equal '# Upper' "$(git_notes show HEAD:note.MD)"
    assert_equal '# Changed' "$(git_notes show HEAD:note.md)"
}

storage_tests='test_init_permissions test_new_note test_repeated_title test_unicode_title test_editor_arguments test_editor_failure_preserves_note test_storage_symlink_rejected test_permissive_storage_rejected test_help_without_dependencies test_unquoted_words test_command_options test_invalid_arguments test_real_nvim_privacy test_missing_editor_creates_nothing'
selected=${1:-all}
search_tests='test_browse_selection test_list_notes test_browse_recent_titles test_list_empty test_literal_search test_print_search test_piped_search_prints test_short_commands test_completion_words test_bash_completion test_zsh_completion_syntax test_smart_case_search test_print_search_tty test_show_note test_match_notes test_new_from_pipe test_add_from_pipe test_last_note test_tags_exact test_empty_and_cancelled_picker test_unusual_filenames test_private_search_only test_sanitized_preview test_environment_isolation test_no_color test_optional_emoji test_picker_failure test_editor_replaced_parent test_editor_replaced_root'
git_tests='test_git_init test_commit_notes test_unrelated_staged_refused test_untracked_unrelated_ignored test_parent_repository_rejected test_git_environment_isolation test_push_local_remote test_sync_notes test_push_missing_upstream test_staged_symlink_refused test_unrelated_rename_refused test_git_literal_pathspec_environment test_git_icase_pathspec_environment'
case "$selected" in storage) tests=$storage_tests;; search) tests=$search_tests;; git) tests=$git_tests;; all) tests="$storage_tests $search_tests $git_tests";; *) fail "unknown test group: $selected";; esac
passed=0
failed=0
for test_name in $tests; do
    if (set -e; setup "$test_name"; "$test_name"); then
        printf 'PASS %s\n' "$test_name"
        passed=$((passed + 1))
    else
        printf 'FAIL %s\n' "$test_name"
        failed=$((failed + 1))
    fi
done
printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
