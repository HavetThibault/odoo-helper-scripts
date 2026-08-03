#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"


cdroot() {
    local root_rel_path=$(get_root_relative_path_2 || exit $?)
    cd $root_rel_path
}

cdodoo() {
    local root_rel_path=$(get_root_relative_path_2 || exit $?)
    cd $root_rel_path/$community_folder
}

get_root_relative_path_2() {
    local folder=$(pwd)
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
    echo "Neither $working_dir, neither the parent folder is a odoo repository" 1>&2
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

python_env() {
    local python_path=$(get_python_path)
    $python_path "$@"
}

get_python_path() {
    if [[ $venv_folder_relative_path != '' ]]; then
        local relative_path=$(get_root_relative_path_2)
        local exit_status=$?
        if [[ $exit_status -ne 0 ]]; then
            exit $exit_status
        fi
        echo ${relative_path}/${venv_folder_relative_path}/python
    elif [[ $python_path != '' ]]; then
        echo $python_path
    else
        echo "Wrong config: Expected either 'venv_folder_relative_path' or 'python_path' variable to be set" 1>&2
        exit 1
    fi
}

get_all_modules() {
    local root_rel_path=$(get_root_relative_path_2 || exit $?)
    cd $root_rel_path/$community_folder/addons
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
