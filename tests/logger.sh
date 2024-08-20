debug() {
    if [ -n "$DEBUG" ]; then
        echo -e "\033[00;34m[DEBUG]   $1\033[0m"
    fi
}

info() {
    echo -e "\033[01;34m[INFO]    $1\033[0m"
}

warn() {
    echo -e "\033[01;33m[WARN]    $1\033[0m"
}

error() {
    echo -e "\033[01;31m[ERROR]   $1\033[0m"
}

success() {
    echo -e "\033[01;32m[SUCCESS] $1\033[0m"
}


red() {
    echo -e "\033[00;31m$1\033[0m"
}

green() {
    echo -e "\033[00;32m$1\033[0m"
}

yellow() {
    echo -e "\033[00;33m$1\033[0m"
}

blue() {
    echo -e "\033[00;34m$1\033[0m"
}

bold() {
    echo -e "\033[0;1m$1\033[0m"
}

WIDTH=80
report() {
    filename=$1
    message=$2
    status=${3:-""}
    spaces=$((WIDTH - ${#message} - ${#status} - 3))
    echo -n " " >> "$filename"
    echo -n "$message" >> "$filename"
    if [ -n "$status" ]; then
        for i in $(seq 1 $spaces); do
            echo -n "." >> "$filename"
        done
    else
        echo "" >> "$filename"
    fi
    if [ -n "$status" ]; then
        if [ "$status" == "PASSED" ]; then
            echo "$(green "$status")" >> "$filename"
        else
            echo "$(red "$status")" >> "$filename"
        fi
    fi
}
