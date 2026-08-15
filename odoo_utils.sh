#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"


cdroot() {
    local root_rel_path=$(get_root_relative_path)
    if [[ $root_rel_path == '' ]]; then
        exit 1
    fi
    cd $root_rel_path
}

cdodoo() {
    local root_rel_path=$(get_root_relative_path)
    if [[ $root_rel_path == '' ]]; then
        exit 1
    fi
    cd $root_rel_path/$community_folder
}

get_root_relative_path() {
    local folder=$(pwd)
    local starting_dir=$folder
    local before_len=-1
    local path='.'
    while [[ ${#folder} -gt 0 && ${#folder} -ne $before_len ]]; do
        if [[ $(is_odoo_repository $path) -eq 1 ]]; then
            echo $path
            return
        fi
        before_len=${#folder}
        folder=${folder%'/'*}
        if [[ $path == '.' ]]; then
            path=".."
        else
            path=../$path
        fi
    done
    echo "Neither $starting_dir, neither the parent folders are an odoo repository" 1>&2
    exit 1
}

is_odoo_repository() {
    local folder=$1
    if [[ -d "${folder}/$community_folder/.git" && -d "${folder}/$enterprise_folder/.git" ]]; then
        echo 1
    else
        echo 0
    fi
}

PREVIOUS_VIRTUAL_ENV=''
python_env() {
    if [[ $venv_python_relativ_path != '' ]]; then
        if [[ $VIRTUAL_ENV == '' || $VIRTUAL_ENV != $PREVIOUS_VIRTUAL_ENV ]]; then
            local relative_path=$(get_root_relative_path)
            if [[ $relative_path == '' ]]; then
                exit 1
            fi
            cd $relative_path
            local venv_dir="$(pwd)"
            cd -
            python_path="$venv_dir"/"$community_folder"/"$venv_python_relativ_path"
            # source "$venv_dir"/"$community_folder"/"$venv_activate_relativ_path"
            PREVIOUS_VIRTUAL_ENV="$VIRTUAL_ENV"
        else
            python_path="$PREVIOUS_VIRTUAL_ENV"
        fi
    elif [[ $python_path == '' ]]; then
        echo "Wrong config: Expected either 'venv_python_relativ_path' or 'python_path' variable to be set" 1>&2
        exit 1
    fi
    $python_path "$@"
}

get_all_modules() {
    local root_rel_path=$(get_root_relative_path)
    if [[ $root_rel_path == '' ]]; then
        exit 1
    fi
    cd "$root_rel_path"/"$community_folder"/addons
    local -n all_of_the_modules=$1
    local module_cnt=0 #${#all_of_the_modules[@]}
    for element in $(ls); do
        if [[ -d $element && -f "$element/__manifest__.py" ]]; then
            all_of_the_modules[$module_cnt]=$element
            module_cnt=$((module_cnt + 1))
        fi
    done
    cd ../../$enterprise_folder
    for element in $(ls); do
        if [[ -d $element && -f "$element/__manifest__.py" ]]; then
            all_of_the_modules[$module_cnt]=$element
            module_cnt=$((module_cnt + 1))
        fi
    done
}
