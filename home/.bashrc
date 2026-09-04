# Interactive check
[[ $- != *i* ]] && return

[ -f /opt/miniconda3/etc/profile.d/conda.sh ] && source /opt/miniconda3/etc/profile.d/conda.sh

alias vi='nvim'
