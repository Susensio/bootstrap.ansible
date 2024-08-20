bin_path="/opt/nvim/bin"
if [ -n "${PATH##*${bin_path}}" ] && [ -n "${PATH##*${bin_path}:*}" ]; then
    export PATH="${bin_path}:$PATH"
fi
