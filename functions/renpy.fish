set -g renpy_data $HOME/.local/share/renpy

function _renpy_index_update
    argparse -i f/force -- $argv

    command mkdir -p $renpy_data
    set -l index $renpy_data/.index
    set -l today (date "+%Y-%m-%d")

    set -l outdated 0
    if not test -f "$index"; or test (date -r "$index" "+%Y-%m-%d") != "$today"
        set outdated 1
    end

    if test "$outdated" -eq 1; or set -q _flag_force
        command curl -s https://www.renpy.org/dl/ \
            | string match -rag '>(\d+\.\d+\.\d+)/<' \
            | command sort -uV >"$index"
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
    argparse -i f/full -- $argv
    for f in $renpy_data/renpy-*.zip
        set -l V (string replace -r '.*/renpy-(.*)\.zip$' '$1' $f)
        echo $V
    end | command sort -uV | while read -l V
        if set -q _flag_full
            set -l python_version (command unzip -Z1 $renpy_data/renpy-$V.zip "*/lib/python*/*" | string match -rg 'python(\d+\.\d+)' | command head -n1)
            echo "$V (python$python_version)"
        else
            echo $V
        end
    end
end

function _renpy_build -a v
    test -n "$v" || begin
        echo "Version required" >&2
        return 1
    end

    _renpy_version_list | command sort -ruV | string match -re (_renpy_version_match $v) | read -l V
    if test -n "$V"
        set -l python_version (command unzip -Z1 $renpy_data/renpy-$V.zip "*/lib/python*/*" | string match -rg 'python(\d+\.\d+)' | command head -n1)
        echo "Found renpy-$V (python$python_version) locally"
        return
    end

    _renpy_index_update
    cat $renpy_data/.index | command sort -ruV | string match -re (_renpy_version_match $v) | read -l V

    set -l cache_dir "$HOME/.cache/renpy"
    set -l cached_file "$cache_dir/renpy-$V-sdk.zip"
    set -l build_dir (command mktemp -d)

    command mkdir -p $cache_dir

    if not test -f "$cached_file"
        echo "Downloading SDK v$V"
        if not command curl --progress-bar -L -o "$cached_file" "https://renpy.org/dl/$V/renpy-$V-sdk.zip"
            echo "Failed to download SDK" >&2
            return 1
        end
    end

    set -l python_version (command unzip -Z1 "$cached_file" "*/lib/python*/*" | string match -rg 'python(\d+\.\d+)' | command head -n1)
    echo "Building renpy-$V.app (python$python_version)"

    if not command bsdtar -xj -C "$build_dir" --strip-components 1 -f "$cached_file"
        echo "Failed to extract SDK" >&2
        command rm -f "$cached_file"
        return 1
    end

    set -l resources_dir $build_dir/renpy.app/Contents/Resources
    command mkdir -p $resources_dir/{autorun,lib}
    command mv $build_dir/renpy $build_dir/renpy.py $resources_dir/autorun
    command mv $build_dir/lib/python$python_version $resources_dir/lib
    command cp $HOME/.config/fish/functions/renpy_patch.py.template $resources_dir/autorun/renpy_patch.py
    command sed -i '' -E 's/^([[:space:]]*)(import renpy\.bootstrap)/\1\2\n\1import renpy_patch/' $resources_dir/autorun/renpy.py

    echo "Codesigning renpy-$V.app"
    command codesign --force --deep --sign RenPy "$build_dir/renpy.app" 2>/dev/null; or begin
        echo "Failed to codesign app" >&2
        return 1
    end

    echo "Archiving renpy-$V.zip"
    command bsdtar -ca -C "$build_dir" -f "$renpy_data/renpy-$V.zip" renpy.app

    rm -rf $build_dir
end

function _renpy_launch -a v
    test -n "$v" || begin
        echo "Version required" >&2
        return 1
    end

    _renpy_version_list | command sort -ruV | string match -re (_renpy_version_match $v) | read -l V
    test -n "$V" || _renpy_build $v
    _renpy_version_list | command sort -ruV | string match -re (_renpy_version_match $v) | read -l V

    if test -n "$V"
        set -l python_version (command unzip -Z1 $renpy_data/renpy-$V.zip "*/lib/python*/*" | string match -rg 'python(\d+\.\d+)' | command head -n1)
        echo "Launching renpy-$V (python$python_version)"

        set -l tmp_dir (command mktemp -d)
        command unzip -q "$renpy_data/renpy-$V.zip" -d "$tmp_dir"
        BASE_DIR=$PWD $tmp_dir/renpy.app/Contents/MacOS/renpy
    end
end

function _renpy_use -a v
    if test -z "$v" -a -d renpy.app
        if test (count renpy.app/Contents/Resources/lib/python3.*) -gt 0
            set v 8
        else if test (count renpy.app/Contents/Resources/lib/python2.*) -gt 0
            # 7.8.7 has memory leak issue
            set v 7.8.6
        end
    end

    _renpy_build $v
    _renpy_version_list | command sort -ruV | string match -re (_renpy_version_match $v) | read -l V

    command rm -rf ./renpy.app
    command unzip -q "$renpy_data/renpy-$V.zip" -d .
end

function renpy -a cmd
    switch "$cmd"
        case list
            _renpy_version_list -f
        case build
            _renpy_build $argv[2..]
        case launch
            _renpy_launch $argv[2..]
        case use
            _renpy_use $argv[2..]
    end
end
