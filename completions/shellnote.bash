# Bash completion for shellnote and the suggested sn alias.
# Load it from ~/.bashrc:
#   source ~/.local/shellnote/completions/shellnote.bash
# compgen only splits fixed option words here, and Bash 3.2 has no mapfile.
# shellcheck disable=SC2207

_shellnote_words() {
    local cur=$1 word
    shift
    local nocase=0
    shopt -q nocasematch && nocase=1
    shopt -s nocasematch
    # Titles are matched by hand because compgen -W would expand $(...) inside note titles.
    while IFS= read -r word; do
        if [[ "$word" == *"$cur"* ]]; then
            printf -v word '%q' "$word"
            COMPREPLY+=("$word")
        fi
    done < <(shellnote __complete "$@" 2>/dev/null)
    [ "$nocase" = 1 ] || shopt -u nocasematch
}

_shellnote() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
    local command=${COMP_WORDS[1]:-}
    COMPREPLY=()
    if [ "$COMP_CWORD" = 1 ]; then
        COMPREPLY=($(compgen -W 'new edit last show add list find tags init commit push sync help' -- "$cur"))
        return
    fi
    # Readline passes the typed word with its backslashes, so drop them before matching.
    cur=${cur//\\/}
    case "$command" in
        e|edit|s|show|a|add) _shellnote_words "$cur" titles;;
        l|list)
            case "$prev" in
                -t|--tag) _shellnote_words "$cur" tags;;
                *) COMPREPLY=($(compgen -W '-t --tag' -- "$cur"));;
            esac;;
        f|find) [[ "$cur" != -* ]] || COMPREPLY=($(compgen -W '-p --print' -- "$cur"));;
        t|tags) [ "$COMP_CWORD" != 2 ] || _shellnote_words "$cur" tags;;
        init) COMPREPLY=($(compgen -W '--git' -- "$cur"));;
    esac
}

complete -F _shellnote shellnote sn
