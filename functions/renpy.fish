function renpy_index_update
    argparse -i f/force -- $argv

    set -l data $HOME/.local/share/renpy && command mkdir -p $data
    set -l index $data/.index
    set -l today (date "+%Y-%m-%d")
    mkdir -p "$data"

    set -l outdated 0
    if not test -f "$index" -o (date -r "$index" "+%Y-%m-%d") != "$today"
        set outdated 1
    end

    if test "$outdated" -eq 1; or set -q _flag_force
        curl -s https://www.renpy.org/dl/ \
            | string match -rag '>(\d+\.\d+\.\d+)/<' \
            | sort -ruV >"$index"
    end
end

function renpy_version_resolve -a v
    renpy_index_update

    set -l index $HOME/.local/share/renpy/.index

    switch "$v"
        case ""
            head -n1 $index
        case "*.*.*"
            string match "$v" <$index | head -n1
        case "*.*"
            string match "$v.*" <$index | head -n1
        case "*"
            string match "$v.*.*" <$index | head -n1
    end
end

function renpy_build -a v
    set -l builds $HOME/.local/share/renpy/builds && command mkdir -p $builds
    ls $builds \
        | string match -rag 'renpy-(\d+\.\d+\.\d+)\.tar.gz' \
        | sort -ruV \
        | while read -l V
        switch "$v"
            case ""
                echo $V
            case "*.*.*"
                string match "$v" $V
            case "*.*"
                string match "$v.*" $V
            case "*"
                string match "$v.*.*" $V
        end
    end | head -n1 | read -l V

    if test -z "$V"
        renpy_version_resolve "$v" | read V

        echo Downloading SDK v$V
        set -l build_dir (mktemp -d)
        curl --progress-bar -L "https://renpy.org/dl/$V/renpy-$V-sdk.tar.bz2" | tar -xj -C "$build_dir" --strip-components 1 || begin
            echo "Error: Failed to download SDK" >&2
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
            echo "Warning: Codesigning failed"
            return 1
        end

        echo Archiving $builds/renpy-$V.app
        tar -czf "$builds/renpy-$V.tar.gz" -C $build_dir renpy.app
    end
end

function renpy -a cmd
    renpy_$cmd $argv[2..]
end
