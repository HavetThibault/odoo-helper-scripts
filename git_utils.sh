#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/number_utils.sh"

origin_version_prefix=[0-9]{2}\.0
saas_version_prefix=saas-[0-9]{2}\.[0-9]

get_branch_source() {
    local branch=$1
    if [[ $branch =~ ^${origin_version_prefix}.*$ ]]; then
        echo ${branch%%'-'*}
    elif [[ $branch =~ ^$saas_version_prefix.*$ ]]; then
        local no_saas_branch=${branch#*'-'}
        local version=${no_saas_branch%%'-'*}
        echo saas-$version
    elif [[ $branch =~ ^master.*$ ]]; then
        echo master
    else
        echo "Could not find the source repository of the branch $branch" 1>&2
        exit 1
    fi
}

is_source_branch() {
    if [[ $branch =~ ^${origin_version_prefix}$ || $branch =~ ^$saas_version_prefix$ || $branch = master ]]; then
        echo 1
    else
        echo 0
    fi
}

# TODO: refiler la liste des branches possibles
# Pour pouvoir par exemple lister les branches pas uniquement dans le répertoire actuel
select_branch() {
    local i=1
    echo "~~~ Please pick a branch"
    declare -a branchs
    for branch in $(git branch | sed 's/*/ /g'); do
        echo "$i) $branch"
        branchs[$i]=$branch
        i=$((i+1))
    done

    local valid_answer=0
    while [[ $valid_answer -ne 1 ]]; do
        read answer
        local valid_input=$(is_number $answer)
        if [[ $valid_input -eq 1 ]]; then
            if [[ $answer -ge 1 && $answer -le ${#branchs[@]} ]]; then
                echo "${branchs[$answer]}"
                valid_answer=1
            fi
        fi
        if [[ $valid_answer -ne 1 ]]; then
            echo "Please enter a valid input: 0 < input < $((${#branchs[@]} + 1))"
        fi
    done
}

select_get_branch() {
    local select_output=$(select_branch | tee /dev/tty)
    # Pay attention when displaying select_output, sometimes a '\n' is displayed as a space !
    echo ${select_output##*$'\n'}
}

get_branch_remote() {
    local branch=$1
    local source=$(get_branch_source $branch)

    local exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi

    if [[ $source == $branch ]]; then
        echo "origin"
    else
        echo "dev"
    fi
}

local_branch_exists() {
    local local_branch=$1
    for branch in $(git branch | sed 's/*/ /g'); do
        if [[ $branch == $local_branch ]]; then
            echo 1
            return
        fi
    done
    echo 0
}

remote_branch_exists() {
    local branch=$1
    local remote_ls=$(git ls-remote dev ${branch})
    if [[ ${#remote_ls} -eq 0 ]]; then
        echo 0
    else
        echo 1
    fi
}

get_current_branch() {
    local gs_line=$(git status | head -1)
    echo ${gs_line##*' '}
}

changes_exist() {
    if [[ $(git status | tail -1) == "nothing to commit, working tree clean" ]]; then
        echo 0
    else
        echo 1
    fi
}

fetch_if_necessary_switch() {
    local branch=$1
    local remote=$(get_branch_remote $branch)
    if [[ $(local_branch_exists $branch) -eq 0 ]]; then
        git fetch $remote $branch
        if [[ $(get_branch_source $branch) = $branch ]]; then
            git switch -c $branch --track $remote/$branch
            return 0
        fi
    fi
    git switch $branch
}
