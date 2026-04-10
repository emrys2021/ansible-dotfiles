# Set up fzf appearance, completion trigger, and fish integration.
set -gx FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS \
    --color=fg:#d0d0d0,fg+:#e0e040,bg:#121212,bg+:#262626 \
    --color=hl:#5f87af,hl+:#5fd7ff,info:#afaf87,marker:#87ff00 \
    --color=prompt:#40e040,spinner:#af5fff,pointer:#e0e040,header:#87afaf \
    --color=border:#262626,label:#aeaeae,query:#d9d9d9 \
    --border=double --border-label='' --preview-window=border-rounded --prompt='> ' \
    --marker='+' --pointer='>' --separator='─' --scrollbar='│' \
    --height=40% --layout=reverse --info=right"

# Only enable fzf integration in interactive shells.
if status is-interactive
    # fish exposes its version in $version, e.g. 3.4.1
    set -l v (string split . -- $version)
    set -l major $v[1]
    set -l minor $v[2]
    set -l patch $v[3]

    # fzf --fish requires fish >= 3.4.1
    if test $major -gt 3
        fzf --fish | source
    else if test $major -eq 3
        if test $minor -gt 4
            fzf --fish | source
        else if test $minor -eq 4
            if test $patch -ge 1
                fzf --fish | source
            else
                echo "Skipping fzf fish integration: fish >= 3.4.1 required, current $version" >&2
            end
        else
            echo "Skipping fzf fish integration: fish >= 3.4.1 required, current $version" >&2
        end
    else
        echo "Skipping fzf fish integration: fish >= 3.4.1 required, current $version" >&2
    end
end
