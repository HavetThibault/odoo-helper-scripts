#!/bin/bash

python_relative_path=.venv/bin
python_parent_relativ_path=odoo/$python_relative_path

cdroot() {
    local root_rel_path=$(get_root_relative_path || exit $?)
    cd $root_rel_path
}

cdodoo() {
    local root_rel_path=$(get_root_relative_path || exit $?)
    cd $root_rel_path/odoo
}

get_root_relative_path() {
    local working_dir=$(pwd)
    local working_folder=${working_dir##*'/'}
    if [[ ($working_folder = 'enterprise' || $working_folder = 'upgrade' || $working_folder = 'odoo') && $(is_odoo_repository "..") -eq 1 ]]; then
        echo ..
    elif [[ $(is_odoo_repository $working_dir) -eq 1 ]]; then
        echo .
    else
        echo "Neither $working_dir, neither the parent folder is a odoo repository" 1>&2
        exit 1
    fi
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
    if [[ -d "${folder}/odoo/.git" && -d "${folder}/enterprise/.git" ]]; then
        echo 1
    else
        echo 0
    fi
}

python_env() {
    python_path=$(get_python_path)
    $python_path "$@"
}

get_python_path() {
    local relative_path=$(get_root_relative_path_2)/odoo
    local exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi
    echo ${relative_path}/${python_relative_path}/python
}

get_all_modules() {
    local root_rel_path=$(get_root_relative_path || exit $?)
    cd $root_rel_path/odoo/addons
    local -n all_of_the_modules=$1
    local module_cnt=0 #${#all_of_the_modules[@]}
    for element in $(ls); do
        if [[ -d $element && -f "$element/__manifest__.py" ]]; then
            all_of_the_modules[$module_cnt]=$element
            module_cnt=$((module_cnt + 1))
        fi
    done
    cd ../../enterprise
    for element in $(ls); do
        if [[ -d $element && -f "$element/__manifest__.py" ]]; then
            all_of_the_modules[$module_cnt]=$element
            module_cnt=$((module_cnt + 1))
        fi
    done
}

function1() {
    log=${1}.log
    exec 4>&2 3>&1 1>>$log 2>&1 # save 1 and 2 to 3 and 4
    echo checking $log >&3
    echo txt to $log
    exec 1>&3 2>&4 3>&- 4>&- # restore 1 and 2
}
