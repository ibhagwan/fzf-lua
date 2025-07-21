#!/bin/sh

BASEDIR=$(cd "$(dirname "$0")" ; pwd -P)
GETOPT=getopt

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options"
    echo "-h, --help            Show this help"
    echo "-d, --debug           Debug level [0|1|2|false|true|v]"
    echo ""
    echo "Display Options"
    echo "-c, --cwd             Working Directory"
    echo "-x, --cmd             Executed Command (default: fd --color=never)"
    echo "-g, --git-icons       Git icons [false|true] (default:false)"
    echo "-f, --file-icons      File icons [false|true] (default:true)"
    echo "--color               Color icons [false|true] (default:true)"
}

# saner programming env: these switches turn some bugs into errors
set -o noclobber -o nounset

# MacOs: `brew install gnu-getopt && brew link --force gnu-getopt`
if [ -x /usr/local/bin/getopt ]; then
    GETOPT=/usr/local/bin/getopt
fi

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
$GETOPT --test > /dev/null 
if [ $? -ne 4 ]; then
    echo "`$GETOPT --test` failed in this environment."
    exit 1
fi

OPTIONS=hd:c:x:f:g:
LONGOPTS=help,debug:,cwd:,file-icons:,git-icons:,color:,cmd:

PARSED=$($GETOPT --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    usage;
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

debug="false"
cwd= cmd=
git_icons="false"
file_icons="true"
color_icons="true"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            usage;
            exit 0
            ;;
        -d|--debug)
            debug="$2"
            shift 2
            ;;
        -c|--cwd)
            cwd="$2"
            shift 2
            ;;
        -x|--cmd)
            cmd="$2"
            shift 2
            ;;
        -f|--file-icons)
            case $2 in
                "true"|"srv"|"mini"|"devicons")
                    file_icons="$2"
                    ;;
                *)
                    file_icons="nil"
                    ;;
            esac
            shift 2
            ;;
        -g|--git-icons)
            git_icons="$2"
            shift 2
            ;;
        --color)
            color_icons="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            # never get here!
            echo "error: error while parsing command line arguments"
            usage;
            exit 3
            ;;
    esac
done

# handle non-option arguments
if [ $# -gt 0 ]; then
    echo "error: unrecgonized option"
    usage;
    exit 4
fi

ICONS_PATH=nil
ICONS_SETUP=nil

if [ $file_icons != "nil" ]; then
    if [ $file_icons != "mini" ]; then
        if [ -d "${BASEDIR}/../deps/nvim-web-devicons" ]; then
            ICONS_PATH="${BASEDIR}/../deps/nvim-web-devicons"
        else
            ICONS_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/nvim-web-devicons"
        fi
        ICONS_SETUP="${BASEDIR}/devicons.lua"
    else
        if [ -d "${BASEDIR}/../deps/mini.nvim" ]; then
            ICONS_PATH="${BASEDIR}/../deps/mini.nvim"
        else
            ICONS_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/mini.nvim"
        fi
    fi
fi

# VIMRUNTIME=/usr/share/nvim/runtime \
nvim -u NONE -l ${BASEDIR}/../lua/fzf-lua/spawn.lua "return
  -- opts
  {
    g = {
      _fzf_lua_server = #[[${FZF_LUA_SERVER:-}]] > 0 and [[${FZF_LUA_SERVER:-}]] or nil,
      _devicons_path = [[${ICONS_PATH}]],
      _devicons_setup = [[${ICONS_SETUP}]],
    },
    debug = [[$debug]] == [[v]] and [[v]] or $debug,
    file_icons = [[${file_icons}]] == true or [[${file_icons}]],
    git_icons = ${git_icons},
    color_icons = ${color_icons},
    cmd = [[${cmd:-fd --color=never}]],
    cwd = vim.fn.expand([[${cwd:-$BASEDIR}]]),
    fn_transform = [==[
      return require(\"fzf-lua.make_entry\").file
    ]==],
    fn_preprocess = [==[
      return require(\"fzf-lua.make_entry\").preprocess
    ]==]
  }
"
