set -g renpy_data $HOME/.local/share/renpy

function _renpy_index_update
    argparse -i f/force -- $argv

    command mkdir -p $renpy_data
    set -l index $renpy_data/.index
    set -l today (date "+%Y-%m-%d")
    mkdir -p "$renpy_data"

    set -l outdated 0
    if not test -f "$index" -o (date -r "$index" "+%Y-%m-%d") != "$today"
        set outdated 1
    end

    if test "$outdated" -eq 1; or set -q _flag_force
        curl -s https://www.renpy.org/dl/ \
            | string match -rag '>(\d+\.\d+\.\d+)/<' \
            | sort -uV >"$index"
    end
end

function _renpy_version_match -a v
    echo $v \
        | string replace -r -- '^v?(\d+|\d+\.\d+)$' '$1.' \
        | string escape --style regex \
        | read -l regex
    echo "^$regex"
end

function _renpy_version_list
    for f in $renpy_data/renpy-*.tar.gz
        echo $f \
            | string replace $renpy_data/renpy- '' \
            | string replace .tar.gz ''
    end | sort -uV
end

function _renpy_build -a v
    test -n "$v" || begin
        echo "Version required" >&2
        return 1
    end

    _renpy_version_list | sort -ruV | string match -re (_renpy_version_match $v) | read -l V

    if test -n "$V"
        echo Found renpy-$V locally
        return
    end

    if test -z "$V"
        _renpy_index_update

        cat $renpy_data/.index | sort -ruV | string match -re (_renpy_version_match $v) | read -l V

        echo Downloading SDK v$V
        set -l build_dir (mktemp -d)
        curl --progress-bar -L "https://renpy.org/dl/$V/renpy-$V-sdk.tar.bz2" | tar -xj -C "$build_dir" --strip-components 1 || begin
            echo Failed to download SDK >&2
            return 1
        end

        echo Building renpy-$V.app
        mkdir $build_dir/renpy.app/Contents/Resources/{autorun,lib}
        mv $build_dir/renpy $build_dir/renpy.py $build_dir/renpy.app/Contents/Resources/autorun
        mv $build_dir/lib/python* $build_dir/renpy.app/Contents/Resources/lib
        cp $HOME/.config/fish/functions/renpy_patch.py.template $build_dir/renpy.app/Contents/Resources/autorun/renpy_patch.py
        sed -i '' -E 's/^([[:space:]]*)(import renpy\.bootstrap)/\1\2\n\1import renpy_patch/' $build_dir/renpy.app/Contents/Resources/autorun/renpy.py

        echo Codesigning renpy-$V.app
        codesign --force --deep --sign RenPy "$build_dir/renpy.app" 2>/dev/null; or begin
            echo Failed to codesign app >&2
            return 1
        end

        echo Archiving renpy-$V.app
        tar -czf "$renpy_data/renpy-$V.tar.gz" -C $build_dir renpy.app
    end
end

function _renpy_use -a v
    if test -z "$v" -a -d renpy.app
        if test (count renpy.app/Contents/Resources/lib/python3.*) -gt 0
            set v 8
        else if test (count renpy.app/Contents/Resources/lib/python2.*) -gt 0
            set v 7
        end
    end
    _renpy_build $v
    _renpy_version_list | sort -ruV | string match -re (_renpy_version_match $v) | read -l V

    set -l tmp_dir (command mktemp -d)
    command tar -xzf $renpy_data/renpy-$V.tar.gz -C "$tmp_dir"
    command rsync -a --delete "$tmp_dir/renpy.app" ./
    rm -rf $tmp_dir
end

function renpy -a cmd
    switch "$cmd"
        case list
            _renpy_version_list
        case build
            _renpy_build $argv[2..]
        case use
            _renpy_use $argv[2..]
    end
end
