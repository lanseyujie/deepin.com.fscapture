#!/bin/bash

#   Copyright (C) 2016 Deepin, Inc.
#
#   Author:     Li LongYu <lilongyu@linuxdeepin.com>
#               Peng Hao <penghao@linuxdeepin.com>

PACKAGENAME="deepin.com.fscapture"
BOTTLENAME="Deepin-FSCapture"
WINEPREFIX="$HOME/.deepinwine/$BOTTLENAME"
APPDIR="/opt/deepinwine/apps/$BOTTLENAME"
APPVER="9.0.1deepin0"
APPTAR="files.7z"
WINE_CMD="deepin-wine"

LOG_FILE=$0

init_log_file()
{
    if [ ! -d "$DEBUG_LOG" ];then
        return
    fi

    LOG_DIR=$(realpath $DEBUG_LOG)
    if [ -d "$LOG_DIR" ];then
        LOG_FILE="${LOG_DIR}/${LOG_FILE##*/}.log"
        echo "" > "$LOG_FILE"
        debug_log "LOG_FILE=$LOG_FILE"
    fi
}

debug_log_to_file()
{
    if [ -d "$DEBUG_LOG" ];then
        strDate=$(date)
        echo -e "${strDate}:${1}" >> "$LOG_FILE"
    fi
}

debug_log()
{
    strDate=$(date)
    echo "${strDate}:${1}"
}

init_log_file

_SetRegistryValue()
{
    env WINEPREFIX="$WINEPREFIX" $WINE_CMD reg ADD "$1" /v "$2" /t $3 /d "$4" /f
}

_DeleteRegistry()
{
    env WINEPREFIX="$WINEPREFIX" $WINE_CMD reg DELETE "$1" /f &> /dev/null
}

_SetOverride()
{
    _SetRegistryValue 'HKCU\Software\Wine\DllOverrides' "$2" REG_SZ "$1"
}

HelpApp()
{
	echo " Extra Commands:"
	echo " -r/--reset     Reset app to fix errors"
	echo " -e/--remove    Remove deployed app files"
	echo " -h/--help      Show program help info"
}

FixLink()
{
    if [ -d ${WINEPREFIX} ]; then
        CUR_DIR=$PWD
        cd "${WINEPREFIX}/dosdevices"
        rm c: z:
        ln -s -f ../drive_c c:
        ln -s -f / z:
        cd $CUR_DIR
        ls -l "${WINEPREFIX}/dosdevices"
    fi
}

urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

uridecode()
{
    local path=$(urldecode "$1")
    path=${path/file:\/\//}
    echo $path
}

get_bottle_path_by_process_id()
{
    PID_LIST="$1"
    PREFIX_LIST=""

    for pid_var in $PID_LIST ; do
        WINE_PREFIX=$(xargs -0 printf '%s\n' < /proc/$pid_var/environ | grep WINEPREFIX)
        WINE_PREFIX=${WINE_PREFIX##*=}
        for path in $(echo -e $PREFIX_LIST) ; do
            if [[ $path == "$WINE_PREFIX" ]]; then
                WINE_PREFIX=""
            fi
        done
        if [ -d "$WINE_PREFIX" ]; then
            debug_log_to_file "found $pid_var : $WINE_PREFIX"
            PREFIX_LIST+="\n$WINE_PREFIX"
        fi
    done
    echo -e $PREFIX_LIST | grep $HOME
}

get_bottle_path_by_process_name()
{
    PID_LIST=$(ps -ef | grep -E -i "c:.*${1}" | grep -v grep | awk '{print $2}')
    debug_log_to_file "get pid list: $PID_LIST"
    get_bottle_path_by_process_id "$PID_LIST"
}

CallApp()
{
    FixLink
    debug_log "CallApp $BOTTLENAME $1 $2"

    if [ "autostart" == "$1" ]; then
        env WINEPREFIX="$WINEPREFIX" $WINE_CMD /opt/deepinwine/tools/startbottle.exe &
    else
        env WINEPREFIX="$WINEPREFIX" $WINE_CMD "c:\\Program Files\\FastStone Capture\\FSCapture.exe" &
    fi
}

ExtractApp()
{
	mkdir -p "$1"
	7z x "$APPDIR/$APPTAR" -o"$1"
	mv "$1/drive_c/users/@current_user@" "$1/drive_c/users/$USER"
	sed -i "s#@current_user@#$USER#" $1/*.reg
}

DeployApp()
{
	ExtractApp "$WINEPREFIX"
	echo "$APPVER" > "$WINEPREFIX/PACKAGE_VERSION"
}

RemoveApp()
{
	rm -rf "$WINEPREFIX"
}

ResetApp()
{
	debug_log "Reset $PACKAGENAME....."
	read -p "*	Are you sure?(Y/N)" ANSWER
	if [ "$ANSWER" = "Y" -o "$ANSWER" = "y" -o -z "$ANSWER" ]; then
		EvacuateApp
		DeployApp
		CallApp
	fi
}

UpdateApp()
{
	if [ -f "$WINEPREFIX/PACKAGE_VERSION" ] && [ "$(cat "$WINEPREFIX/PACKAGE_VERSION")" = "$APPVER" ]; then
		return
	fi
	if [ -d "${WINEPREFIX}.tmpdir" ]; then
		rm -rf "${WINEPREFIX}.tmpdir"
	fi
	ExtractApp "${WINEPREFIX}.tmpdir"
	/opt/deepinwine/tools/updater -s "${WINEPREFIX}.tmpdir" -c "${WINEPREFIX}" -v
	rm -rf "${WINEPREFIX}.tmpdir"
	echo "$APPVER" > "$WINEPREFIX/PACKAGE_VERSION"
}

RunApp()
{
    progpid=$(ps -ef | grep "zenity --progress --title=${BOTTLENAME}" | grep -v grep)
    debug_log "run ${BOTTLENAME} progress pid $progpid"
    if [ -n "$progpid" ]; then
        debug_log "$BOTTLENAME is running"
        exit 0
    fi
 	if [ -d "$WINEPREFIX" ]; then
        UpdateApp | progressbar $BOTTLENAME "更新$BOTTLENAME中..."
 	else
        DeployApp | progressbar $BOTTLENAME "初始化$BOTTLENAME中..."
 	fi
    CallApp "$1" "$2"
}

CreateBottle()
{
    if [ -d "$WINEPREFIX" ]; then
        UpdateApp
    else
        DeployApp
    fi
}

# Check if some visual feedback is possible
if command -v zenity >/dev/null 2>&1; then
	progressbar()
	{
		WINDOWID="" zenity --progress --title="$1" --text="$2" --pulsate --width=400 --auto-close --no-cancel ||
		WINDOWID="" zenity --progress --title="$1" --text="$2" --pulsate --width=400 --auto-close
	}

else
	progressbar()
	{
		cat -
	}
fi

debug_log "Run $BOTTLENAME $APPVER"

if [ -z "$1" ]; then
	RunApp
	exit 0
fi
case $1 in
	"-r" | "--reset")
		ResetApp
		;;
	"-c" | "--create")
		CreateBottle
		;;
	"-e" | "--remove")
		RemoveApp
		;;
	"-u" | "--uri")
		RunApp "$2" "$3"
		;;
	"-h" | "--help")
		HelpApp
		;;
	*)
		echo "Invalid option: $1"
		echo "Use -h|--help to get help"
		exit 1
		;;
esac
exit 0
